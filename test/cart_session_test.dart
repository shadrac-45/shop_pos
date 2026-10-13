// ============================================
// Cart Session Isolation Test — ShopPOS
// ============================================
// A cart belongs to whoever is signed in. Drives
// the real PIN login, the real cart (stock checks
// against a real Isar database) and the real
// logout:
//   User A → add products → logout → User B login
//   → cart must be empty.
// Plus: same user back in, sale discount reset,
// a late add finishing after sign-out, and a
// record refresh mid-sale keeping the cart.
// ============================================

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/database/schemas.dart';
import 'package:shop_pos/core/utils/hash_helpers.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';

late Isar isar;
late Directory dir;
late ProviderContainer container;
late Product milo;
late Product water;

const pinA = '7777'; // Kofi, cashier
const pinB = '5555'; // Mia, manager

Future<void> _user(String name, String role, String pin) async {
  final u = AppUser()
    ..name = name
    ..role = role
    ..pinHash = HashHelpers.hashPin(pin);
  await isar.writeTxn(() => isar.appUsers.put(u));
}

Future<Product> _product(String name, double price, int stock) async {
  final p = Product()
    ..name = name
    ..price = price
    ..category = 'Test';
  await isar.writeTxn(() async {
    await isar.products.put(p);
    final b = Batch()
      ..productId = p.id
      ..quantity = stock
      ..expiryDate = DateTime.now().add(const Duration(days: 200))
      ..restockDate = DateTime.now();
    await isar.batchs.put(b);
    b.product.value = p;
    await b.product.save();
  });
  return p;
}

AuthNotifier get auth => container.read(currentUserProvider.notifier);
List<CartItem> get cart => container.read(cartProvider);

Future<void> signIn(String pin) async {
  expect(await auth.login(pin), LoginResult.success);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: 'isar.dll'});
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('pos_cart_session_test_');
    isar = await Isar.open(allSchemas, directory: dir.path, name: 'cart_session');
    await _user('Kofi', AppConstants.roleCashier, pinA);
    await _user('Mia', AppConstants.roleManager, pinB);
    milo = await _product('Milo Tin 400g', 52, 12);
    water = await _product('Voltic Water 1.5L', 5, 60);
    container = ProviderContainer(overrides: [isarProvider.overrideWithValue(isar)]);
    // Keep the cart alive between reads, as the till screen does.
    container.listen(cartProvider, (_, __) {});
    container.listen(cartSaleDiscountProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    await isar.close(deleteFromDisk: true);
    await dir.delete(recursive: true);
  });

  test('User A adds products, logs out; User B logs in to an empty cart', () async {
    await signIn(pinA);
    expect(container.read(currentUserProvider)!.name, 'Kofi');
    expect(await container.read(cartProvider.notifier).addItem(milo, 2), AddItemResult.success);
    expect(await container.read(cartProvider.notifier).addItem(water, 3), AddItemResult.success);
    container.read(cartSaleDiscountProvider.notifier).state = 4;
    expect(cart.map((i) => i.quantity), [2, 3]);

    auth.logout();
    expect(cart, isEmpty, reason: 'cleared on logout');
    expect(container.read(cartSaleDiscountProvider), 0);

    await signIn(pinB);
    expect(container.read(currentUserProvider)!.name, 'Mia');
    expect(cart, isEmpty, reason: "Mia must not see Kofi's cart");
    expect(container.read(cartSaleDiscountProvider), 0);
    expect(container.read(cartItemCountProvider), 0);

    // And B's own cart works normally.
    expect(await container.read(cartProvider.notifier).addItem(water, 1), AddItemResult.success);
    expect(cart.single.product.name, 'Voltic Water 1.5L');
  });

  test('the same user signing back in starts with an empty cart', () async {
    await signIn(pinA);
    await container.read(cartProvider.notifier).addItem(milo, 1);
    auth.logout();
    await signIn(pinA);
    expect(cart, isEmpty);
  });

  test('an inactivity time-out clears the cart too', () async {
    await signIn(pinA);
    await container.read(cartProvider.notifier).addItem(milo, 1);
    auth.logout(timedOut: true);
    await signIn(pinB);
    expect(cart, isEmpty);
  });

  test('an add still checking stock when A signs out never reaches B', () async {
    await signIn(pinA);
    final oldCart = container.read(cartProvider.notifier);

    // Tap a product, then sign out and let B in before the stock check
    // (a database read) comes back.
    final lateAdd = oldCart.addItem(milo, 2);
    auth.logout();
    await signIn(pinB);

    expect(await lateAdd, AddItemResult.cancelled);
    expect(cart, isEmpty, reason: "the late result must not land in Mia's cart");
    expect(identical(container.read(cartProvider.notifier), oldCart), isFalse);
  });

  test("a refresh of the signed-in user's record keeps their cart", () async {
    await signIn(pinA);
    await container.read(cartProvider.notifier).addItem(milo, 2);

    // The same person's record re-read from the database: a new object
    // with the same id (as when their account is refreshed mid-sale).
    final me = container.read(currentUserProvider)!;
    final fresh = (await isar.appUsers.get(me.id))!;
    expect(identical(fresh, me), isFalse);
    auth.setUser(fresh);

    expect(identical(container.read(currentUserProvider), fresh), isTrue);
    expect(cart.single.quantity, 2, reason: 'mid-sale cart survives');
  });
}
