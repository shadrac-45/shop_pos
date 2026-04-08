import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../providers/cart_provider.dart';
import '../../../providers/auth_provider.dart';

class CheckoutBottomSheet extends ConsumerStatefulWidget {
  const CheckoutBottomSheet({super.key});

  @override
  ConsumerState<CheckoutBottomSheet> createState() =>
      _CheckoutBottomSheetState();
}

class _CheckoutBottomSheetState extends ConsumerState<CheckoutBottomSheet> {
  String _selectedPayment = 'cash'; // 'cash', 'momo', 'split'

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final currentUser = ref.watch(currentUserProvider);

    if (cart.isEmpty) {
      Navigator.pop(context);
      return const SizedBox();
    }

    final total = cart.fold(0.0, (sum, item) => sum + item.subtotal);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Checkout',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Cart Items Summary
          ...cart.map((item) => ListTile(
                dense: true,
                title: Text(item.product.name),
                subtitle: Text(
                    '${item.quantity} × GHS ${item.product.price.toStringAsFixed(2)}'),
                trailing: Text(
                  'GHS ${(item.product.price * item.quantity).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              )),

          const Divider(height: 30),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(
                'GHS ${total.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Payment Method Selection
          const Text('Payment Method',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Row(
            children: [
              _paymentButton('Cash', 'cash', Icons.money),
              const SizedBox(width: 12),
              _paymentButton('Mobile Money', 'momo', Icons.phone_android),
            ],
          ),

          const SizedBox(height: 30),

          // Complete Sale Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                final success = await cartNotifier.completeSale(
                  _selectedPayment,
                  currentUser?.pinHash ?? '1234', // fallback for testing
                );

                if (success && mounted) {
                  Navigator.pop(context); // Close bottom sheet
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sale completed successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Complete Sale',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _paymentButton(String label, String value, IconData icon) {
    final isSelected = _selectedPayment == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedPayment = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.green : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.green : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.black87),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
