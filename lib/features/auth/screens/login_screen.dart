/// ============================================
/// Login Screen — ShopPOS
/// ============================================
/// Single, unified PIN-based authentication.
///  • 4–6 digit numeric PIN keypad (Enter submits; 6 digits auto-submit)
///  • Auto-detects user identity and role (Owner vs Cashier)
///  • Security: Blocks deactivated accounts with clear feedback
///  • Security: 5 failed attempts trigger a 30-second lockout
/// ============================================
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_assets.dart';
import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/responsive/app_breakpoints.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/main/screens/main_shell_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ── PIN Entry State ─────────────────────────────────────
  String _pin = '';
  bool _isAuthenticating = false;

  // The lockout itself lives in AuthNotifier (and survives restarts);
  // this only mirrors it for the countdown banner.
  bool _isLockedOut = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    // Let AuthNotifier finish restoring a saved lockout, then show it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLockout());
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  /// Shows the provider's lockout, if any, and counts it down.
  void _syncLockout() {
    if (!mounted) return;
    final auth = ref.read(currentUserProvider.notifier);
    final locked = auth.isLockedOut;
    setState(() {
      _isLockedOut = locked;
      _lockoutSeconds = auth.lockoutSecondsRemaining;
      if (locked) _pin = '';
    });
    _lockoutTimer?.cancel();
    if (locked) {
      _lockoutTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _syncLockout());
    }
  }

  void _onNumberPress(String number) {
    if (_isLockedOut || _isAuthenticating) return;

    if (_pin.length < AppConstants.maxPinLength) {
      HapticFeedback.lightImpact();
      setState(() => _pin += number);
      // A full-length PIN can't grow any further, so submit it straight away.
      if (_pin.length == AppConstants.maxPinLength) {
        _attemptLogin();
      }
    }
  }

  void _onSubmit() {
    if (_isLockedOut || _isAuthenticating) return;
    if (_pin.length < AppConstants.minPinLength) {
      HapticFeedback.vibrate();
      context.showErrorSnackbar(
        'PIN must be at least ${AppConstants.minPinLength} digits.',
      );
      return;
    }
    _attemptLogin();
  }

  void _onBackspace() {
    if (_isLockedOut || _isAuthenticating) return;

    if (_pin.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _attemptLogin() async {
    setState(() => _isAuthenticating = true);
    final enteredPin = _pin;
    final auth = ref.read(currentUserProvider.notifier);

    final result = await auth.login(enteredPin);

    if (!mounted) return;
    setState(() {
      _isAuthenticating = false;
      _pin = '';
    });

    switch (result) {
      case LoginResult.success:
        HapticFeedback.mediumImpact();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShellScreen()),
          (_) => false,
        );

      case LoginResult.deactivated:
        HapticFeedback.vibrate();
        context.showErrorSnackbar(
          'This account has been deactivated — please contact the shop owner.',
        );

      case LoginResult.defaultPin:
        HapticFeedback.vibrate();
        context.showErrorSnackbar(
          'This is a default PIN and can no longer be used. Owner: sign in '
          'with your admin email and set a new PIN. Staff: ask the owner '
          'to reset your PIN.',
        );

      case LoginResult.lockedOut:
        HapticFeedback.vibrate();
        _syncLockout();
        context.showErrorSnackbar(
          'Too many failed attempts. Keypad locked for ${auth.lockoutSecondsRemaining}s.',
        );

      case LoginResult.invalidPin:
        HapticFeedback.vibrate();
        final remaining = auth.attemptsBeforeLockout;
        context.showErrorSnackbar(
          'Incorrect PIN ($remaining attempt${remaining == 1 ? '' : 's'} remaining before lockout).',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    if (user != null && user.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShellScreen()),
            (_) => false,
          );
        }
      });
    }

    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    final screenWidth = mq.size.width;
    final isLandscape = AppBreakpoints.isLandscape(context);

    final logoSize = isLandscape
        ? (screenHeight * 0.22).clamp(50.0, 90.0)
        : AppBreakpoints.logoHeight(screenHeight);

    final dotW = AppBreakpoints.pinDotWidth(screenWidth * 0.88);
    final dotH = AppBreakpoints.pinDotHeight(screenWidth * 0.88);
    final keypadMaxW = (screenWidth * 0.80).clamp(0.0, 340.0);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.06,
            vertical: AppSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (screenHeight -
                      mq.padding.top -
                      mq.padding.bottom -
                      AppSpacing.md * 2)
                  .clamp(0.0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Brand Logo ───────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppSpacing.borderLg,
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Image.asset(
                    AppAssets.shopposLogo,
                    height: logoSize,
                    width: logoSize,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  'Welcome to ShopPOS',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter your 4–6 digit PIN, then tap ✓',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Lockout Warning Banner ───────────────────
                if (_isLockedOut)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: AppSpacing.borderMd,
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_rounded,
                            color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Keypad locked. Retry in ${_lockoutSeconds}s',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── PIN Indicator Dots ────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  // Always show at least the minimum number of boxes; grow
                  // up to the maximum as longer PINs are typed.
                  children: List.generate(
                      _pin.length.clamp(AppConstants.minPinLength,
                          AppConstants.maxPinLength), (index) {
                    final filled = index < _pin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: dotW,
                      height: dotH,
                      decoration: BoxDecoration(
                        color: filled
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.cardBg,
                        border: Border.all(
                          color: _isLockedOut
                              ? AppColors.danger
                              : (filled ? AppColors.primary : AppColors.border),
                          width: filled ? 2.0 : 1.0,
                        ),
                        borderRadius: AppSpacing.borderMd,
                      ),
                      child: Center(
                        child: !filled
                            ? Text(
                                '•',
                                style: TextStyle(
                                  fontSize: 24,
                                  color: _isLockedOut
                                      ? AppColors.danger
                                      : AppColors.textMuted,
                                ),
                              )
                            : Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _isLockedOut
                                      ? AppColors.danger
                                      : AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Numeric Keypad ────────────────────────────
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: keypadMaxW),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.25,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      if (index == 9) {
                        return ElevatedButton(
                          onPressed: _isLockedOut ? null : _onSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.borderLg),
                            elevation: 0,
                          ),
                          child: const Icon(Icons.check_rounded, size: 26),
                        );
                      }
                      if (index == 11) {
                        return OutlinedButton(
                          onPressed: _isLockedOut ? null : _onBackspace,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.borderLg),
                            backgroundColor: AppColors.cardBg,
                            foregroundColor: AppColors.textSecondary,
                          ),
                          child: const Icon(Icons.backspace_rounded, size: 22),
                        );
                      }
                      final number =
                          index == 10 ? '0' : (index + 1).toString();
                      return ElevatedButton(
                        onPressed: _isLockedOut ? null : () => _onNumberPress(number),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cardBg,
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: AppSpacing.borderLg),
                          elevation: 0,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            number,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _isLockedOut
                                  ? AppColors.textMuted
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),


              ],
            ),
          ),
        ),
      ),
    );
  }
}
