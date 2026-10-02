/// ============================================
/// Admin Login Screen — ShopPOS
/// ============================================
/// Email + Password login for the Owner/Admin role.
/// Shown on first launch before the setup wizard
/// (where it creates the admin credentials), and on
/// later launches when Admin is selected.
///
/// "Forgot password?" opens PasswordRecoveryScreen
/// whenever an admin account exists; the first-time
/// setup hint only appears when none does.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/screens/password_recovery_screen.dart';
import 'package:shop_pos/features/auth/services/admin_auth_service.dart';
import 'package:shop_pos/features/main/screens/main_shell_screen.dart';
import 'package:shop_pos/features/setup/screens/setup_wizard_screen.dart';
import 'package:shop_pos/features/setup/providers/setup_wizard_provider.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  /// If true, a completed setup already exists — go straight to dashboard on success.
  final bool setupAlreadyDone;

  const AdminLoginScreen({super.key, this.setupAlreadyDone = false});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;

  String? _emailError;
  String? _passError;
  String? _confirmError;

  /// Form-level message (wrong credentials, server error).
  String? _errorMsg;

  /// Shown after a successful password reset.
  String? _successMsg;

  bool get _creating => !widget.setupAlreadyDone;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailCtrl.text;
    final pass = _passCtrl.text;
    setState(() {
      _errorMsg = null;
      _emailError = AdminAuthService.emailProblem(email);
      if (_creating) {
        // A new password must be strong and typed twice.
        _passError = AdminAuthService.passwordProblem(pass, email: email);
        _confirmError =
            _passError == null && pass != _confirmCtrl.text ? 'The passwords don\'t match.' : null;
      } else {
        _passError = pass.isEmpty ? 'Enter your password.' : null;
        _confirmError = null;
      }
    });
    return _emailError == null && _passError == null && _confirmError == null;
  }

  Future<void> _signIn() async {
    if (!_validate()) return;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    setState(() {
      _loading = true;
      _successMsg = null;
    });

    try {
      if (widget.setupAlreadyDone) {
        // ── Returning admin: verify email+password against DB ──────────
        final user = await AdminAuthService.login(ref.read(isarProvider), email, pass);
        if (!mounted) return;
        if (user == null) {
          setState(() {
            // Deliberately vague: doesn't say which part was wrong.
            _errorMsg = 'Email or password is incorrect.';
            _loading = false;
          });
          return;
        }
        ref.read(currentUserProvider.notifier).setUser(user);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShellScreen()),
          (_) => false,
        );
      } else {
        // ── First-run setup: store credentials, navigate to wizard ─────
        // The owner account is created when the wizard completes.
        ref.read(setupWizardProvider.notifier).update((s) => s.copyWith(
              adminEmail: email,
              adminPassword: pass,
            ));
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Something went wrong. Please try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final hasAdmin = await AdminAuthService.adminAccountExists(ref.read(isarProvider));
    if (!mounted) return;

    if (!hasAdmin) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No admin account yet'),
          content: const Text(
            'This is first-time setup, so there is no password to recover. '
            'Choose the email and password you want to use for the admin account.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final reset = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PasswordRecoveryScreen(initialEmail: _emailCtrl.text.trim()),
    ));
    if (reset == true && mounted) {
      setState(() {
        _passCtrl.clear();
        _errorMsg = null;
        _passError = null;
        _successMsg = 'Password updated. Sign in with your new password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = AdminAuthService.passwordScore(_passCtrl.text);
    const scoreLabels = ['Too weak', 'Weak', 'Fair', 'Good', 'Strong'];
    const scoreColors = [
      AppColors.danger, AppColors.danger, AppColors.warning, AppColors.success, AppColors.success,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF14151D), // sidebar dark
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: AppSpacing.borderXl,
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: AppSpacing.borderMd,
                        ),
                        child: const Icon(Icons.shopping_cart_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      _creating ? 'Create your admin account' : 'Sign in to admin console',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _creating
                          ? 'You\'ll use this email and password to manage the store.'
                          : 'Welcome back. Enter your credentials.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    if (_successMsg != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: AppSpacing.borderMd,
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.success),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(_successMsg!,
                                  style: const TextStyle(color: AppColors.successDarkText)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),

                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      onChanged: (_) {
                        if (_emailError != null) setState(() => _emailError = null);
                      },
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: 'admin@yourstore.com',
                        errorText: _emailError,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      textInputAction: _creating ? TextInputAction.next : TextInputAction.done,
                      autofillHints: [
                        _creating ? AutofillHints.newPassword : AutofillHints.password
                      ],
                      onSubmitted: (_) => _creating ? null : _signIn(),
                      onChanged: (_) => setState(() => _passError = null),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _creating
                            ? 'At least ${AdminAuthService.minPasswordLength} characters, with a letter and a number.'
                            : null,
                        helperMaxLines: 2,
                        errorText: _passError,
                        errorMaxLines: 3,
                        suffixIcon: IconButton(
                          tooltip: _obscurePass ? 'Show password' : 'Hide password',
                          icon: Icon(_obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                    ),

                    if (_creating) ...[
                      if (_passCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (score + 1) / 5,
                                  minHeight: 5,
                                  backgroundColor: AppColors.surfaceBg,
                                  color: scoreColors[score],
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(scoreLabels[score],
                                style: TextStyle(color: scoreColors[score], fontSize: 12)),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: _obscurePass,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        onSubmitted: (_) => _signIn(),
                        onChanged: (_) {
                          if (_confirmError != null) setState(() => _confirmError = null);
                        },
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          errorText: _confirmError,
                        ),
                      ),
                    ],

                    if (_errorMsg != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(_errorMsg!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                    ],
                    const SizedBox(height: AppSpacing.xl),

                    ElevatedButton(
                      onPressed: _loading ? null : _signIn,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_creating ? 'Continue to store setup' : 'Sign in'),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        child: const Text('Forgot password?',
                            style: TextStyle(color: AppColors.primary)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
