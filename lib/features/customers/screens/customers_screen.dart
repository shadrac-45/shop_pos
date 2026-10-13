/// ============================================
/// Customers Screen — ShopPOS
/// ============================================
/// The shop's customers: search, add, edit.
/// Stored on this till and shared with the
/// shop's other tills through cloud sync (newest
/// edit wins). Needs the sell permission.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';

import 'package:shop_pos/core/auth/permissions.dart';
import 'package:shop_pos/core/database/database_provider.dart';
import 'package:shop_pos/core/extensions/context_extensions.dart';
import 'package:shop_pos/core/theme/app_colors.dart';
import 'package:shop_pos/core/theme/app_spacing.dart';
import 'package:shop_pos/core/utils/id_helpers.dart';
import 'package:shop_pos/features/auth/providers/auth_provider.dart';
import 'package:shop_pos/features/customers/models/customer.dart';
import 'package:shop_pos/features/shared/widgets/glass.dart';

final customersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.customers.where().sortByName().watch(fireImmediately: true);
});

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';

  Future<void> _edit([Customer? existing]) async {
    final user = ref.read(currentUserProvider);
    if (!Permissions.can(user, Permission.sell)) {
      context.showErrorSnackbar('Your role cannot manage customers.');
      return;
    }
    final name = TextEditingController(text: existing?.name);
    final phone = TextEditingController(text: existing?.phone);
    final email = TextEditingController(text: existing?.email);
    final notes = TextEditingController(text: existing?.notes);
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New customer' : 'Edit customer'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    String? blank(String s) => s.trim().isEmpty ? null : s.trim();
    final isar = ref.read(isarProvider);
    final c = existing ?? (Customer()..uuid = IdHelpers.newUuid());
    c
      ..name = name.text.trim()
      ..phone = blank(phone.text)
      ..email = blank(email.text)
      ..notes = blank(notes.text)
      ..updatedAt = DateTime.now()
      ..modifiedBy = user!.id
      ..isSynced = false;
    await isar.writeTxn(() => isar.customers.put(c));
    if (mounted) context.showSuccessSnackbar('Saved ${c.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name or phone'),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: customers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (all) {
              final list = all
                  .where((c) =>
                      _query.isEmpty ||
                      c.name.toLowerCase().contains(_query) ||
                      (c.phone ?? '').contains(_query))
                  .toList();
              if (list.isEmpty) {
                return const Center(
                    child: Text('No customers yet.', style: TextStyle(color: AppColors.textSecondary)));
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                    title: Text(c.name),
                    subtitle: Text([c.phone, c.email].whereType<String>().join(' · ')),
                    trailing: c.isSynced
                        ? null
                        : const Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.textMuted),
                    onTap: () => _edit(c),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
