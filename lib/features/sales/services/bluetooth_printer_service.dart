/// ============================================
/// Bluetooth Printer Service — ShopPOS
/// ============================================
/// Sends ESC/POS bytes to a paired Bluetooth
/// thermal printer, and pulses the cash drawer
/// plugged into it.
/// ============================================
library;


import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrinterException implements Exception {
  final String message;
  PrinterException(this.message);
  @override
  String toString() => message;
}

class PairedPrinter {
  final String name;
  final String address;
  const PairedPrinter(this.name, this.address);
}

class BluetoothPrinterService {
  BluetoothPrinterService._();

  static Future<void> _ensureReady() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      throw PrinterException('Allow ShopPOS to use Bluetooth (Nearby devices) to print.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw PrinterException('Bluetooth is off. Turn it on to print.');
    }
  }

  /// Printers already paired in Android's Bluetooth settings.
  static Future<List<PairedPrinter>> pairedPrinters() async {
    await _ensureReady();
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return [for (final d in devices) PairedPrinter(d.name, d.macAdress)];
  }

  /// Connects to [address] if needed and sends [bytes].
  static Future<void> send(String address, Uint8List bytes) async {
    if (address.isEmpty) throw PrinterException('No printer selected.');
    await _ensureReady();
    if (!await PrintBluetoothThermal.connectionStatus) {
      final connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: address);
      if (!connected) {
        throw PrinterException(
            'Could not connect to the printer. Check it is on and in range.');
      }
    }
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      // A stale connection: reconnect once and retry.
      debugPrint('[Printer] write failed, reconnecting');
      await PrintBluetoothThermal.disconnect;
      if (!await PrintBluetoothThermal.connect(macPrinterAddress: address) ||
          !await PrintBluetoothThermal.writeBytes(bytes)) {
        throw PrinterException('The printer did not accept the receipt.');
      }
    }
  }
}
