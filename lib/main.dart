import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/features/auth/screens/admin_login_screen.dart';
import 'package:shop_pos/features/auth/screens/role_select_screen.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/services/notification_service.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/products/services/csv_import_service.dart';

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
          [
            ProductSchema,
            BatchSchema,
            SaleSchema,
            AppUserSchema,
            StoreSettingsSchema,
          ],
          directory: dir.path,
          inspector: kDebugMode,
        );
      } catch (e, st) {
        debugPrint('[ShopPOS] Isar.open() failed: $e\n$st');
        rethrow;
      }

      // Check if first-run setup has been completed
      bool setupCompleted = false;
      try {
        final settings = await isar.storeSettings.get(1);
        setupCompleted = settings?.setupCompleted ?? false;
      } catch (e) {
        debugPrint('[ShopPOS] Setup state check failed: $e');
      }

      // Seed default users ONLY if the users table is genuinely empty.
      // Never auto-wipe existing users.
      try {
        await _seedDefaultUsersIfEmpty(isar);
      } catch (e, st) {
        debugPrint('[ShopPOS] _seedDefaultUsersIfEmpty() failed: $e\n$st');
      }

      // Seed default product catalog ONLY if the products table is empty.
      // Populates 8 sample Ghana retail items with stock batches.
      try {
        await _seedDefaultProductsIfEmpty(isar);
      } catch (e, st) {
        debugPrint('[ShopPOS] _seedDefaultProductsIfEmpty() failed: $e\n$st');
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

/// Seeds the default owner/cashier accounts ONLY when the appUsers table
/// is completely empty (i.e. a genuinely fresh install/DB).
Future<void> _seedDefaultUsersIfEmpty(Isar isar) async {
  final userCount = await isar.appUsers.count();
  if (userCount > 0) {
    return;
  }

  await isar.writeTxn(() async {
    final owner = AppUser()
      ..name = 'Shop Owner'
      ..role = 'owner'
      ..isActive = true
      ..pinHash = HashHelpers.hashPin('1234');
    await isar.appUsers.put(owner);

    final cashier = AppUser()
      ..name = 'Cashier'
      ..role = 'cashier'
      ..isActive = true
      ..pinHash = HashHelpers.hashPin('0000');
    await isar.appUsers.put(cashier);
  });

  debugPrint('[ShopPOS] Fresh install detected — seeded owner + cashier.');
}

/// Seeds sample Ghana retail products with stock batches ONLY when
/// the products table is completely empty.
Future<void> _seedDefaultProductsIfEmpty(Isar isar) async {
  final productCount = await isar.products.count();
  if (productCount > 0) {
    return;
  }

  final imported = await CsvImportService.seedSampleProducts(isar);
  debugPrint('[ShopPOS] Fresh catalog detected — seeded $imported sample products.');
}

class ShopPOSApp extends StatelessWidget {
  final bool setupCompleted;
  const ShopPOSApp({super.key, required this.setupCompleted});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopPOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // ── Routing ─────────────────────────────────────────────
      // First launch (setup not done) → Admin email+pass login → Wizard
      // Subsequent launches (setup done) → Role selector login screen
      home: setupCompleted
          ? const RoleSelectScreen()
          : const AdminLoginScreen(setupAlreadyDone: false),
    );
  }
}
