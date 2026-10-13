/// ============================================
/// Join Shop Screen — ShopPOS
/// ============================================
/// A new device joins a shop that already exists
/// in ShopPOS Cloud:
///   1. the person signs in with their own
///      account (email or username + password);
///   2. picks one of the shops THEY are assigned
///      to (the cloud decides which);
///   3. the device registers in that shop and
///      downloads its products, stock, staff and
///      settings into its own local database.
/// No shop and no owner account are created.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/providers/store_settings_provider.dart';
import 'package:shop_pos/core/services/cloud_service.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/cloud/widgets/shop_picker.dart';
import 'package:shop_pos/features/main/screens/main_shell_screen.dart';

class JoinShopScreen extends ConsumerStatefulWidget {
  const JoinShopScreen({super.key});

  @override
  ConsumerState<JoinShopScreen> createState() => _JoinShopScreenState();
}

class _JoinShopScreenState extends ConsumerState<JoinShopScreen> {
  final _url = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _status;

  static const _lastUrlKey = 'shoppos.lastCloudUrl';

  @override
  void initState() {
    super.initState();
    // Remember the address between attempts (going back used to lose it).
    SharedPreferences.getInstance().then((p) {
      final last = p.getString(_lastUrlKey);
      if (mounted && last != null && _url.text.isEmpty) _url.text = last;
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_url, _id, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _join() async {
    if (_url.text.trim().isEmpty || _id.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter the cloud address, your email or username, and your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Signing in…';
    });
    final cleaned = CloudService.normaliseUrl(_url.text);
    if (cleaned.isNotEmpty) {
      _url.text = cleaned.replaceFirst(RegExp(r'/api$'), '');
      SharedPreferences.getInstance().then((p) => p.setString(_lastUrlKey, _url.text)).catchError((_) => false);
    }
    final login = await CloudService.login(url: _url.text, identifier: _id.text, password: _password.text);
    if (!mounted) return;
    if (!login.ok) {
      setState(() {
        _busy = false;
        _error = login.error;
        _status = null;
      });
      return;
    }
    if (login.shops.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Your account is not assigned to any shop yet. Ask the owner.';
        _status = null;
      });
      return;
    }
    final shop = await pickShop(context, login.shops);
    if (!mounted) return;
    if (shop == null) {
      setState(() {
        _busy = false;
        _status = null;
      });
      return;
    }
    setState(() => _status = 'Downloading ${shop.name}…');
    try {
      final isar = ref.read(isarProvider);
      final user = await CloudService.joinShop(isar, login, shop.id, fresh: true);
      if (!mounted) return;
      _password.clear();
      ref.invalidate(storeSettingsProvider);
      ref.read(currentUserProvider.notifier).setUser(user);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: AppColors.onInkMuted);
    InputDecoration deco(String text, {String? hint, Widget? suffix}) => InputDecoration(
          labelText: text,
          hintText: hint,
          labelStyle: label,
          hintStyle: const TextStyle(color: AppColors.onInkSubtle),
          filled: true,
          fillColor: AppColors.inkRaised,
          suffixIcon: suffix,
        );
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        // The app theme's dark title style would be invisible here.
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        title: const Text('Join an existing shop'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Sign in with the account the owner or manager created for you. '
                    'This device will join your shop and download its products, stock and staff.',
                    style: label,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco('Cloud address', hint: 'https://api.example.com'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _id,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco('Email or username'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _busy ? null : _join(),
                    decoration: deco('Password',
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.onInkMuted),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        )),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_status!, style: label),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login_rounded),
                    label: const Text('Sign in & join'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
