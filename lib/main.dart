import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/app_user.dart';
import 'models/batch.dart';
import 'models/product.dart';
import 'models/sale.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'providers/database_provider.dart';
import 'providers/notification_provider.dart';
import 'utils/hash_helpers.dart';

void main() {
  // Catch all uncaught async errors in the Zone — prevents silent blank screens
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Forward Flutter framework errors to the Zone error handler
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        debugPrintStack(stackTrace: details.stack);
      };

      // Initialize Notification Service — wrapped in try/catch so any
      // permission denial or plugin error doesn't block the startup flow.
      NotificationService? notificationService;
      try {
        notificationService = NotificationService();
        await notificationService.init();
      } catch (e, st) {
        debugPrint('[ShopPOS] NotificationService.init() failed: $e\n$st');
        notificationService = NotificationService(); // use uninitialised fallback
      }

      // Initialize Isar Database
      late Isar isar;
      try {
        final dir = await getApplicationDocumentsDirectory();
        isar = await Isar.open(
          [ProductSchema, BatchSchema, SaleSchema, AppUserSchema],
          directory: dir.path,
          // inspector: true must be FALSE (or absent) in release builds —
          // it opens a web server that is blocked by Android release policy.
          inspector: kDebugMode,
        );
      } catch (e, st) {
        debugPrint('[ShopPOS] Isar.open() failed: $e\n$st');
        rethrow; // Re-throw so the Zone catches it — we can't run without DB
      }

      // Seed default users on fresh launch
      try {
        await _seedDefaultUsers(isar);
      } catch (e, st) {
        debugPrint('[ShopPOS] _seedDefaultUsers() failed: $e\n$st');
        // Non-fatal — continue even if seeding fails (users may already exist)
      }

      runApp(
        ProviderScope(
          overrides: [
            isarProvider.overrideWithValue(isar),
            notificationServiceProvider.overrideWithValue(notificationService),
          ],
          child: const ShopPOSApp(),
        ),
      );
    },
    (error, stack) {
      // Any uncaught async error lands here — prints to logcat/console
      debugPrint('[ShopPOS] UNCAUGHT ERROR: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

Future<void> _seedDefaultUsers(Isar isar) async {
  // 1. Guarantee Owner account
  var owner = await isar.appUsers.filter().roleEqualTo('owner').findFirst();
  if (owner == null) {
    final newOwner = AppUser()
      ..name = 'Shop Owner'
      ..role = 'owner'
      ..isActive = true
      ..pinHash = HashHelpers.hashPin('1234');
    await isar.writeTxn(() async {
      await isar.appUsers.put(newOwner);
    });
  } else {
    final o = owner;
    if (!o.isActive || o.pinHash.isEmpty) {
      o.isActive = true;
      if (o.pinHash.isEmpty) {
        o.pinHash = HashHelpers.hashPin('1234');
      }
      await isar.writeTxn(() async {
        await isar.appUsers.put(o);
      });
    }
  }

  // 2. Guarantee Cashier account
  var cashier = await isar.appUsers.filter().roleEqualTo('cashier').findFirst();
  if (cashier == null) {
    final newCashier = AppUser()
      ..name = 'Cashier'
      ..role = 'cashier'
      ..isActive = true
      ..pinHash = HashHelpers.hashPin('0000');
    await isar.writeTxn(() async {
      await isar.appUsers.put(newCashier);
    });
  } else {
    final c = cashier;
    if (!c.isActive) {
      c.isActive = true;
      await isar.writeTxn(() async {
        await isar.appUsers.put(c);
      });
    }
  }
}

class ShopPOSApp extends StatelessWidget {
  const ShopPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopPOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const LoginScreen(),
    );
  }
}