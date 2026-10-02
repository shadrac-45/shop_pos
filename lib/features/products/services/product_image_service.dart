/// ============================================
/// Product Image Service — ShopPOS
/// ============================================
/// Takes or picks a product photo, shrinks it,
/// and keeps a copy in the app's own folder so it
/// survives the original being deleted.
/// ============================================
library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shop_pos/core/utils/id_helpers.dart';

class ProductImageService {
  ProductImageService._();

  static final _picker = ImagePicker();

  /// Returns the saved photo's path, or null if the user cancelled.
  static Future<String?> pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (picked == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/product_images');
    await dir.create(recursive: true);
    final dest = '${dir.path}/${IdHelpers.newUuid()}.jpg';
    await File(picked.path).copy(dest);
    return dest;
  }

  /// Deletes a photo this service saved (ignores anything else).
  static Future<void> delete(String? path) async {
    if (path == null || !path.contains('product_images')) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // A leftover file is harmless.
    }
  }

  /// True if [path] points at an existing file.
  static bool exists(String? path) => path != null && File(path).existsSync();
}
