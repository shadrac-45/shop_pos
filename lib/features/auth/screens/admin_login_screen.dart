// ignore_for_file: unused_import

/// ============================================
/// Admin Login Screen — ShopPOS
/// ============================================
/// Email + Password login for the Owner/Admin role.
/// Shown on first launch before the setup wizard,
/// and on subsequent launches when Admin is selected.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
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
  bool _loading = false;
  bool _obscurePass = true;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMsg = 'Enter both email and password.');
      return;
    }
    if (pass.length < 4) {
      setState(() => _errorMsg = 'Password must be at least 4 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      if (widget.setupAlreadyDone) {
        // ── Returning admin: verify email+password against DB ──────────
        final isar = ref.read(isarProvider);
        final user = await AdminAuthService.login(isar, email, pass);
        if (!mounted) return;
        if (user == null) {
          setState(() {
            _errorMsg = 'Invalid email or password.';
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
        // The owner account is created when the wizard completes (saveAndComplete).
        // No DB query needed here.
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
          _errorMsg = 'An error occurred. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14151D), // sidebar dark
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(32),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Logo ──────────────────────────────
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: AppSpacing.borderMd,
                      ),
                      child: const Icon(Icons.shopping_cart_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Title ─────────────────────────────
                    Text('Sign in to admin console',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      widget.setupAlreadyDone
                          ? 'Welcome back. Enter your credentials.'
                          : "Manage your store's setup and daily operations.",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ── Email Field ───────────────────────
                    Text('Email',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'admin@yourstore.com',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Password Field ────────────────────
                    Text('Password',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                    ),

                    // ── Error ─────────────────────────────
                    if (_errorMsg != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_errorMsg!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 13)),
                    ],
                    const SizedBox(height: AppSpacing.lg),

                    // ── Sign In Button ────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _signIn,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Forgot password ───────────────────
                    Center(
                      child: TextButton(
                        onPressed: () => _showForgotHint(context),
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

  void _showForgotHint(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Password Recovery'),
        content: const Text(
          'To reset the admin password, uninstall and reinstall the app, '
          'then complete the setup wizard again with a new password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
