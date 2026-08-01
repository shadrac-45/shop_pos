/// ============================================
/// Developer & Debug Panel — ShopPOS
/// ============================================
/// Dedicated diagnostic and configuration screen for
/// developers/engineers to test backend API endpoints,
/// adjust LAN IPs, inspect gateway status, and verify build flags.
/// Hidden from standard Cashier/Owner UI flow.
/// ============================================
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../providers/backend_config_provider.dart';
import '../../../services/paystack_service.dart';
import '../../common/widgets/touchable_card.dart';

class DeveloperDebugScreen extends ConsumerStatefulWidget {
  const DeveloperDebugScreen({super.key});

  @override
  ConsumerState<DeveloperDebugScreen> createState() => _DeveloperDebugScreenState();
}

class _DeveloperDebugScreenState extends ConsumerState<DeveloperDebugScreen> {
  bool _isTestingConnection = false;
  bool? _lastConnectionStatus;

  Future<void> _testBackendConnection() async {
    setState(() {
      _isTestingConnection = true;
      _lastConnectionStatus = null;
    });

    final paystackService = ref.read(paystackServiceProvider);
    final isSuccess = await paystackService.testConnection();

    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _lastConnectionStatus = isSuccess;
      });

      if (isSuccess) {
        context.showSuccessSnackbar('Backend Connection Successful! (200 OK)');
      } else {
        context.showErrorSnackbar('Backend Unreachable! Verify server is running on LAN IP.');
      }
    }
  }

  void _showEditUrlDialog(String currentUrl) {
    final controller = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('Backend API Base URL', style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the IP address of the machine running the backend Node server.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'http://192.168.x.x:3000/api',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Quick Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('Host PC (10.68.171.116)', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.text = 'http://10.68.171.116:3000/api',
                  ),
                  ActionChip(
                    label: const Text('Emulator (10.0.2.2)', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.text = 'http://10.0.2.2:3000/api',
                  ),
                  ActionChip(
                    label: const Text('Localhost', style: TextStyle(fontSize: 11)),
                    onPressed: () => controller.text = 'http://localhost:3000/api',
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newUrl = controller.text.trim();
                if (newUrl.isNotEmpty) {
                  ref.read(backendUrlProvider.notifier).state = newUrl;
                  Navigator.pop(ctx);
                  _testBackendConnection();
                }
              },
              child: const Text('Save & Test'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final backendUrl = ref.watch(backendUrlProvider);
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Developer & Debug Panel'),
        backgroundColor: AppColors.cardBg,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Warning Developer Banner
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: AppSpacing.borderMd,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.developer_mode_rounded, color: AppColors.warning),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'DEVELOPER PANEL — Infrastructure diagnostics & API endpoint settings for hardware/network setup.',
                      style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const Text(
              'PAYMENT GATEWAY CONFIGURATION',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Paystack Integration Status
            TouchableCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: AppSpacing.borderMd,
                  ),
                  child: const Icon(Icons.phone_android_rounded, color: AppColors.warning),
                ),
                title: const Text('Paystack Mobile Money (Ghana)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('MTN, Vodafone, AirtelTigo Push Payments', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    borderRadius: AppSpacing.borderSm,
                  ),
                  child: const Text('TEST MODE', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const Text(
              'BACKEND ENDPOINT & HEALTH CHECK',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            TouchableCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dns_rounded, color: AppColors.primary),
                    title: const Text('Backend API Base URL'),
                    subtitle: Text(
                      backendUrl,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textPrimary),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
                      onPressed: () => _showEditUrlDialog(backendUrl),
                    ),
                  ),

                  // Health Check Button Row
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isTestingConnection ? null : _testBackendConnection,
                          icon: _isTestingConnection
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                )
                              : const Icon(Icons.sync_rounded, size: 16),
                          label: const Text('Test Connection', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            side: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_lastConnectionStatus != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _lastConnectionStatus!
                                  ? AppColors.success.withValues(alpha: 0.15)
                                  : AppColors.danger.withValues(alpha: 0.15),
                              borderRadius: AppSpacing.borderSm,
                              border: Border.all(
                                color: _lastConnectionStatus! ? AppColors.success : AppColors.danger,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _lastConnectionStatus! ? Icons.check_circle_rounded : Icons.error_rounded,
                                  size: 14,
                                  color: _lastConnectionStatus! ? AppColors.success : AppColors.danger,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _lastConnectionStatus! ? 'ONLINE (200 OK)' : 'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _lastConnectionStatus! ? AppColors.success : AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            const Text(
              'SYSTEM & FRAMEWORK DIAGNOSTICS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            TouchableCard(
              child: Column(
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.touch_app_rounded, color: AppColors.info),
                    title: Text('Touch Target Enforcement'),
                    subtitle: Text('Optimized for Touchscreens (≥48×48 dp)'),
                    trailing: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bug_report_rounded, color: AppColors.warning),
                    title: Text('Flutter Build Mode'),
                    subtitle: Text(kDebugMode ? 'Debug / Development Build' : 'Release / Production Build'),
                    trailing: _BuildModeBadge(),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.aspect_ratio_rounded, color: AppColors.textSecondary),
                    title: const Text('Viewport Metrics'),
                    subtitle: Text('${mq.size.width.toInt()} × ${mq.size.height.toInt()} dp (PixelRatio: ${mq.devicePixelRatio.toStringAsFixed(1)})'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildModeBadge extends StatelessWidget {
  const _BuildModeBadge();

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (kDebugMode ? AppColors.warning : AppColors.success).withValues(alpha: 0.15),
        borderRadius: AppSpacing.borderSm,
      ),
      child: Text(
        kDebugMode ? 'DEBUG' : 'RELEASE',
        style: textStyle.copyWith(
          color: kDebugMode ? AppColors.warning : AppColors.success,
        ),
      ),
    );
  }
}
