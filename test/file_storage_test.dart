import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:keepit/shared/services/file_storage.dart';

void main() {
  group('FileStorage', () {
    late Directory tempDir;
    late FileStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('keepit-storage-test');
      storage = FileStorage(appDocumentsDir: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saveReceiptImage copies into app-private receipts dir', () async {
      final source = File('${tempDir.path}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final saved = await storage.saveReceiptImage(source);

      expect(saved.path, contains('receipts'));
      expect(saved.path.startsWith(tempDir.path), isTrue);
      expect(await saved.exists(), isTrue);
      expect(await source.exists(), isTrue); // original untouched
    });

    test('saveReceiptImage rejects dangerous extensions', () async {
      final source = File('${tempDir.path}/evil.exe')
        ..writeAsBytesSync([1, 2, 3]);
      final saved = await storage.saveReceiptImage(source);
      expect(saved.path.endsWith('.jpg'), isTrue);
    });

    test('saveDocument sanitizes the file name', () async {
      final source = File('${tempDir.path}/src.pdf')
        ..writeAsBytesSync([1, 2, 3]);
      final saved = await storage.saveDocument(source, '../../etc/passwd.pdf');
      expect(saved.path, contains('documents'));
      expect(saved.path.contains('..'), isFalse);
      expect(await saved.exists(), isTrue);
    });

    test('deleteFile removes the file and tolerates missing paths', () async {
      final source = File('${tempDir.path}/gone.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await storage.deleteFile(source.path);
      expect(await source.exists(), isFalse);
      // Must not throw for null, empty, or already-deleted paths.
      await storage.deleteFile(null);
      await storage.deleteFile('');
      await storage.deleteFile(source.path);
    });
  });
}
