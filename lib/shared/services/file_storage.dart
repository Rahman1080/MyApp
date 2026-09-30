import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// App-private file storage.
///
/// Receipt images and attached documents are copied into the application's
/// private documents directory (never the public gallery or Downloads), so
/// they stay on the device and are removed when the app is uninstalled.
/// Nothing here ever uploads or logs file contents.
class FileStorage {
  FileStorage({Directory? appDocumentsDir}) : _appDocumentsDir = appDocumentsDir;

  final Directory? _appDocumentsDir;
  static const _uuid = Uuid();

  Future<Directory> _baseDir() async {
    final dir = _appDocumentsDir ?? await getApplicationDocumentsDirectory();
    return dir;
  }

  /// Copies [source] into `<app-docs>/receipts/<uuid>.<ext>` and returns it.
  Future<File> saveReceiptImage(File source) async {
    final receiptsDir = Directory(p.join((await _baseDir()).path, 'receipts'));
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    final ext = p.extension(source.path).toLowerCase();
    final safeExt = RegExp(r'^\.(jpg|jpeg|png|heic|webp)$').hasMatch(ext)
        ? ext
        : '.jpg';
    final target = File(p.join(receiptsDir.path, '${_uuid.v4()}$safeExt'));
    return source.copy(target.path);
  }

  /// Copies [source] into `<app-docs>/documents/<uuid>_<name>` and returns it.
  Future<File> saveDocument(File source, String originalName) async {
    final documentsDir =
        Directory(p.join((await _baseDir()).path, 'documents'));
    if (!await documentsDir.exists()) {
      await documentsDir.create(recursive: true);
    }
    final sanitized = originalName
        .replaceAll(RegExp(r'[^\w\-. ]'), '_')
        .replaceAll('..', '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final name = sanitized.isEmpty ? 'document' : sanitized;
    final target =
        File(p.join(documentsDir.path, '${_uuid.v4()}_$name'));
    return source.copy(target.path);
  }

  /// Copies [source] into `<app-docs>/belongings/<uuid>.<ext>` and returns
  /// it. Used for belonging photos; never stores the original path.
  Future<File> saveBelongingPhoto(File source) async {
    final belongingsDir =
        Directory(p.join((await _baseDir()).path, 'belongings'));
    if (!await belongingsDir.exists()) {
      await belongingsDir.create(recursive: true);
    }
    final ext = p.extension(source.path).toLowerCase();
    final safeExt = RegExp(r'^\.(jpg|jpeg|png|heic|webp)$').hasMatch(ext)
        ? ext
        : '.jpg';
    final target = File(p.join(belongingsDir.path, '${_uuid.v4()}$safeExt'));
    return source.copy(target.path);
  }

  /// Deletes a stored file if it exists. Never throws for missing files.
  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup: a stale path must not break deletion flows.
    }
  }
}
