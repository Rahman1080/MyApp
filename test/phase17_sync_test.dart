import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/sync/domain/sync_service.dart';

/// Phase 17: Cloud Backup and Cross-Device Sync.
void main() {
  late KeepItDatabase db;
  late BelongingRepository belongings;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    belongings = BelongingRepository(db);
  });

  tearDown(() => db.close());

  group('Phase 17 Sync', () {
    test('exportChanges includes all belongings', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);
      final sync = SyncService(db, provider, 'device-a');

      final changes = await sync.exportChanges(null);
      expect(changes['deviceId'], 'device-a');
      expect((changes['belongings'] as List).length, 1);
    });

    test('exportChanges respects since filter', () async {
      final oldTime = DateTime(2020, 1, 1);
      final newTime = DateTime(2025, 1, 1);

      await db.into(db.belongings).insert(
            BelongingsCompanion(
              id: Value(newId()),
              name: const Value('Old Item'),
              createdAt: Value(oldTime),
              updatedAt: Value(oldTime),
            ),
          );
      await db.into(db.belongings).insert(
            BelongingsCompanion(
              id: Value(newId()),
              name: const Value('New Item'),
              createdAt: Value(newTime),
              updatedAt: Value(newTime),
            ),
          );

      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);
      final sync = SyncService(db, provider, 'device-a');

      final cutoff = DateTime(2022, 1, 1);
      final changes = await sync.exportChanges(cutoff);
      final items = changes['belongings'] as List;
      expect(items.length, 1);
      expect((items.first as Map)['name'], 'New Item');
    });

    test('sync uploads without peers', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);
      final sync = SyncService(db, provider, 'device-a');

      final result = await sync.sync();
      // No peers: just uploads.
      expect(result.pushed, 1);
      expect(result.pulled, 0);
      expect(result.hasConflicts, isFalse);
    });

    test('sync pulls new records from another device', () async {
      // Device A creates an item and syncs.
      final storage = <String, String>{};
      final providerA = FileSyncProvider(storage);
      final syncA = SyncService(db, providerA, 'device-a');

      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );
      await syncA.sync();

      // Device B (fresh DB) syncs with device A as peer.
      final dbB = KeepItDatabase(NativeDatabase.memory());
      try {
        final providerB = FileSyncProvider(storage);
        final syncB = SyncService(dbB, providerB, 'device-b');

        final result = await syncB.sync(peerDeviceIds: ['device-a']);
        expect(result.pulled, 1);

        final items = await BelongingRepository(dbB).getAll();
        expect(items.length, 1);
        expect(items.first.name, 'Hammer');
      } finally {
        await dbB.close();
      }
    });

    test('sync detects conflicts when both sides modify', () async {
      final itemId = newId();
      await belongings.create(
        BelongingsCompanion(
          id: Value(itemId),
          name: const Value('Hammer'),
        ),
      );

      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);
      final sync = SyncService(db, provider, 'device-a');

      // Simulate a remote change to the same item from device-b.
      final local = await belongings.getById(itemId);
      final remoteData = {
        'deviceId': 'device-b',
        'exportedAt': DateTime.now().toIso8601String(),
        'belongings': [
          {
            ...local!.toJson(),
            'name': 'Hammer (modified on B)',
            'updatedAt': DateTime.now()
                .add(const Duration(seconds: 1))
                .toIso8601String(),
          },
        ],
      };
      await provider.upload('device-b', remoteData);

      final result = await sync.sync(peerDeviceIds: ['device-b']);
      expect(result.hasConflicts, isTrue);
      expect(result.conflicts.length, 1);
      expect(result.conflicts.first.entityId, itemId);
    });

    test('conflict resolution keepRemote applies remote change', () async {
      final itemId = newId();
      await belongings.create(
        BelongingsCompanion(
          id: Value(itemId),
          name: const Value('Hammer'),
        ),
      );

      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);
      final sync = SyncService(db, provider, 'device-a');

      final local = await belongings.getById(itemId);
      final remoteData = {
        'deviceId': 'device-b',
        'exportedAt': DateTime.now().toIso8601String(),
        'belongings': [
          {
            ...local!.toJson(),
            'name': 'Hammer Pro',
            'updatedAt': DateTime.now()
                .add(const Duration(seconds: 1))
                .toIso8601String(),
          },
        ],
      };
      await provider.upload('device-b', remoteData);

      final result = await sync.sync(peerDeviceIds: ['device-b']);
      expect(result.hasConflicts, isTrue);

      await sync.resolveConflict(
        result.conflicts.first,
        ConflictResolution.keepRemote,
      );

      final updated = await belongings.getById(itemId);
      expect(updated!.name, 'Hammer Pro');
    });

    test('conflict resolution keepLocal preserves local change', () async {
      final itemId = newId();
      await belongings.create(
        BelongingsCompanion(
          id: Value(itemId),
          name: const Value('Hammer'),
        ),
      );

      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);
      final sync = SyncService(db, provider, 'device-a');

      final local = await belongings.getById(itemId);
      final remoteData = {
        'deviceId': 'device-b',
        'exportedAt': DateTime.now().toIso8601String(),
        'belongings': [
          {
            ...local!.toJson(),
            'name': 'Hammer Pro',
            'updatedAt': DateTime.now()
                .add(const Duration(seconds: 1))
                .toIso8601String(),
          },
        ],
      };
      await provider.upload('device-b', remoteData);

      final result = await sync.sync(peerDeviceIds: ['device-b']);
      expect(result.hasConflicts, isTrue);

      await sync.resolveConflict(
        result.conflicts.first,
        ConflictResolution.keepLocal,
      );

      final updated = await belongings.getById(itemId);
      expect(updated!.name, 'Hammer');
    });

    test('FileSyncProvider round-trips data', () async {
      final storage = <String, String>{};
      final provider = FileSyncProvider(storage);

      final data = {'key': 'value', 'number': 42};
      await provider.upload('device-x', data);

      final downloaded = await provider.download('device-x');
      expect(downloaded!['key'], 'value');
      expect(downloaded['number'], 42);

      final lastUpdate = await provider.lastRemoteUpdate('device-x');
      expect(lastUpdate, isNotNull);
    });
  });
}

// Simple ID generator for tests.
String newId() => DateTime.now().microsecondsSinceEpoch.toString();
