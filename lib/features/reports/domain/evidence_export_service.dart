import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'inventory_report.dart';

/// User-initiated evidence export: a ZIP containing the inventory PDF plus
/// the original photos, receipt images and documents it references.
///
/// Everything stays user-controlled: this service only writes a ZIP into a
/// temp directory when the user asks for an export. Nothing is uploaded.
///
/// ZIP layout:
/// ```
/// keepit-evidence-YYYYMMDD-HHMMSS.zip
/// ├── inventory-report.pdf
/// ├── photos/<item-name>/<file>
/// ├── receipts/<file>
/// └── documents/<file>
/// ```
class EvidenceExportService {
  /// Writes the evidence ZIP into a temp directory and returns it.
  /// [pdfBytes] is the report from [PdfReportBuilder]. Missing files are
  /// skipped, never fatal.
  Future<File> createEvidenceZip({
    required InventoryReport report,
    required Uint8List pdfBytes,
  }) async {
    final staging = await Directory.systemTemp.createTemp(
      'keepit-evidence-staging',
    );
    try {
      await File(
        p.join(staging.path, 'inventory-report.pdf'),
      ).writeAsBytes(pdfBytes);

      for (final item in report.items) {
        for (final photoPath in item.photoPaths) {
          final name = _safeName(item.belonging.name);
          await _copyInto(photoPath, p.join(staging.path, 'photos', name));
        }
        final receiptPath = item.receipt?.imagePath;
        if (receiptPath != null && receiptPath.isNotEmpty) {
          await _copyInto(receiptPath, p.join(staging.path, 'receipts'));
        }
        for (final doc in item.documents) {
          await _copyInto(doc.filePath, p.join(staging.path, 'documents'));
        }
      }

      final zipPath = p.join(
        Directory.systemTemp.path,
        _zipName(DateTime.now()),
      );
      final encoder = ZipFileEncoder()..create(zipPath);
      await encoder.addDirectory(staging, includeDirName: false);
      encoder.close();
      return File(zipPath);
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String _zipName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'keepit-evidence-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }

  /// Copies [sourcePath] into [dir], keeping the original file name.
  /// Returns true when a file was actually copied.
  Future<bool> _copyInto(String sourcePath, String dir) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return false;
      final targetDir = Directory(dir);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      var target = File(p.join(dir, p.basename(sourcePath)));
      // Avoid collisions when two items reference the same file name.
      var n = 1;
      while (await target.exists()) {
        final base = p.basenameWithoutExtension(sourcePath);
        final ext = p.extension(sourcePath);
        target = File(p.join(dir, '$base-$n$ext'));
        n++;
      }
      await source.copy(target.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();
    return cleaned.isEmpty ? 'item' : cleaned;
  }
}
