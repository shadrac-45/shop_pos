import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/features/auth/screens/admin_login_screen.dart';
import 'package:shop_pos/features/auth/screens/role_select_screen.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/database/migrations.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/providers/sync_provider.dart';
import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/services/stock_alert_service.dart';
import 'package:shop_pos/core/services/notification_service.dart';
import 'package:shop_pos/core/services/session_manager.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        debugPrintStack(stackTrace: details.stack);
      };

      // Initialize Notification Service
      NotificationService? notificationService;
      try {
        notificationService = NotificationService();
        await notificationService.init();
      } catch (e, st) {
        debugPrint('[ShopPOS] NotificationService.init() failed: $e\n$st');
        notificationService = NotificationService();
      }

      // Initialize Isar Database
      late Isar isar;
      try {
        final dir = await getApplicationDocumentsDirectory();
        isar = await Isar.open(
          allSchemas,
          directory: dir.path,
          inspector: kDebugMode,
        );
      } catch (e, st) {
        debugPrint('[ShopPOS] Isar.open() failed: $e\n$st');
        rethrow;
      }

      await DataMigrations.run(isar);

      // Check if first-run setup has been completed
      bool setupCompleted = false;
      try {
        final settings = await isar.storeSettings.get(1);
        setupCompleted = settings?.setupCompleted ?? false;
      } catch (e) {
        debugPrint('[ShopPOS] Setup state check failed: $e');
      }

      // Daily notification about expiring and low-stock products.
      if (setupCompleted) {
        unawaited(StockAlertService.notifyIfDue(isar, notificationService));
      }

      runApp(
        ProviderScope(
          overrides: [
            isarProvider.overrideWithValue(isar),
            notificationServiceProvider.overrideWithValue(notificationService),
          ],
          child: ShopPOSApp(setupCompleted: setupCompleted),
        ),
      );
    },
    (error, stack) {
      debugPrint('[ShopPOS] UNCAUGHT ERROR: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

/// Root navigator, so app-wide events (logout, inactivity timeout) can
/// reset navigation without a BuildContext from the current screen.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class ShopPOSApp extends ConsumerWidget {
  final bool setupCompleted;
  const ShopPOSApp({super.key, required this.setupCompleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Single logout path: whenever the signed-in user is cleared (sign-out
    // button, Settings, or the inactivity timeout), go back to the role
    // picker and drop every screen and dialog that was open.
    ref.listen(currentUserProvider, (previous, next) {
      if (previous != null && next == null) {
        rootNavigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
          (_) => false,
        );
      }
    });

    // Keeps cloud sync running in the background (it starts and stops
    // itself as users sign in and out).
    ref.listen(syncProvider, (_, __) {});

    return MaterialApp(
      title: 'ShopPOS',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.lightTheme,
      // Any touch anywhere counts as activity for the inactivity timeout.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => ref.read(sessionManagerProvider).recordActivity(),
        child: child,
      ),
      // ── Routing ─────────────────────────────────────────────
      // First launch (setup not done) → Admin email+pass login → Wizard
      // Subsequent launches (setup done) → Role selector login screen
      home: setupCompleted
          ? const RoleSelectScreen()
          : const AdminLoginScreen(setupAlreadyDone: false),
    );
  }
}
