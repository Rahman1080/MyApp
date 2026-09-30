import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/keepit_database.dart';
import '../../core/database/tables.dart' show defaultPlaceId;

/// Thrown when a backup file is missing, corrupt, or in an unsupported
/// format. The [message] is safe to show to the user.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;

  @override
  String toString() => 'BackupException: $message';
}

/// What [BackupService.validateBackup] learned about a backup file without
/// changing any data.
class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.appVersion,
    required this.counts,
    required this.fileCount,
  });

  final DateTime createdAt;
  final String appVersion;
  final Map<String, int> counts;
  final int fileCount;

  int get totalRecords => counts.values.fold(0, (a, b) => a + b);

  factory BackupPreview.fromManifest(Map<String, dynamic> manifest) {
    final rawCounts = manifest['counts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        final value = entry.value;
        counts['${entry.key}'] = value is int
            ? value
            : int.tryParse('$value') ?? 0;
      }
    }
    DateTime createdAt;
    try {
      createdAt =
          DateTime.parse('${manifest['createdAt']}').toLocal();
    } catch (_) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return BackupPreview(
      createdAt: createdAt,
      appVersion: '${manifest['appVersion'] ?? 'unknown'}',
      counts: counts,
      fileCount: manifest['fileCount'] is int
          ? manifest['fileCount'] as int
          : 0,
    );
  }
}

/// Couples one drift table to its backup file name and JSON (de)serialization.
/// [_codecs] is ordered parents-first so restores satisfy foreign keys;
/// [_wipeOrder] is the reverse so deletes never violate them.
class _TableCodec {
  const _TableCodec({
    required this.name,
    required this.dump,
    required this.restoreRows,
    required this.wipe,
    this.optional = false,
    this.patchRow,
  });

  final String name;
  final Future<List<Map<String, dynamic>>> Function() dump;
  final Future<void> Function(List<Map<String, dynamic>> rows) restoreRows;
  final Future<void> Function() wipe;

  /// When true, a backup missing this table's file still restores (as empty)
  /// instead of failing. Used for tables added after the backup format was
  /// introduced, so older backups stay restorable.
  final bool optional;

  /// Fixes up a raw JSON row before [DataClass].fromJson runs. Used to fill
  /// in columns that did not exist when a legacy backup was written (e.g.
  /// `placeId` on locations, `isContainer` on belongings).
  final Map<String, dynamic> Function(Map<String, dynamic> row)? patchRow;
}

/// Creates versioned ZIP backups of the whole local database plus the
/// app-private files (receipts, documents, belonging photos), and restores
/// them. Everything is local: no server, no upload, no analytics.
///
/// Backup layout:
/// ```
/// keepit-backup-YYYYMMDD-HHMMSS.zip
/// ├── manifest.json            (formatVersion, appVersion, createdAt, counts)
/// ├── tables/<table>.json     (one JSON array per table)
/// └── files/<dir>/<file>      (receipts/, documents/, belongings/)
/// ```
class BackupService {
  BackupService({
    required KeepItDatabase db,
    required Directory filesRoot,
    Directory? tempRoot,
  })  : _db = db,
        _filesRoot = filesRoot,
        _tempRoot = tempRoot;

  final KeepItDatabase _db;
  final Directory _filesRoot;
  final Directory? _tempRoot;

  /// The backup format this build reads and writes.
  static const int formatVersion = 1;

  /// App-private directories mirrored into the backup.
  static const List<String> managedFileDirs = [
    'receipts',
    'documents',
    'belongings',
  ];

  static String backupFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'keepit-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.zip';
  }

  List<_TableCodec> get _codecs => [
        _codec<UserSetting>(
          'user_settings',
          () => _db.select(_db.userSettings).get(),
          UserSetting.fromJson,
          (row) => _db.into(_db.userSettings).insert(row),
          () => _db.delete(_db.userSettings).go(),
        ),
        _codec<Category>(
          'categories',
          () => _db.select(_db.categories).get(),
          Category.fromJson,
          (row) => _db.into(_db.categories).insert(row),
          () => _db.delete(_db.categories).go(),
        ),
        _codec<Tag>(
          'tags',
          () => _db.select(_db.tags).get(),
          Tag.fromJson,
          (row) => _db.into(_db.tags).insert(row),
          () => _db.delete(_db.tags).go(),
        ),
        // Places (Phase 10) come before locations: restores run
        // parents-first so foreign keys are satisfied. Optional so legacy
        // backups without a places file still restore.
        _TableCodec(
          name: 'places',
          dump: () async =>
              (await _db.select(_db.places).get())
                  .map((row) => row.toJson())
                  .toList(),
          restoreRows: (rows) async {
            for (final json in rows) {
              await _db.into(_db.places).insert(Place.fromJson(json));
            }
            // Legacy backups have no places file, yet their (patched)
            // locations point at the default place — and the place FK is
            // RESTRICT, so the row must exist before locations restore.
            final existing = await (_db.select(_db.places)
                  ..where((t) => t.id.equals(defaultPlaceId)))
                .getSingleOrNull();
            if (existing == null) {
              await _db.into(_db.places).insert(
                    PlacesCompanion.insert(
                      id: const Value(defaultPlaceId),
                      name: 'My Home',
                    ),
                  );
            }
          },
          wipe: () => _db.delete(_db.places).go(),
          optional: true,
        ),
        _codec<Location>(
          'locations',
          () => _db.select(_db.locations).get(),
          Location.fromJson,
          (row) => _db.into(_db.locations).insert(row),
          () => _db.delete(_db.locations).go(),
          // Legacy backups predate places: point their locations at the
          // default place (created by the places codec below).
          patchRow: (row) {
            row.putIfAbsent('placeId', () => defaultPlaceId);
            return row;
          },
        ),
        _codec<Purchase>(
          'purchases',
          () => _db.select(_db.purchases).get(),
          Purchase.fromJson,
          (row) => _db.into(_db.purchases).insert(row),
          () => _db.delete(_db.purchases).go(),
        ),
        _codec<Product>(
          'products',
          () => _db.select(_db.products).get(),
          Product.fromJson,
          (row) => _db.into(_db.products).insert(row),
          () => _db.delete(_db.products).go(),
        ),
        _codec<Receipt>(
          'receipts',
          () => _db.select(_db.receipts).get(),
          Receipt.fromJson,
          (row) => _db.into(_db.receipts).insert(row),
          () => _db.delete(_db.receipts).go(),
        ),
        _codec<Warranty>(
          'warranties',
          () => _db.select(_db.warranties).get(),
          Warranty.fromJson,
          (row) => _db.into(_db.warranties).insert(row),
          () => _db.delete(_db.warranties).go(),
        ),
        _codec<ReturnDeadline>(
          'return_deadlines',
          () => _db.select(_db.returnDeadlines).get(),
          ReturnDeadline.fromJson,
          (row) => _db.into(_db.returnDeadlines).insert(row),
          () => _db.delete(_db.returnDeadlines).go(),
        ),
        _codec<Refund>(
          'refunds',
          () => _db.select(_db.refunds).get(),
          Refund.fromJson,
          (row) => _db.into(_db.refunds).insert(row),
          () => _db.delete(_db.refunds).go(),
        ),
        _codec<Deadline>(
          'deadlines',
          () => _db.select(_db.deadlines).get(),
          Deadline.fromJson,
          (row) => _db.into(_db.deadlines).insert(row),
          () => _db.delete(_db.deadlines).go(),
        ),
        _codec<Belonging>(
          'belongings',
          () => _db.select(_db.belongings).get(),
          Belonging.fromJson,
          (row) => _db.into(_db.belongings).insert(row),
          () => _db.delete(_db.belongings).go(),
          // Legacy backups predate container mode: nothing was a
          // container and nothing sat inside one.
          patchRow: (row) {
            row.putIfAbsent('isContainer', () => false);
            return row;
          },
        ),
        _codec<BelongingPhoto>(
          'belonging_photos',
          () => _db.select(_db.belongingPhotos).get(),
          BelongingPhoto.fromJson,
          (row) => _db.into(_db.belongingPhotos).insert(row),
          () => _db.delete(_db.belongingPhotos).go(),
          optional: true,
        ),
        _codec<BelongingHistoryData>(
          'belonging_history',
          () => _db.select(_db.belongingHistory).get(),
          BelongingHistoryData.fromJson,
          (row) => _db.into(_db.belongingHistory).insert(row),
          () => _db.delete(_db.belongingHistory).go(),
          optional: true,
        ),
        _codec<Document>(
          'documents',
          () => _db.select(_db.documents).get(),
          Document.fromJson,
          (row) => _db.into(_db.documents).insert(row),
          () => _db.delete(_db.documents).go(),
        ),
        _codec<Reminder>(
          'reminders',
          () => _db.select(_db.reminders).get(),
          Reminder.fromJson,
          (row) => _db.into(_db.reminders).insert(row),
          () => _db.delete(_db.reminders).go(),
        ),
        _codec<TagLink>(
          'tag_links',
          () => _db.select(_db.tagLinks).get(),
          TagLink.fromJson,
          (row) => _db.into(_db.tagLinks).insert(row),
          () => _db.delete(_db.tagLinks).go(),
        ),
        // Moves (Phase 12) come before move_items: restores run
        // parents-first so foreign keys are satisfied. Optional so legacy
        // backups without moves still restore.
        _codec<Move>(
          'moves',
          () => _db.select(_db.moves).get(),
          Move.fromJson,
          (row) => _db.into(_db.moves).insert(row),
          () => _db.delete(_db.moves).go(),
          optional: true,
        ),
        _codec<MoveItem>(
          'move_items',
          () => _db.select(_db.moveItems).get(),
          MoveItem.fromJson,
          (row) => _db.into(_db.moveItems).insert(row),
          () => _db.delete(_db.moveItems).go(),
          optional: true,
        ),
      ];

  _TableCodec _codec<T extends DataClass>(
    String name,
    Future<List<T>> Function() selectAll,
    T Function(Map<String, dynamic>) fromJson,
    Future<void> Function(T row) insert,
    Future<void> Function() wipe, {
    bool optional = false,
    Map<String, dynamic> Function(Map<String, dynamic> row)? patchRow,
  }) {
    return _TableCodec(
      name: name,
      dump: () async =>
          (await selectAll()).map((row) => row.toJson()).toList(),
      restoreRows: (rows) async {
        for (final json in rows) {
          await insert(fromJson(patchRow == null ? json : patchRow(json)));
        }
      },
      wipe: wipe,
      optional: optional,
      patchRow: patchRow,
    );
  }

  /// Tables in child-first order for safe deletion.
  List<_TableCodec> get _wipeOrder => _codecs.reversed.toList();

  Future<Directory> _scratchDir(String prefix) async {
    final root = _tempRoot ?? await getTemporaryDirectory();
    final dir = Directory(
      p.join(
        root.path,
        '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Writes a complete backup ZIP into a temp directory and returns it.
  /// [onProgress] receives 0.0–1.0 as tables are dumped.
  Future<File> createBackup({
    required String appVersion,
    void Function(double progress)? onProgress,
  }) async {
    final staging = await _scratchDir('keepit-backup-staging');
    try {
      final codecs = _codecs;
      final counts = <String, int>{};
      final tablesDir =
          Directory(p.join(staging.path, 'tables'));
      await tablesDir.create(recursive: true);

      for (var i = 0; i < codecs.length; i++) {
        final codec = codecs[i];
        final rows = await codec.dump();
        await File(p.join(tablesDir.path, '${codec.name}.json'))
            .writeAsString(jsonEncode(rows));
        counts[codec.name] = rows.length;
        onProgress?.call((i + 1) / (codecs.length + 1));
      }

      var fileCount = 0;
      final filesDir = Directory(p.join(staging.path, 'files'));
      for (final dir in managedFileDirs) {
        final src = Directory(p.join(_filesRoot.path, dir));
        if (!await src.exists()) continue;
        await for (final entity
            in src.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final rel = p.relative(entity.path, from: src.path);
          final target = File(p.join(filesDir.path, dir, rel));
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
          fileCount++;
        }
      }

      final manifest = <String, dynamic>{
        'formatVersion': formatVersion,
        'appName': 'KeepIt',
        'appVersion': appVersion,
        'schemaVersion': _db.schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'counts': counts,
        'fileCount': fileCount,
      };
      await File(p.join(staging.path, 'manifest.json'))
          .writeAsString(jsonEncode(manifest));
      onProgress?.call(1.0);

      final tempRoot = _tempRoot ?? await getTemporaryDirectory();
      final zipPath =
          p.join(tempRoot.path, backupFileName(DateTime.now()));
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

  /// Reads and validates a backup file without changing any data.
  /// Throws [BackupException] with a user-safe message when the file is not
  /// a readable KeepIt backup.
  Future<BackupPreview> validateBackup(File zip) async {
    final archive = await _decodeArchive(zip);
    final manifest = _readManifest(archive);
    return BackupPreview.fromManifest(manifest);
  }

  /// Restores [zip] over the current data:
  /// 1. validates the manifest (unknown versions are rejected, never
  ///    silently applied),
  /// 2. parses every table into memory first (dry run — format errors abort
  ///    before anything is touched),
  /// 3. swaps the file directories aside with a `.bak` fallback,
  /// 4. wipes and re-inserts all rows inside one transaction, verifying
  ///    foreign keys afterwards,
  /// 5. on any failure, puts the old files back and rethrows — the previous
  ///    data is never left half-restored.
  Future<void> restoreBackup(File zip) async {
    final archive = await _decodeArchive(zip);
    _readManifest(archive); // throws when unsupported — never silently applied
    final codecs = _codecs;

    // Dry run: parse everything before touching current data.
    final parsed = <_TableCodec, List<Map<String, dynamic>>>{};
    for (final codec in codecs) {
      final file = _findEntry(archive, 'tables/${codec.name}.json');
      if (file == null) {
        if (codec.optional) {
          // Table added after this backup was written: restore as empty.
          parsed[codec] = [];
          continue;
        }
        throw BackupException(
          'This backup is incomplete: tables/${codec.name}.json is missing.',
        );
      }
      try {
        final decoded = jsonDecode(utf8.decode(file.content));
        parsed[codec] = [
          for (final row in decoded as List)
            Map<String, dynamic>.from(row as Map),
        ];
      } catch (_) {
        throw BackupException(
          'This backup is corrupt: tables/${codec.name}.json is unreadable.',
        );
      }
    }

    // Stage the backed-up files into a temp directory.
    final staging = await _scratchDir('keepit-restore-staging');
    try {
      for (final entry in archive.files) {
        if (!entry.isFile || !entry.name.startsWith('files/')) continue;
        final target = File(p.join(staging.path, entry.name));
        final normalized = p.normalize(target.absolute.path);
        if (!p.isWithin(staging.absolute.path, normalized)) {
          throw BackupException(
            'This backup contains an unsafe file path and was rejected.',
          );
        }
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.content);
      }

      // Swap current file dirs aside; the staged ones take their place.
      final backups = <String, Directory>{};
      for (final dir in managedFileDirs) {
        final current = Directory(p.join(_filesRoot.path, dir));
        final bak = Directory(p.join(_filesRoot.path, '$dir.bak'));
        if (await bak.exists()) await bak.delete(recursive: true);
        if (await current.exists()) await current.rename(bak.path);
        backups[dir] = bak;
        final staged = Directory(p.join(staging.path, 'files', dir));
        if (await staged.exists()) {
          await staged.rename(current.path);
        } else {
          await current.create(recursive: true);
        }
      }

      Future<void> rollbackFiles() async {
        for (final dir in managedFileDirs) {
          final current = Directory(p.join(_filesRoot.path, dir));
          final bak = backups[dir]!;
          try {
            if (await current.exists()) {
              await current.delete(recursive: true);
            }
            if (await bak.exists()) await bak.rename(current.path);
          } catch (_) {}
        }
      }

      try {
        await _db.transaction(() async {
          for (final codec in _wipeOrder) {
            await codec.wipe();
          }
          for (final codec in codecs) {
            await codec.restoreRows(parsed[codec]!);
          }
          // A backup always carries its settings row; if it didn't, keep
          // the app bootable with a fresh default row.
          final settings =
              await _db.select(_db.userSettings).get();
          if (settings.isEmpty) {
            await _db.into(_db.userSettings).insert(
                  UserSettingsCompanion.insert(id: 'default'),
                );
          }
          final violations =
              await _db.customSelect('PRAGMA foreign_key_check').get();
          if (violations.isNotEmpty) {
            throw BackupException(
              'This backup failed data-integrity checks and was not applied.',
            );
          }
        });
      } catch (e) {
        await rollbackFiles();
        rethrow;
      }

      for (final dir in managedFileDirs) {
        final bak = Directory(p.join(_filesRoot.path, '$dir.bak'));
        try {
          if (await bak.exists()) await bak.delete(recursive: true);
        } catch (_) {}
      }
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Deletes every row and every stored file, then recreates the default
  /// settings row. The caller is responsible for clearing the PIN and
  /// cancelling notifications separately.
  Future<void> wipeAllData() async {
    await _db.transaction(() async {
      for (final codec in _wipeOrder) {
        await codec.wipe();
      }
      await _db.into(_db.userSettings).insert(
            UserSettingsCompanion.insert(id: 'default'),
          );
    });
    for (final dir in managedFileDirs) {
      final target = Directory(p.join(_filesRoot.path, dir));
      try {
        if (await target.exists()) await target.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<Archive> _decodeArchive(File zip) async {
    try {
      final bytes = await zip.readAsBytes();
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw BackupException('This file is not a valid ZIP archive.');
    }
  }

  Map<String, dynamic> _readManifest(Archive archive) {
    final entry = _findEntry(archive, 'manifest.json');
    if (entry == null) {
      throw BackupException(
        'Not a KeepIt backup: manifest.json is missing.',
      );
    }
    try {
      final manifest =
          jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
      if (manifest['formatVersion'] != formatVersion ||
          manifest['appName'] != 'KeepIt') {
        throw BackupException(
          'Unsupported backup format '
          '(version ${manifest['formatVersion']}). This version of KeepIt '
          'reads backup format $formatVersion.',
        );
      }
      return manifest;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException(
        'Not a KeepIt backup: the manifest is corrupt.',
      );
    }
  }

  ArchiveFile? _findEntry(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.isFile && (file.name == name || file.name.endsWith('/$name'))) {
        return file;
      }
    }
    return null;
  }
}
