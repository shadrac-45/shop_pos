/// ============================================
/// Login Screen — ShopPOS
/// ============================================
/// Single, unified PIN-based authentication.
///  • Standard 4-digit numeric PIN keypad
///  • Auto-detects user identity and role (Owner vs Cashier)
///  • Security: Blocks deactivated accounts with clear feedback
///  • Security: 3 failed attempts trigger a 30-second lockout
/// ============================================
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/auth_provider.dart';
import '../../main/screens/main_shell_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ── PIN Entry State ─────────────────────────────────────
  final List<String> _pin = List.filled(4, '');
  int _currentIndex = 0;
  bool _isAuthenticating = false;

  // ── Lockout Security State ──────────────────────────────
  int _failedAttempts = 0;
  bool _isLockedOut = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _isLockedOut = true;
      _lockoutSeconds = 30;
      _pin.fillRange(0, 4, '');
      _currentIndex = 0;
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_lockoutSeconds > 1) {
          _lockoutSeconds--;
        } else {
          _isLockedOut = false;
          _lockoutSeconds = 0;
          _failedAttempts = 0;
          timer.cancel();
        }
      });
    });
  }

  void _onNumberPress(String number) {
    if (_isLockedOut || _isAuthenticating) return;

    if (_currentIndex < 4) {
      HapticFeedback.lightImpact();
      setState(() {
        _pin[_currentIndex] = number;
        _currentIndex++;
      });
      if (_currentIndex == 4) {
        _attemptLogin();
      }
    }
  }

  void _onBackspace() {
    if (_isLockedOut || _isAuthenticating) return;

    if (_currentIndex > 0) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentIndex--;
        _pin[_currentIndex] = '';
      });
    }
  }

  Future<void> _attemptLogin() async {
    setState(() => _isAuthenticating = true);
    final enteredPin = _pin.join();

    // Timing instrumentation — visible in debug console.
    final sw = Stopwatch()..start();
    final result = await ref.read(currentUserProvider.notifier).login(enteredPin);
    sw.stop();
    debugPrint('[ShopPOS Login] PIN verify + DB lookup: ${sw.elapsedMilliseconds}ms');

    final user = ref.read(currentUserProvider);

    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    switch (result) {
      case LoginResult.success:
        if (user != null) {
          HapticFeedback.mediumImpact();
          setState(() => _failedAttempts = 0);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShellScreen()),
          );
        }

      case LoginResult.deactivated:
        HapticFeedback.vibrate();
        setState(() {
          _pin.fillRange(0, 4, '');
          _currentIndex = 0;
        });
        context.showErrorSnackbar(
          'This account has been deactivated — please contact the shop owner.',
        );

      case LoginResult.invalidPin:
        HapticFeedback.vibrate();
        _failedAttempts++;
        setState(() {
          _pin.fillRange(0, 4, '');
          _currentIndex = 0;
        });

        if (_failedAttempts >= 3) {
          _startLockoutTimer();
          context.showErrorSnackbar(
            'Too many failed attempts. Keypad locked for 30s.',
          );
        } else {
          final remaining = 3 - _failedAttempts;
          context.showErrorSnackbar(
            'Incorrect PIN ($remaining attempt${remaining == 1 ? '' : 's'} remaining before lockout).',
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    if (user != null && user.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShellScreen()),
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
              minHeight: screenHeight -
                  mq.padding.top -
                  mq.padding.bottom -
                  AppSpacing.md * 2,
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
                  'Enter your assigned 4-digit PIN to begin',
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
                  children: List.generate(4, (index) {
                    final filled = _pin[index].isNotEmpty;
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
                        child: _pin[index].isEmpty
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
                      if (index == 9) return const SizedBox.shrink();
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
