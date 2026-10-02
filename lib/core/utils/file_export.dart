/// ============================================
/// File Export — ShopPOS
/// ============================================
/// Lets the user choose where to save a file
/// (Downloads, Google Drive, a USB stick…) using
/// the system save dialog.
/// ============================================
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class FileExport {
  FileExport._();

  /// Asks where to save [bytes] as [fileName] and writes them there.
  /// Returns where it was saved, or null if the user cancelled.
  static Future<Uri?> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String dialogTitle = 'Save file',
    List<String>? allowedExtensions,
  }) {
    return FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: dialogTitle,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
  }
}
