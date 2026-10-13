/// ============================================
/// Sign Out Button — ShopPOS
/// ============================================
/// One compact sign-out control for the whole
/// app: a small outlined pill (icon + "Sign out")
/// with a red icon and a red-tint hover/press, so
/// it is easy to find but never dominates.
/// Asks first if items are still in the cart.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/sales/providers/cart_provider.dart';
import 'package:shop_pos/features/shared/widgets/ui_helpers.dart';

/// Signs out (the app returns to the sign-in screen once the user is
/// cleared). If the cart holds items, confirms first: they would be lost.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  // Read everything needed before awaiting: the widget that owns [ref]
  // may be disposed while the dialog is open (e.g. a session timeout).
  final auth = ref.read(currentUserProvider.notifier);
  final items = ref.read(cartItemCountProvider);
  if (items > 0) {
    final ok = await confirmDialog(
      context,
      title: 'Sign out now?',
      message: 'There ${items == 1 ? 'is 1 item' : 'are $items items'} in the cart. '
          'Signing out will clear the current sale.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok) return;
  }
  auth.logout();
}

class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => confirmAndSignOut(context, ref),
      icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
      label: const Text('Sign out'),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
        foregroundColor: const WidgetStatePropertyAll(AppColors.textPrimary),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)
                ? AppColors.dangerTint
                : AppColors.cardBg),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)
                  ? AppColors.dangerBorder
                  : AppColors.border,
            )),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
