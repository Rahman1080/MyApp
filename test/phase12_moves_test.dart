import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/core/database/repositories/move_item_repository.dart';
import 'package:keepit/core/database/repositories/move_repository.dart';
import 'package:keepit/core/database/repositories/place_repository.dart';
import 'package:keepit/features/moves/domain/move_service.dart';
import 'package:keepit/shared/services/backup_service.dart';
import 'package:keepit/shared/services/location_service.dart';

KeepItDatabase _openDb() => KeepItDatabase(NativeDatabase.memory());

int _idCounter = 0;
String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

Future<String> _addBelonging(
  BelongingRepository repo, {
  required String name,
  String? locationId,
}) {
  return repo.create(
    BelongingsCompanion.insert(name: name, locationId: Value(locationId)),
  );
}

Future<String> _addLocation(
  LocationRepository repo, {
  required String name,
  required String placeId,
  String? parentLocationId,
}) async {
  final id = _newId();
  await repo.create(
    LocationsCompanion.insert(
      id: Value(id),
      name: name,
      placeId: Value(placeId),
      parentLocationId: Value(parentLocationId),
    ),
  );
  return id;
}

void main() {
  group('Phase 12 Moving Mode', () {
    late KeepItDatabase db;
    late MoveRepository moves;
    late MoveItemRepository moveItems;
    late BelongingRepository belongings;
    late LocationRepository locations;
    late PlaceRepository places;
    late MoveService service;

    setUp(() async {
      db = _openDb();
      moves = MoveRepository(db);
      moveItems = MoveItemRepository(db);
      belongings = BelongingRepository(db);
      locations = LocationRepository(db);
      places = PlaceRepository(db);
      service = MoveService(
        db: db,
        moves: moves,
        moveItems: moveItems,
        belongings: belongings,
        locations: locations,
        locationService: LocationService(db),
      );
      await places.ensureDefaultPlace();
    });

    tearDown(() => db.close());

    test('schema is v9 and moves tables exist', () async {
      expect(db.schemaVersion, 9);
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('moves','move_items')",
          )
          .get();
      expect(tables.map((r) => r.read<String>('name')).toSet(), {
        'moves',
        'move_items',
      });
    });

    test('create move with defaults', () async {
      final id = await moves.createNamed('Move to new apartment');
      final move = await moves.requireById(id);
      expect(move.name, 'Move to new apartment');
      expect(move.status, MoveStatus.planning);
      expect(move.fromPlaceId, isNull);
      expect(move.moveDate, isNull);
    });

    test('move status advances through the flow', () async {
      final id = await moves.createNamed('Test move');
      await moves.advanceStatus(id);
      expect((await moves.requireById(id)).status, MoveStatus.packing);
      await moves.advanceStatus(id);
      expect((await moves.requireById(id)).status, MoveStatus.inTransit);
      await moves.advanceStatus(id);
      expect((await moves.requireById(id)).status, MoveStatus.unpacking);
      await moves.advanceStatus(id);
      final done = await moves.requireById(id);
      expect(done.status, MoveStatus.completed);
      expect(done.completedAt, isNotNull);
      expect(() => moves.advanceStatus(id), throwsStateError);
    });

    test('cancel move from planning', () async {
      final id = await moves.createNamed('Cancelled move');
      await moves.cancel(id);
      expect((await moves.requireById(id)).status, MoveStatus.cancelled);
      expect(() => moves.cancel(id), throwsStateError);
    });

    test('add items to move is idempotent', () async {
      final moveId = await moves.createNamed('Pack up');
      final itemId = await _addBelonging(belongings, name: 'Sofa');
      final first = await moveItems.add(
        moveId: moveId,
        belongingId: itemId,
        boxLabel: 'Box 1',
      );
      final second = await moveItems.add(
        moveId: moveId,
        belongingId: itemId,
        boxLabel: 'Box 2',
      );
      expect(first, second);
      final items = await moveItems.forMove(moveId);
      expect(items, hasLength(1));
      // First box label wins on duplicate add.
      expect(items.first.boxLabel, 'Box 1');
    });

    test('move item status flow is forward-only', () async {
      final moveId = await moves.createNamed('Pack up');
      final itemId = await _addBelonging(belongings, name: 'Lamp');
      final rowId = await moveItems.add(moveId: moveId, belongingId: itemId);
      expect(
        (await moveItems.requireById(rowId)).status,
        MoveItemStatus.toPack,
      );
      // Cannot skip ahead.
      expect(
        () => moveItems.setStatus(rowId, MoveItemStatus.inTransit),
        throwsStateError,
      );
      await moveItems.advance(rowId);
      expect(
        (await moveItems.requireById(rowId)).status,
        MoveItemStatus.packed,
      );
      await moveItems.setStatus(rowId, MoveItemStatus.inTransit);
      await moveItems.setStatus(rowId, MoveItemStatus.delivered);
      await moveItems.setStatus(rowId, MoveItemStatus.unpacked);
      expect(
        (await moveItems.requireById(rowId)).status,
        MoveItemStatus.unpacked,
      );
      // Terminal: advance is a no-op.
      await moveItems.advance(rowId);
      expect(
        (await moveItems.requireById(rowId)).status,
        MoveItemStatus.unpacked,
      );
    });

    test('bulk status update skips illegal transitions', () async {
      final moveId = await moves.createNamed('Bulk');
      final a = await _addBelonging(belongings, name: 'A');
      final b = await _addBelonging(belongings, name: 'B');
      final idA = await moveItems.add(moveId: moveId, belongingId: a);
      final idB = await moveItems.add(moveId: moveId, belongingId: b);
      await moveItems.advance(idB); // B is now packed
      final updated = await moveItems.setStatusBulk([
        idA,
        idB,
      ], MoveItemStatus.packed);
      // A: to_pack -> packed is legal. B: packed -> packed is a no-op legal.
      expect(updated, 2);
      final skipped = await moveItems.setStatusBulk([
        idA,
      ], MoveItemStatus.delivered);
      // A cannot jump packed -> delivered.
      expect(skipped, 0);
    });

    test('packBox marks every item in a box as packed', () async {
      final moveId = await moves.createNamed('Boxes');
      final a = await _addBelonging(belongings, name: 'Book 1');
      final b = await _addBelonging(belongings, name: 'Book 2');
      final c = await _addBelonging(belongings, name: 'Vase');
      await moveItems.add(moveId: moveId, belongingId: a, boxLabel: 'Box 1');
      await moveItems.add(moveId: moveId, belongingId: b, boxLabel: 'Box 1');
      await moveItems.add(moveId: moveId, belongingId: c, boxLabel: 'Box 2');
      final packed = await service.packBox(moveId, 'Box 1');
      expect(packed, 2);
      final counts = await moveItems.countsByStatus(moveId);
      expect(counts[MoveItemStatus.packed], 2);
      expect(counts[MoveItemStatus.toPack], 1);
      expect(await moveItems.boxLabels(moveId), ['Box 1', 'Box 2']);
    });

    test('addPlaceContents adds owned items from a place', () async {
      final place = await places.ensureDefaultPlace();
      final locId = await _addLocation(
        locations,
        name: 'Living room',
        placeId: place.id,
      );
      final archived = await _addLocation(
        locations,
        name: 'Garage',
        placeId: place.id,
      );
      final keep = await _addBelonging(
        belongings,
        name: 'TV',
        locationId: locId,
      );
      final skip = await _addBelonging(
        belongings,
        name: 'Old bike',
        locationId: archived,
      );
      await belongings.update(
        skip,
        BelongingsCompanion(archiveState: const Value('archived')),
      );
      final moveId = await moves.createNamed('Move out');
      final added = await service.addPlaceContents(moveId, place.id);
      expect(added, 1);
      final items = await moveItems.forMove(moveId);
      expect(items.map((i) => i.belongingId), contains(keep));
    });

    test('addLocationContents includes subtree', () async {
      final place = await places.ensureDefaultPlace();
      final kitchen = await _addLocation(
        locations,
        name: 'Kitchen',
        placeId: place.id,
      );
      final pantry = await _addLocation(
        locations,
        name: 'Pantry',
        placeId: place.id,
        parentLocationId: kitchen,
      );
      final a = await _addBelonging(
        belongings,
        name: 'Fridge',
        locationId: kitchen,
      );
      final b = await _addBelonging(
        belongings,
        name: 'Cereal',
        locationId: pantry,
      );
      final moveId = await moves.createNamed('Kitchen move');
      final added = await service.addLocationContents(moveId, kitchen);
      expect(added, 2);
      final items = await moveItems.forMove(moveId);
      expect(items.map((i) => i.belongingId).toSet(), {a, b});
    });

    test('completeMove re-homes delivered items', () async {
      final place = await places.ensureDefaultPlace();
      final oldLoc = await _addLocation(
        locations,
        name: 'Old place',
        placeId: place.id,
      );
      final newLoc = await _addLocation(
        locations,
        name: 'New place',
        placeId: place.id,
      );
      final tv = await _addBelonging(
        belongings,
        name: 'TV',
        locationId: oldLoc,
      );
      final lamp = await _addBelonging(
        belongings,
        name: 'Lamp',
        locationId: oldLoc,
      );
      final moveId = await moves.createNamed('Big move');
      final tvRow = await moveItems.add(moveId: moveId, belongingId: tv);
      await moveItems.add(moveId: moveId, belongingId: lamp);
      // TV travels the full flow; lamp is still to_pack.
      await moveItems.setStatus(tvRow, MoveItemStatus.packed);
      await moveItems.setStatus(tvRow, MoveItemStatus.inTransit);
      await moveItems.setStatus(tvRow, MoveItemStatus.delivered);

      await service.completeMove(moveId, destinationLocationId: newLoc);

      final tvAfter = await belongings.getById(tv);
      expect(tvAfter!.locationId, newLoc);
      final lampAfter = await belongings.getById(lamp);
      // Not delivered yet: stays where it was.
      expect(lampAfter!.locationId, oldLoc);
      final tvMoveRow = await moveItems.requireById(tvRow);
      expect(tvMoveRow.status, MoveItemStatus.unpacked);
      final move = await moves.requireById(moveId);
      expect(move.status, MoveStatus.completed);
    });

    test('progress snapshot aggregates statuses', () async {
      final moveId = await moves.createNamed('Progress');
      final a = await _addBelonging(belongings, name: 'A');
      final b = await _addBelonging(belongings, name: 'B');
      final idA = await moveItems.add(
        moveId: moveId,
        belongingId: a,
        boxLabel: 'X',
      );
      await moveItems.add(moveId: moveId, belongingId: b);
      await moveItems.advance(idA);
      final progress = await service.progress(moveId);
      expect(progress.total, 2);
      expect(progress.packed, 1);
      expect(progress.packedFraction, 0.5);
      expect(progress.boxCount, 1);
    });

    test('deleting a move cascades to move items', () async {
      final moveId = await moves.createNamed('Ephemeral');
      final a = await _addBelonging(belongings, name: 'Chair');
      await moveItems.add(moveId: moveId, belongingId: a);
      await moves.delete(moveId);
      expect(await moveItems.forMove(moveId), isEmpty);
    });

    test('backup round-trips moves and move items', () async {
      final moveId = await moves.createNamed('Backup move');
      final a = await _addBelonging(belongings, name: 'Desk');
      final rowId = await moveItems.add(
        moveId: moveId,
        belongingId: a,
        boxLabel: 'Box 9',
      );
      await moveItems.advance(rowId);

      final tempDir = await Directory.systemTemp.createTemp('keepit-p12-bak');
      addTearDown(() => tempDir.delete(recursive: true));
      final backupService = BackupService(
        db: db,
        filesRoot: tempDir,
        tempRoot: tempDir,
      );
      final zip = await backupService.createBackup(appVersion: 'phase12-test');

      final db2 = _openDb();
      addTearDown(db2.close);
      final restoreService = BackupService(
        db: db2,
        filesRoot: tempDir,
        tempRoot: tempDir,
      );
      await restoreService.restoreBackup(zip);

      final restoredMoves = await MoveRepository(db2).getAll();
      expect(restoredMoves.map((m) => m.name), contains('Backup move'));
      final restoredMove = restoredMoves.firstWhere(
        (m) => m.name == 'Backup move',
      );
      final restoredItems = await MoveItemRepository(
        db2,
      ).forMove(restoredMove.id);
      expect(restoredItems, hasLength(1));
      expect(restoredItems.first.boxLabel, 'Box 9');
      expect(restoredItems.first.status, MoveItemStatus.packed);
    });
  });
}
