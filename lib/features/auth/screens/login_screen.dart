/// ============================================
/// Login Screen — ShopPOS
/// ============================================
/// PIN-based login with 4-digit keypad.
/// Routes to Cashier Sales or Owner Products
/// based on the user's role.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/auth_provider.dart';
import '../main/screens/main_shell_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _isLoading = false;
  bool _showError = false;
  String _errorMessage = '';

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reverse();
        }
      });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  /// Handle a keypad digit press.
  void _onDigitPressed(String digit) {
    if (_pin.length >= AppConstants.pinLength) return;

    HapticFeedback.lightImpact();

    setState(() {
      _pin += digit;
      _showError = false;
    });

    // Auto-submit when 4 digits entered
    if (_pin.length == AppConstants.pinLength) {
      _attemptLogin();
    }
  }

  /// Handle backspace press.
  void _onBackspace() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _showError = false;
    });
  }

  /// Attempt to log in with the entered PIN.
  Future<void> _attemptLogin() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // Small delay for UX feedback
    await Future.delayed(const Duration(milliseconds: 300));

    final authService = ref.read(authServiceProvider);
    final user = await authService.login(_pin);

    if (!mounted) return;

    if (user != null) {
      // Successful login — navigate based on role
      HapticFeedback.heavyImpact();

      // Navigate to main shell screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MainShellScreen(),
        ),
      );
    } else {
      // Failed login — show error
      HapticFeedback.vibrate();
      _shakeController.forward();

      setState(() {
        _showError = true;
        _errorMessage = 'Invalid PIN. Please try again.';
        _pin = '';
        _isLoading = false;
      });
    }
  }

  /// Manual login button press.
  void _onLoginPressed() {
    if (_pin.length != AppConstants.pinLength) {
      setState(() {
        _showError = true;
        _errorMessage = 'Please enter a 4-digit PIN';
      });
      _shakeController.forward();
      return;
    }
    _attemptLogin();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: isSmallScreen ? 24 : 48),

                  // ── Logo & Header ──────────────────────
                  _buildHeader(isSmallScreen),

                  SizedBox(height: isSmallScreen ? 24 : 40),

                  // ── PIN Display Boxes ──────────────────
                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          _shakeAnimation.value *
                              (_shakeController.status ==
                                      AnimationStatus.forward
                                  ? 1
                                  : -1),
                          0,
                        ),
                        child: child,
                      );
                    },
                    child: _buildPinBoxes(),
                  ),

                  const SizedBox(height: 8),

                  // ── Error Message ──────────────────────
                  _buildErrorMessage(),

                  SizedBox(height: isSmallScreen ? 16 : 24),

                  // ── Numeric Keypad ─────────────────────
                  _buildKeypad(),

                  SizedBox(height: isSmallScreen ? 16 : 24),

                  // ── Login Button ───────────────────────
                  _buildLoginButton(),

                  SizedBox(height: isSmallScreen ? 16 : 32),

                  // ── Default PINs Hint (remove in prod) ─
                  _buildDefaultPinsHint(),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// App logo and welcome header.
  Widget _buildHeader(bool isSmallScreen) {
    return Column(
      children: [
        // App icon container
        Container(
          width: isSmallScreen ? 64 : 80,
          height: isSmallScreen ? 64 : 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.point_of_sale_rounded,
            size: isSmallScreen ? 32 : 40,
            color: AppColors.textOnPrimary,
          ),
        ),

        SizedBox(height: isSmallScreen ? 12 : 20),

        // App name
        Text(
          AppConstants.appName,
          style: TextStyle(
            fontSize: isSmallScreen ? 28 : 32,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 4),

        // Welcome text
        Text(
          'Welcome Back!',
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          'Enter your PIN to continue',
          style: TextStyle(
            fontSize: isSmallScreen ? 13 : 14,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  /// Four PIN indicator boxes.
  Widget _buildPinBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(AppConstants.pinLength, (index) {
        final isFilled = index < _pin.length;
        final isActive = index == _pin.length;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 56,
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isFilled
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surfaceBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _showError
                  ? AppColors.danger
                  : isFilled
                      ? AppColors.primary
                      : isActive
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.border,
              width: isFilled || isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: isFilled
                ? Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
        );
      }),
    );
  }

  /// Error message display.
  Widget _buildErrorMessage() {
    return AnimatedOpacity(
      opacity: _showError ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        height: 24,
        child: Text(
          _errorMessage,
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Numeric keypad grid.
  Widget _buildKeypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'backspace'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 80, height: 64);
              }
              return _buildKeypadButton(key);
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  /// Individual keypad button.
  Widget _buildKeypadButton(String key) {
    final isBackspace = key == 'backspace';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isBackspace ? _onBackspace : () => _onDigitPressed(key),
          onLongPress: isBackspace
              ? () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _pin = '';
                    _showError = false;
                  });
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primary.withValues(alpha: 0.2),
          highlightColor: AppColors.primary.withValues(alpha: 0.1),
          child: Container(
            width: 80,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border,
                width: 1,
              ),
            ),
            child: Center(
              child: isBackspace
                  ? const Icon(
                      Icons.backspace_outlined,
                      color: AppColors.textSecondary,
                      size: 24,
                    )
                  : Text(
                      key,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Big green LOGIN button.
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _onLoginPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.textOnPrimary,
                ),
              )
            : const Text(
                'LOGIN',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                ),
              ),
      ),
    );
  }

  /// Hint showing default PINs (for development only).
  Widget _buildDefaultPinsHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: const Column(
        children: [
          Text(
            'Default PINs (for testing)',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Owner: 1234',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 24),
              Text(
                'Cashier: 0000',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
