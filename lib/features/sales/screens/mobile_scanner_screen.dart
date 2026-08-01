/// ============================================
/// Mobile Scanner Screen — ShopPOS
/// ============================================
/// Dedicated route for barcode scanning.
/// Extracted from cashier_sales_screen.dart to
/// honour Single Responsibility — each file
/// does one thing.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Pushes [MobileScanner] and pops with the scanned barcode string.
class MobileScannerScreen extends StatelessWidget {
  const MobileScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcode = capture.barcodes.first.rawValue;
          if (barcode != null) {
            Navigator.pop(context, barcode);
          }
        },
      ),
    );
  }
}
