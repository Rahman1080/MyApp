import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/shared/services/backup_service.dart';
import 'package:path/path.dart' as p;

const _tableNames = [
  'user_settings',
  'categories',
  'locations',
  'purchases',
  'products',
  'receipts',
  'warranties',
  'return_deadlines',
  'refunds',
  'deadlines',
  'belongings',
  'documents',
  'reminders',
  'tags',
  'tag_links',
];

void main() {
  late Directory sandbox;
  late Directory filesRoot;
  late Directory tempRoot;
  late KeepItDatabase db;
  late BackupService service;

  setUp(() async {
    sandbox =
        await Directory.systemTemp.createTemp('keepit-backup-test');
    filesRoot = Directory(p.join(sandbox.path, 'files'))
      ..createSync(recursive: true);
    tempRoot = Directory(p.join(sandbox.path, 'tmp'))
      ..createSync(recursive: true);
    db = openInMemoryDatabase();
    service = BackupService(db: db, filesRoot: filesRoot, tempRoot: tempRoot);
  });

  tearDown(() async {
    await db.close();
    await sandbox.delete(recursive: true);
  });

  Future<void> seedPurchaseWithReceipt() async {
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: const Value('p1'),
            productName: 'Drill',
            priceCents: const Value(4999),
          ),
        );
    final receiptDir = Directory(p.join(filesRoot.path, 'receipts'))
      ..createSync(recursive: true);
    final image = File(p.join(receiptDir.path, 'r1.jpg'));
    await image.writeAsBytes([1, 2, 3, 4]);
    await db.into(db.receipts).insert(
          ReceiptsCompanion.insert(
            id: const Value('r1'),
            purchaseId: 'p1',
            imagePath: Value(image.path),
          ),
        );
  }

  Map<String, dynamic> manifestOf(Archive archive) {
    final file =
        archive.files.firstWhere((f) => f.name == 'manifest.json');
    return jsonDecode(utf8.decode(file.content)) as Map<String, dynamic>;
  }

  File writeZip(Map<String, List<int>> entries, String name) {
    final archive = Archive();
    entries.forEach((entryName, bytes) {
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
    });
    final file = File(p.join(tempRoot.path, name));
    file.writeAsBytesSync(ZipEncoder().encode(archive));
    return file;
  }

  Map<String, List<int>> validManifestEntries({int formatVersion = 1}) {
    final entries = <String, List<int>>{
      'manifest.json': utf8.encode(jsonEncode({
        'formatVersion': formatVersion,
        'appName': 'KeepIt',
        'appVersion': 'test',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'counts': <String, int>{},
        'fileCount': 0,
      })),
    };
    for (final table in _tableNames) {
      entries['tables/$table.json'] = utf8.encode('[]');
    }
    return entries;
  }

  group('createBackup', () {
    test('produces a versioned ZIP with manifest, tables and files',
        () async {
      await seedPurchaseWithReceipt();

      final zip =
          await service.createBackup(appVersion: '1.0.0-test');
      expect(await zip.exists(), isTrue);
      expect(p.basename(zip.path).startsWith('keepit-backup-'), isTrue);
      expect(p.extension(zip.path), '.zip');

      final archive =
          ZipDecoder().decodeBytes(await zip.readAsBytes());
      final manifest = manifestOf(archive);
      expect(manifest['formatVersion'],
          BackupService.formatVersion);
      expect(manifest['appName'], 'KeepIt');
      expect(manifest['appVersion'], '1.0.0-test');
      expect((manifest['counts'] as Map)['purchases'], 1);
      expect((manifest['counts'] as Map)['receipts'], 1);
      expect(manifest['fileCount'], 1);

      final tables = {
        for (final f in archive.files)
          if (f.name.startsWith('tables/')) f.name: f,
      };
      for (final table in _tableNames) {
        expect(tables, contains('tables/$table.json'),
            reason: 'missing tables/$table.json');
      }
      final purchases = jsonDecode(
          utf8.decode(tables['tables/purchases.json']!.content)) as List;
      expect(purchases, hasLength(1));
      expect(purchases.first['productName'], 'Drill');

      final receiptEntry = archive.files
          .firstWhere((f) => f.name == 'files/receipts/r1.jpg');
      expect(receiptEntry.content, [1, 2, 3, 4]);
    });

    test('works with an empty database', () async {
      final zip = await service.createBackup(appVersion: '1.0.0-test');
      final archive =
          ZipDecoder().decodeBytes(await zip.readAsBytes());
      final manifest = manifestOf(archive);
      expect(manifest['formatVersion'], BackupService.formatVersion);
      expect((manifest['counts'] as Map)['purchases'], 0);
    });
  });

  group('validateBackup', () {
    test('rejects a corrupt ZIP', () async {
      final bad = File(p.join(tempRoot.path, 'bad.zip'))
        ..writeAsBytesSync([0, 1, 2, 3]);
      await expectLater(
        service.validateBackup(bad),
        throwsA(isA<BackupException>()),
      );
    });

    test('rejects a ZIP without a manifest', () async {
      final zip = writeZip(
          {'tables/purchases.json': utf8.encode('[]')}, 'nomanifest.zip');
      await expectLater(
        service.validateBackup(zip),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('manifest.json'),
        )),
      );
    });

    test('rejects an unsupported format version', () async {
      final zip = writeZip(
          validManifestEntries(formatVersion: 999), 'future.zip');
      await expectLater(
        service.validateBackup(zip),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported backup format'),
        )),
      );
    });

    test('accepts a valid backup and reports its contents', () async {
      await seedPurchaseWithReceipt();
      final zip = await service.createBackup(appVersion: '9.9.9-test');

      final preview = await service.validateBackup(zip);
      expect(preview.appVersion, '9.9.9-test');
      expect(preview.counts['purchases'], 1);
      expect(preview.counts['receipts'], 1);
      expect(preview.fileCount, 1);
      expect(preview.totalRecords, greaterThanOrEqualTo(2));
    });
  });

  group('restoreBackup', () {
    test('export then import restores records and files', () async {
      await seedPurchaseWithReceipt();
      final zip = await service.createBackup(appVersion: 'test');

      await service.wipeAllData();
      expect(await db.select(db.purchases).get(), isEmpty);
      expect(
        await Directory(p.join(filesRoot.path, 'receipts')).exists(),
        isFalse,
      );

      await service.restoreBackup(zip);

      final purchases = await db.select(db.purchases).get();
      expect(purchases, hasLength(1));
      expect(purchases.first.productName, 'Drill');
      expect(purchases.first.priceCents, 4999);

      final receipts = await db.select(db.receipts).get();
      expect(receipts, hasLength(1));
      expect(receipts.first.purchaseId, 'p1');

      final restored =
          File(p.join(filesRoot.path, 'receipts', 'r1.jpg'));
      expect(await restored.exists(), isTrue);
      expect(await restored.readAsBytes(), [1, 2, 3, 4]);
    });

    test('aborts before touching data when a table is corrupt', () async {
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: const Value('original'),
              productName: 'Original',
            ),
          );

      final entries = validManifestEntries();
      entries['tables/purchases.json'] = utf8.encode('this is not json');
      final zip = writeZip(entries, 'corrupt-table.zip');

      await expectLater(
        service.restoreBackup(zip),
        throwsA(isA<BackupException>()),
      );

      // The dry run failed before anything was wiped: original data intact.
      final purchases = await db.select(db.purchases).get();
      expect(purchases.map((row) => row.productName), contains('Original'));
    });

    test('rejects backups with unsafe file paths', () async {
      final entries = validManifestEntries();
      entries['files/../../evil.txt'] = [1, 2, 3];
      final zip = writeZip(entries, 'unsafe.zip');

      await expectLater(
        service.restoreBackup(zip),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('unsafe file path'),
        )),
      );
      expect(
        await File(p.join(sandbox.path, 'evil.txt')).exists(),
        isFalse,
      );
    });

    test('rejects a backup missing a table file', () async {
      final entries = validManifestEntries()
        ..remove('tables/purchases.json');
      final zip = writeZip(entries, 'incomplete.zip');

      await expectLater(
        service.restoreBackup(zip),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('incomplete'),
        )),
      );
    });
  });

  group('wipeAllData', () {
    test('removes rows and files, keeping a default settings row', () async {
      await seedPurchaseWithReceipt();

      await service.wipeAllData();

      expect(await db.select(db.purchases).get(), isEmpty);
      expect(await db.select(db.receipts).get(), isEmpty);
      expect(
        await Directory(p.join(filesRoot.path, 'receipts')).exists(),
        isFalse,
      );
      final settings = await db.select(db.userSettings).get();
      expect(settings, hasLength(1));
      expect(settings.single.id, 'default');
    });
  });
}
