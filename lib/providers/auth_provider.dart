/// ============================================
/// Auth Provider — Riverpod
/// ============================================
/// Manages authentication state: login, logout,
/// current user session, and PIN verification.
/// ============================================
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/app_user.dart';
import 'database_provider.dart';

/// Holds the currently logged-in user (null = not logged in).
final currentUserProvider = StateProvider<AppUser?>((ref) => null);

/// Provider for authentication operations.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(isarProvider), ref);
});

/// Authentication service handling PIN-based login.
class AuthService {
  final Isar _isar;
  final Ref _ref;

  AuthService(this._isar, this._ref);

  /// Attempt to log in with a 4-digit PIN.
  /// Returns the user if successful, null otherwise.
  Future<AppUser?> login(String pin) async {
    final hashedPin = AppUser.hashPin(pin);

    // Query Isar for a user with this PIN hash
    final user = await _isar.appUsers
        .filter()
        .pinHashEqualTo(hashedPin)
        .isActiveEqualTo(true)
        .findFirst();

    if (user != null) {
      // Set the current user in state
      _ref.read(currentUserProvider.notifier).state = user;
    }

    return user;
  }

  /// Log out the current user.
  void logout() {
    _ref.read(currentUserProvider.notifier).state = null;
  }

  /// Get all active users (for admin purposes).
  Future<List<AppUser>> getAllUsers() async {
    return _isar.appUsers
        .filter()
        .isActiveEqualTo(true)
        .findAll();
  }

  /// Verify if a PIN belongs to an active owner.
  Future<bool> verifyOwnerPin(String pin) async {
    final hashedPin = AppUser.hashPin(pin);
    final count = await _isar.appUsers
        .filter()
        .pinHashEqualTo(hashedPin)
        .roleEqualTo('owner')
        .isActiveEqualTo(true)
        .count();
    return count > 0;
  }

  /// Check if a PIN is already in use.
  Future<bool> isPinTaken(String pin) async {
    final hashedPin = AppUser.hashPin(pin);
    final count = await _isar.appUsers
        .filter()
        .pinHashEqualTo(hashedPin)
        .count();
    return count > 0;
  }

  /// Create a new user (owner only).
  Future<AppUser> createUser({
    required String name,
    required String pin,
    required String role,
  }) async {
    final user = AppUser()
      ..name = name
      ..role = role
      ..pinHash = AppUser.hashPin(pin);

    await _isar.writeTxn(() async {
      await _isar.appUsers.put(user);
    });

    return user;
  }
}
