// ============================================
// Till test harness — ShopPOS
// ============================================
// Fakes and a pumpable app for widget tests of
// the till, checkout and sign-in screens, with
// no database: products come from an in-memory
// stream and the cart adds items in memory.
// ============================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/theme/app_theme.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/providers/product_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/sales/screens/cashier_sales_screen.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';
import 'package:shop_pos/features/shifts/providers/shift_provider.dart';

class FakeSettings extends StoreSettingsNotifier {
  @override
  StoreSettings build() => StoreSettings()..storeName = 'Kofi Shop';
}

class FakeAuth extends AuthNotifier {
  FakeAuth(super.ref, AppUser? user) {
    // ignore: invalid_use_of_protected_member
    state = user;
  }

  int logouts = 0;

  @override
  void logout({bool timedOut = false}) {
    logouts++;
    // ignore: invalid_use_of_protected_member
    state = null;
  }
}

/// Cart whose [addItem] works in memory (the real one re-reads the product
/// and its stock from the database). Line maths and limits are the real
/// [CartNotifier]'s.
class FakeCart extends CartNotifier {
  FakeCart(super.ref, List<CartItem> items) {
    // ignore: invalid_use_of_protected_member
    state = items;
  }

  final List<String> added = [];

  @override
  Future<AddItemResult> addItem(Product product, int quantity) async {
    added.add(product.name);
    final i = state.indexWhere((e) => e.product.id == product.id);
    if (i >= 0) {
      final updated = [...state];
      updated[i] = updated[i].copyWith(quantity: updated[i].quantity + quantity);
      // ignore: invalid_use_of_protected_member
      state = updated;
    } else {
      // ignore: invalid_use_of_protected_member
      state = [...state, CartItem(product: product, quantity: quantity, available: 99)];
    }
    return AddItemResult.success;
  }
}

Product testProduct(int id, String name, double price, String category, {String? barcode}) =>
    Product()
      ..id = id
      ..name = name
      ..price = price
      ..category = category
      ..barcode = barcode;

final testProducts = [
  testProduct(1, 'Coca-Cola 500ml', 8.5, 'Drinks', barcode: '5449000000996'),
  testProduct(2, 'Fan Ice Vanilla', 3, 'Frozen'),
  testProduct(3, 'Indomie Chicken', 4.5, 'Food'),
  testProduct(4, 'Milo Tin 400g', 52, 'Drinks'),
  testProduct(5, 'Peak Milk Powder', 38, 'Dairy'),
  testProduct(6, 'Sunlight Soap', 6, 'Household'),
  testProduct(7, 'Gino Tomato Paste', 2.5, 'Food'),
  testProduct(8, 'Voltic Water 1.5L', 5, 'Drinks'),
  testProduct(9, 'Ideal Milk', 9, 'Dairy'),
  testProduct(10, 'Royal Aroma Rice 5kg', 145, 'Food'),
];

/// The three-line cart used by layout tests (9 units, GH₵ 97.00).
List<CartItem> sampleCart() => [
      CartItem(product: testProducts[0], quantity: 2, available: 48),
      CartItem(product: testProducts[3], quantity: 1, available: 12, discount: 2),
      CartItem(product: testProducts[7], quantity: 6, available: 60),
    ];

AppUser testOwner() => AppUser()
  ..name = 'Ama Mensah'
  ..role = 'owner'
  ..pinHash = '';

/// Handles to the fakes a test may want to inspect.
class TillHandles {
  FakeCart? cart;
  FakeAuth? auth;
}

Widget tillApp({
  List<CartItem> cart = const [],
  Widget? home,
  TillHandles? handles,
  AppUser? user,
}) {
  return ProviderScope(
    overrides: [
      storeSettingsProvider.overrideWith(FakeSettings.new),
      productServiceProvider.overrideWith((ref) => Stream.value(testProducts)),
      currentShiftProvider.overrideWith((ref) => Stream.value(null)),
      currentUserProvider.overrideWith((ref) {
        final a = FakeAuth(ref, user ?? testOwner());
        handles?.auth = a;
        return a;
      }),
      cartProvider.overrideWith((ref) {
        final c = FakeCart(ref, [...cart]);
        handles?.cart = c;
        return c;
      }),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: home ??
          const Scaffold(
            body: AmbientBackdrop(child: SafeArea(child: CashierSalesScreen())),
          ),
    ),
  );
}

Future<void> setTestSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Loads Inter and Material Icons so golden previews show real type.
Future<void> loadPreviewFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
  final iconsFile = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (iconsFile.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconsFile.readAsBytesSync())));
    await icons.load();
  }
}
