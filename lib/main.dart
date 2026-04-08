import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/app_user.dart';
import 'models/batch.dart';
import 'models/product.dart';
import 'models/sale.dart';
import 'features/main/screens/main_shell_screen.dart';
import 'providers/database_provider.dart';   // ← FIXED: required for isarProvider

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Isar Database
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ProductSchema, BatchSchema, SaleSchema, AppUserSchema],
    directory: dir.path,
    inspector: true, // Set to false in production
  );

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const ShopPOSApp(),
    ),
  );
}

class ShopPOSApp extends StatelessWidget {
  const ShopPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopPOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MainShellScreen(),
    );
  }
}