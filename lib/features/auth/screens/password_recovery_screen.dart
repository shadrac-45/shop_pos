/// ============================================
/// Password Recovery Screen — ShopPOS
/// ============================================
/// Admin password reset, one step per screen:
///   1. admin email
///   2. owner PIN (the PIN set during setup)
///   3. new password, entered twice
/// then back to sign-in with a success message.
///
/// Five wrong PINs lock recovery for 15 minutes.
/// Messages never say whether an email exists.
/// Emailed one-time codes are a TODO: see
/// AdminAuthService.
/// ============================================
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/core/constants/app_constants.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/auth/services/admin_auth_service.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  final String initialEmail;
  const PasswordRecoveryScreen({super.key, this.initialEmail = ''});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends ConsumerState<PasswordRecoveryScreen> {
  int _step = 0; // 0 email, 1 PIN, 2 new password
  bool _busy = false;

  late final _emailCtrl = TextEditingController(text: widget.initialEmail);
  final _pinCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePin = true;
  bool _obscurePass = true;

  String? _emailError;
  String? _pinError;
  String? _passError;
  String? _confirmError;

  RecoveryTicket? _ticket;
  Duration _lockedFor = Duration.zero;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    _refreshLock();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLock() async {
    final left = await AdminAuthService.recoveryLockRemaining();
    if (!mounted) return;
    setState(() => _lockedFor = left);
    _lockTimer?.cancel();
    if (left > Duration.zero) {
      _lockTimer = Timer(const Duration(seconds: 1), _refreshLock);
    }
  }

  String get _lockText {
    final m = _lockedFor.inMinutes;
    final s = _lockedFor.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── Steps ──────────────────────────────────────────────────────────

  void _submitEmail() {
    final problem = AdminAuthService.emailProblem(_emailCtrl.text);
    setState(() => _emailError = problem);
    if (problem != null) return;
    // Always continue: whether the email exists is only checked together
    // with the PIN, so this step reveals nothing.
    setState(() => _step = 1);
  }

  Future<void> _submitPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < AppConstants.minPinLength) {
      setState(() => _pinError = 'Enter your ${AppConstants.minPinLength}–${AppConstants.maxPinLength} digit owner PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _pinError = null;
    });
    final check = await AdminAuthService.verifyRecoveryPin(
      ref.read(isarProvider),
      email: _emailCtrl.text,
      ownerPin: pin,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (check.result) {
      case RecoveryPinResult.verified:
        HapticFeedback.mediumImpact();
        setState(() {
          _ticket = check.ticket;
          _pinCtrl.clear();
          _step = 2;
        });
      case RecoveryPinResult.invalid:
        HapticFeedback.vibrate();
        setState(() {
          _pinCtrl.clear();
          _pinError = 'That email and owner PIN don\'t match an admin account. '
              '${check.attemptsLeft} attempt${check.attemptsLeft == 1 ? '' : 's'} left '
              'before recovery is locked for 15 minutes.';
        });
      case RecoveryPinResult.lockedOut:
        HapticFeedback.vibrate();
        _pinCtrl.clear();
        await _refreshLock();
    }
  }

  Future<void> _submitPassword() async {
    final pass = _passCtrl.text;
    final passProblem = AdminAuthService.passwordProblem(pass, email: _emailCtrl.text);
    final confirmProblem = pass != _confirmCtrl.text ? 'The passwords don\'t match.' : null;
    setState(() {
      _passError = passProblem;
      _confirmError = passProblem == null ? confirmProblem : null;
    });
    if (passProblem != null || confirmProblem != null) return;

    final ticket = _ticket;
    if (ticket == null || ticket.isExpired) {
      _restart('That took too long. Confirm your owner PIN again.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AdminAuthService.completeRecovery(
        ref.read(isarProvider),
        ticket: ticket,
        newPassword: pass,
      );
      // Ends any session still open on this device.
      ref.read(currentUserProvider.notifier).checkSessionStillValid();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      setState(() {
        _busy = false;
        _passError = e.message.toString();
      });
    } on StateError catch (e) {
      _restart(e.message);
    }
  }

  void _restart(String message) {
    setState(() {
      _busy = false;
      _ticket = null;
      _step = 1;
      _pinError = message;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locked = _lockedFor > Duration.zero;
    final (title, helper) = switch (_step) {
      0 => ('Reset admin password', 'Enter the email you use to sign in.'),
      1 => (
          'Confirm it\'s you',
          'Enter the owner PIN you chose during setup. If the email and PIN '
              'match the admin account, you can set a new password.'
        ),
      _ => ('Choose a new password', 'You\'ll use it to sign in from now on.'),
    };

    return Scaffold(
      backgroundColor: const Color(0xFF14151D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Step ${_step + 1} of 3'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: AppSpacing.borderXl,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / 3,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceBg,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(title, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(helper, style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.xl),
                    if (locked)
                      _LockedNotice(timeLeft: _lockText)
                    else
                      ...switch (_step) {
                        0 => _emailStep(),
                        1 => _pinStep(),
                        _ => _passwordStep(),
                      },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep() => [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _submitEmail(),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
          decoration: InputDecoration(
            labelText: 'Admin email',
            hintText: 'admin@yourstore.com',
            errorText: _emailError,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(onPressed: _submitEmail, child: const Text('Continue')),
      ];

  List<Widget> _pinStep() => [
        Text('Email: ${_emailCtrl.text.trim()}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: _obscurePin,
          maxLength: AppConstants.maxPinLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(letterSpacing: 4, fontSize: 18),
          onSubmitted: (_) => _submitPin(),
          onChanged: (_) {
            if (_pinError != null) setState(() => _pinError = null);
          },
          decoration: InputDecoration(
            labelText: 'Owner PIN',
            counterText: '',
            errorText: _pinError,
            errorMaxLines: 4,
            suffixIcon: IconButton(
              tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
              icon: Icon(_obscurePin ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscurePin = !_obscurePin),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(
          onPressed: _busy ? null : _submitPin,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verify PIN'),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: const Text('Use a different email'),
        ),
      ];

  List<Widget> _passwordStep() {
    final score = AdminAuthService.passwordScore(_passCtrl.text);
    const labels = ['Too weak', 'Weak', 'Fair', 'Good', 'Strong'];
    const colors = [
      AppColors.danger, AppColors.danger, AppColors.warning, AppColors.success, AppColors.success,
    ];
    return [
      TextField(
        controller: _passCtrl,
        obscureText: _obscurePass,
        autofillHints: const [AutofillHints.newPassword],
        onChanged: (_) => setState(() => _passError = null),
        decoration: InputDecoration(
          labelText: 'New password',
          helperText:
              'At least ${AdminAuthService.minPasswordLength} characters, with a letter and a number.',
          helperMaxLines: 2,
          errorText: _passError,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _obscurePass ? 'Show password' : 'Hide password',
            icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
        ),
      ),
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
                  color: colors[score],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(labels[score], style: TextStyle(color: colors[score], fontSize: 12)),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      TextField(
        controller: _confirmCtrl,
        obscureText: _obscurePass,
        autofillHints: const [AutofillHints.newPassword],
        onSubmitted: (_) => _submitPassword(),
        onChanged: (_) {
          if (_confirmError != null) setState(() => _confirmError = null);
        },
        decoration: InputDecoration(
          labelText: 'Confirm new password',
          errorText: _confirmError,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      ElevatedButton(
        onPressed: _busy ? null : _submitPassword,
        child: _busy
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Save new password'),
      ),
    ];
  }
}

class _LockedNotice extends StatelessWidget {
  final String timeLeft;
  const _LockedNotice({required this.timeLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: AppSpacing.borderMd,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_rounded, color: AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Too many wrong PINs. Password recovery is locked. Try again in $timeLeft.',
              style: const TextStyle(color: AppColors.dangerDarkText),
            ),
          ),
        ],
      ),
    );
  }
}
