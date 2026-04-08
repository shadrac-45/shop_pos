import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/app_user.dart';
import 'database_provider.dart';

final currentUserProvider =
    StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<AppUser?> {
  final Ref ref;

  AuthNotifier(this.ref) : super(null);

  Future<void> login(String pin) async {
    final isar = ref.read(isarProvider);
    final user = await isar.appUsers.filter().pinHashEqualTo(pin).findFirst();

    if (user != null) {
      state = user;
    }
    // Removed dangerous default-owner creation.
    // Seed the default owner (PIN=1234) in main.dart instead.
  }

  void logout() => state = null;

  bool get isOwner => state?.role == "owner";
  bool get isLoggedIn => state != null;
}
