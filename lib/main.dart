/// =======================================================
/// ShopPOS — Offline-First Point of Sale System
/// =======================================================
/// A mobile-first POS system for small shops in emerging
/// markets. Built with Flutter, Isar, and Riverpod.
///
/// Architecture: Clean Architecture + MVVM
/// Database: Isar (offline-first)
/// State: Riverpod 2.x
/// =======================================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'core/theme/app_theme.dart';
import 'models/product.dart';
import 'models/batch.dart';
import 'models/sale.dart';
import 'models/app_user.dart';
import 'providers/database_provider.dart';
import 'features/auth/screens/login_screen.dart';

void main() async {
  // Ensure Flutter bindings are initialized before async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait only — better for POS usage
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for immersive dark experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Isar database
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ProductSchema, BatchSchema, SaleSchema, AppUserSchema],
    directory: dir.path,
    name: 'shop_pos_db',
    inspector: false, // Disable inspector in production for performance
  );

  // Seed default owner account if no users exist
  await _seedDefaultUsers(isar);

  runApp(
    ProviderScope(
      overrides: [
        // Override the database provider with our initialized instance
        isarProvider.overrideWithValue(isar),
      ],
      child: const ShopPOSApp(),
    ),
  );
}

/// Seeds a default owner account on first launch.
/// Default PIN: 1234 (owner), 0000 (cashier)
Future<void> _seedDefaultUsers(Isar isar) async {
  final userCount = await isar.appUsers.count();
  if (userCount == 0) {
    await isar.writeTxn(() async {
      // Create default owner
      final owner = AppUser()
        ..name = 'Shop Owner'
        ..role = 'owner'
        ..pinHash = AppUser.hashPin('1234');
      await isar.appUsers.put(owner);

      // Create default cashier
      final cashier = AppUser()
        ..name = 'Cashier 1'
        ..role = 'cashier'
        ..pinHash = AppUser.hashPin('0000');
      await isar.appUsers.put(cashier);
    });

    // Seed sample products with batches for demo
    await _seedSampleProducts(isar);
  }
}

/// Seeds sample products and batches for demonstration.
Future<void> _seedSampleProducts(Isar isar) async {
  await isar.writeTxn(() async {
    // Define sample products with their quick-button colors
    final products = <Map<String, dynamic>>[
      {
        'name': 'Pure Water',
        'price': 1.00,
        'category': 'Beverages',
        'color': 0xFF2196F3, // Blue
        'batches': [
          {'qty': 500, 'daysUntilExpiry': 180},
          {'qty': 200, 'daysUntilExpiry': 90},
        ],
      },
      {
        'name': 'Indomie',
        'price': 5.50,
        'category': 'Food',
        'color': 0xFFFF9800, // Orange
        'batches': [
          {'qty': 100, 'daysUntilExpiry': 365},
        ],
      },
      {
        'name': 'Milo Sachet',
        'price': 3.00,
        'category': 'Beverages',
        'color': 0xFF4CAF50, // Green
        'batches': [
          {'qty': 150, 'daysUntilExpiry': 270},
          {'qty': 80, 'daysUntilExpiry': 30},
        ],
      },
      {
        'name': 'Bread',
        'price': 12.00,
        'category': 'Bakery',
        'color': 0xFFFF5722, // Deep Orange
        'batches': [
          {'qty': 20, 'daysUntilExpiry': 3},
        ],
      },
      {
        'name': 'Sugar (1kg)',
        'price': 18.00,
        'category': 'Grocery',
        'color': 0xFF9C27B0, // Purple
        'batches': [
          {'qty': 50, 'daysUntilExpiry': 730},
        ],
      },
      {
        'name': 'Egg (crate)',
        'price': 45.00,
        'category': 'Dairy',
        'color': 0xFFE91E63, // Pink
        'batches': [
          {'qty': 10, 'daysUntilExpiry': 14},
        ],
      },
      {
        'name': 'Fanta 500ml',
        'price': 8.00,
        'category': 'Beverages',
        'color': 0xFFFFC107, // Amber
        'batches': [
          {'qty': 200, 'daysUntilExpiry': 120},
        ],
      },
      {
        'name': 'Biscuit Pack',
        'price': 2.50,
        'category': 'Snacks',
        'color': 0xFF00BCD4, // Cyan
        'batches': [
          {'qty': 300, 'daysUntilExpiry': 200},
          {'qty': 100, 'daysUntilExpiry': 15},
        ],
      },
    ];

    for (final p in products) {
      final product = Product()
        ..name = p['name'] as String
        ..price = p['price'] as double
        ..category = p['category'] as String
        ..quickButtonColor = p['color'] as int;
      final productId = await isar.products.put(product);

      // Create batches for each product
      for (final b in p['batches'] as List<Map<String, dynamic>>) {
        final batch = Batch()
          ..productId = productId
          ..quantity = b['qty'] as int
          ..expiryDate = DateTime.now().add(
            Duration(days: b['daysUntilExpiry'] as int),
          )
          ..restockDate = DateTime.now()
          ..supplierNote = 'Initial stock';
        await isar.batchs.put(batch);
      }
    }
  });
}

/// Root application widget.
class ShopPOSApp extends StatelessWidget {
  const ShopPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopPOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginScreen(),
    );
  }
}
