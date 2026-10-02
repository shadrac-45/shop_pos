/// ============================================
/// Isar Schemas — ShopPOS
/// ============================================
/// Every collection the app stores. Used by
/// main.dart to open the database and by tests,
/// so a new collection only needs adding here.
/// ============================================
library;

import 'package:isar/isar.dart';

import 'package:shop_pos/core/models/store_settings.dart';
import 'package:shop_pos/features/activity/models/activity_log.dart';
import 'package:shop_pos/features/auth/models/app_user.dart';
import 'package:shop_pos/features/expenses/models/expense.dart';
import 'package:shop_pos/features/products/models/batch.dart';
import 'package:shop_pos/features/products/models/product.dart';
import 'package:shop_pos/features/products/models/stock_movement.dart';
import 'package:shop_pos/features/sales/models/sale.dart';
import 'package:shop_pos/features/sales/models/sale_item.dart';
import 'package:shop_pos/features/shifts/models/shift.dart';

const List<CollectionSchema<dynamic>> allSchemas = [
  ProductSchema,
  BatchSchema,
  SaleSchema,
  SaleItemSchema,
  AppUserSchema,
  StoreSettingsSchema,
  StockMovementSchema,
  ExpenseSchema,
  ShiftSchema,
  ActivityLogSchema,
];
