import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/belonging_meta.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/tables.dart' show newRecordId;
import 'package:keepit/core/database/repositories/belonging_history_repository.dart';
import 'package:keepit/core/database/repositories/belonging_photo_repository.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/category_repository.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/core/database/repositories/tag_repository.dart';
import 'package:keepit/shared/services/backup_service.dart';
import 'package:keepit/shared/services/global_search.dart';
import 'package:path/path.dart' as p;

/// Phase 9 — Advanced Personal Property System:
/// richer item fields, archive states, purchase links, tags, photos,
/// item history, extended search, and backup/restore compatibility.
void main() {
  late KeepItDatabase db;
  late BelongingRepository belongings;
  late BelongingPhotoRepository photos;
  late BelongingHistoryRepository history;
  late TagRepository tags;
  late PurchaseRepository purchases;
  late LocationRepository locations;
  late CategoryRepository categories;

  setUp(() {
    db = openInMemoryDatabase();
    belongings = BelongingRepository(db);
    photos = BelongingPhotoRepository(db);
    history = BelongingHistoryRepository(db);
    tags = TagRepository(db);
    purchases = PurchaseRepository(db);
    locations = LocationRepository(db);
    categories = CategoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createPurchase(String id, String name) async {
    await purchases.create(
      PurchasesCompanion.insert(
        id: Value(id),
        productName: name,
      ),
    );
    return id;
  }

  Future<String> createLocation(String id, String name) async {
    await locations.create(
      LocationsCompanion.insert(id: Value(id), name: name),
    );
    return id;
  }

  group('item fields', () {
    test('create stores all Phase 9 fields and round-trips', () async {
      final purchaseId = await createPurchase('p1', 'Laptop Pro 14');
      final id = await belongings.create(
        BelongingsCompanion.insert(
          name: 'Laptop',
          brand: const Value('Acme'),
          model: const Value('Pro 14'),
          serialNumber: const Value('SN-001'),
          purchaseId: Value(purchaseId),
          quantity: const Value(2),
          valueCents: const Value(129900),
          currencyCode: const Value('USD'),
          valueUnknown: const Value(false),
          condition: const Value(BelongingCondition.likeNew),
          archiveState: const Value(BelongingArchiveState.owned),
          notes: const Value('Work machine'),
        ),
      );

      final item = await belongings.getById(id);
      expect(item, isNotNull);
      expect(item!.name, 'Laptop');
      expect(item.brand, 'Acme');
      expect(item.model, 'Pro 14');
      expect(item.serialNumber, 'SN-001');
      expect(item.purchaseId, purchaseId);
      expect(item.quantity, 2);
      expect(item.valueCents, 129900);
      expect(item.currencyCode, 'USD');
      expect(item.valueUnknown, isFalse);
      expect(item.condition, BelongingCondition.likeNew);
      expect(item.archiveState, BelongingArchiveState.owned);
      expect(item.archivedAt, isNull);
      expect(item.notes, 'Work machine');

      // JSON round-trip (used by backup/restore) carries the new fields.
      final restored = Belonging.fromJson(item.toJson());
      expect(restored.model, 'Pro 14');
      expect(restored.serialNumber, 'SN-001');
      expect(restored.purchaseId, purchaseId);
      expect(restored.valueUnknown, isFalse);
      expect(restored.condition, BelongingCondition.likeNew);
      expect(restored.archiveState, BelongingArchiveState.owned);
    });

    test('minimal create applies sensible defaults', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Mug'),
      );
      final item = await belongings.getById(id);
      expect(item!.archiveState, BelongingArchiveState.owned);
      expect(item.valueUnknown, isFalse);
      expect(item.quantity, 1);
      expect(item.model, isNull);
      expect(item.serialNumber, isNull);
      expect(item.purchaseId, isNull);
      expect(item.condition, isNull);
      expect(item.valueCents, isNull);
    });

    test('unknown value is stored distinctly from zero', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(
          name: 'Heirloom',
          valueUnknown: const Value(true),
        ),
      );
      final item = await belongings.getById(id);
      expect(item!.valueUnknown, isTrue);
      expect(item.valueCents, isNull);
    });
  });

  group('archive states', () {
    test('setArchiveState transitions and stamps archivedAt', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Bike'),
      );

      await belongings.setArchiveState(id, BelongingArchiveState.sold);
      var item = await belongings.getById(id);
      expect(item!.archiveState, BelongingArchiveState.sold);
      expect(item.archivedAt, isNotNull);

      // Restoring clears the timestamp.
      await belongings.setArchiveState(id, BelongingArchiveState.owned);
      item = await belongings.getById(id);
      expect(item!.archiveState, BelongingArchiveState.owned);
      expect(item.archivedAt, isNull);
    });

    test('watchByArchiveStates filters by state', () async {
      final ownedId = await belongings.create(
        BelongingsCompanion.insert(name: 'Owned thing'),
      );
      final soldId = await belongings.create(
        BelongingsCompanion.insert(name: 'Sold thing'),
      );
      await belongings.setArchiveState(soldId, BelongingArchiveState.sold);

      final owned =
          await belongings.watchByArchiveStates(['owned']).first;
      expect(owned.map((b) => b.id), contains(ownedId));
      expect(owned.map((b) => b.id), isNot(contains(soldId)));

      final sold = await belongings
          .watchByArchiveStates([BelongingArchiveState.sold]).first;
      expect(sold.map((b) => b.id), contains(soldId));

      final all = await belongings
          .watchByArchiveStates(BelongingArchiveState.all).first;
      expect(all.length, 2);
    });

    test('archiving logs a history entry', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Chair'),
      );
      await belongings.setArchiveState(id, BelongingArchiveState.archived);

      final entries = await history.historyFor(id);
      expect(
        entries.any((e) =>
            e.eventType == BelongingHistoryEvent.archived &&
            e.title.contains('Archived')),
        isTrue,
      );

      await belongings.setArchiveState(id, BelongingArchiveState.sold);
      final entries2 = await history.historyFor(id);
      expect(
        entries2.any((e) =>
            e.eventType == BelongingHistoryEvent.sold &&
            e.title.contains('sold')),
        isTrue,
      );
    });
  });

  group('purchase links', () {
    test('linkPurchase links and unlinks with history', () async {
      final purchaseId = await createPurchase('p9', 'Headphones');
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Headphones'),
      );

      await belongings.linkPurchase(id, purchaseId);
      var item = await belongings.getById(id);
      expect(item!.purchaseId, purchaseId);

      var entries = await history.historyFor(id);
      expect(
        entries.any((e) =>
            e.eventType == BelongingHistoryEvent.purchased),
        isTrue,
      );

      await belongings.linkPurchase(id, null);
      item = await belongings.getById(id);
      expect(item!.purchaseId, isNull);
    });

    test('byPurchaseId returns linked items (reverse navigation)', () async {
      final purchaseId = await createPurchase('p2', 'Camera kit');
      final linked = await belongings.create(
        BelongingsCompanion.insert(name: 'Camera', purchaseId: Value(purchaseId)),
      );
      await belongings.create(BelongingsCompanion.insert(name: 'Unrelated'));

      final items = await belongings.byPurchaseId(purchaseId);
      expect(items.map((b) => b.id), contains(linked));
      expect(items.length, 1);
    });

    test('deleting a purchase clears the link instead of the item',
        () async {
      final purchaseId = await createPurchase('p3', 'Drill');
      final id = await belongings.create(
        BelongingsCompanion.insert(
            name: 'Drill', purchaseId: Value(purchaseId)),
      );

      await purchases.delete(purchaseId);

      final item = await belongings.getById(id);
      expect(item, isNotNull, reason: 'item must survive purchase deletion');
      expect(item!.purchaseId, isNull, reason: 'link cleared via SET NULL');
    });
  });

  group('quantity and movement', () {
    test('moveToLocation updates the location and logs history', () async {
      final drawer = await createLocation('l1', 'Drawer');
      final shelf = await createLocation('l2', 'Shelf');
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Passport', locationId: Value(drawer)),
      );

      await belongings.moveToLocation(id, shelf,
          fromName: 'Drawer', toName: 'Shelf');

      final item = await belongings.getById(id);
      expect(item!.locationId, shelf);

      final entries = await history.historyFor(id);
      final moved = entries
          .where((e) => e.eventType == BelongingHistoryEvent.moved);
      expect(moved, isNotEmpty);
      expect(moved.first.title, contains('Shelf'));
    });

    test('moveToLocation to the same location is a no-op', () async {
      final drawer = await createLocation('l1', 'Drawer');
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Keys', locationId: Value(drawer)),
      );
      final before = await history.historyFor(id);

      await belongings.moveToLocation(id, drawer);

      final after = await history.historyFor(id);
      expect(after.length, before.length);
    });
  });

  group('photos', () {
    test('add, list in order, and delete', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Vase'),
      );

      final first = await photos.add(
          belongingId: id, filePath: '/tmp/a.jpg', caption: 'Front');
      await photos.add(belongingId: id, filePath: '/tmp/b.jpg');

      var list = await photos.photosFor(id);
      expect(list.length, 2);
      expect(list.first.id, first);
      expect(list.first.caption, 'Front');

      await photos.delete(first);
      list = await photos.photosFor(id);
      expect(list.length, 1);
      expect(list.single.filePath, '/tmp/b.jpg');
    });

    test('adding a photo logs a history entry', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Lamp'),
      );
      await photos.add(belongingId: id, filePath: '/tmp/lamp.jpg');

      final entries = await history.historyFor(id);
      expect(
        entries.any(
            (e) => e.eventType == BelongingHistoryEvent.photoAdded),
        isTrue,
      );
    });

    test('deleting a belonging removes its photos and history', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Old radio'),
      );
      await photos.add(belongingId: id, filePath: '/tmp/radio.jpg');

      await belongings.delete(id);

      expect(await photos.photosFor(id), isEmpty);
      expect(await history.historyFor(id), isEmpty);
      expect(await belongings.getById(id), isNull);
    });
  });

  group('history', () {
    test('create logs an automatic "added" entry', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Book'),
      );
      final entries = await history.historyFor(id);
      expect(entries.length, 1);
      expect(entries.single.eventType, BelongingHistoryEvent.created);
    });

    test('manual notes can be appended and read newest-first', () async {      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Guitar'),
      );
      await history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.note,
        title: 'Changed strings',
        details: 'Put on Elixirs, sounds great.',
      );

      final entries = await history.historyFor(id);
      expect(entries.length, 2);
      // Newest first: the manual note comes before the "added" entry.
      expect(entries.first.eventType, BelongingHistoryEvent.note);
      expect(entries.first.details, contains('Elixirs'));
      expect(entries.last.eventType, BelongingHistoryEvent.created);
    });

    test('maintenance entries are stored with their own event type', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Bike'),
      );
      await history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.maintenance,
        title: 'Oiled the chain',
      );

      final entries = await history.historyFor(id);
      final maintenance = entries.where(
          (e) => e.eventType == BelongingHistoryEvent.maintenance);
      expect(maintenance, hasLength(1));
      expect(maintenance.single.title, 'Oiled the chain');
    });

    test('watchFor streams updates', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Watch'),
      );
      final stream = history.watchFor(id);
      // The create already logged one entry.
      expect(await stream.first, hasLength(1));

      await history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.note,
        title: 'Serviced',
      );
      expect(await stream.first, hasLength(2));
    });
  });

  group('tags on belongings', () {
    test('custom categories can be created and assigned to items', () async {
      final before = await categories.getAll();
      final id = newRecordId();
      await categories.create(
        CategoriesCompanion.insert(id: Value(id), name: 'Instruments'),
      );
      final after = await categories.getAll();
      expect(after.length, before.length + 1);
      expect(after.map((c) => c.name), contains('Instruments'));

      final itemId = await belongings.create(
        BelongingsCompanion.insert(
            name: 'Guitar', categoryId: Value(id)),
      );
      final item = await belongings.getById(itemId);
      expect(item!.categoryId, id);
    });

    test('tags can be linked to a belonging', () async {
      final id = await belongings.create(
        BelongingsCompanion.insert(name: 'Tent'),
      );
      final tag = await tags.getOrCreate('Camping');
      await tags.link(
          tagId: tag.id, entityType: 'belonging', entityId: id);

      final linked = await tags.tagsForEntity(
          entityType: 'belonging', entityId: id);
      expect(linked.map((t) => t.name), contains('Camping'));
    });
  });

  group('global search', () {
    test('finds belongings by model, serial, notes, location and tags',
        () async {
      final garage = await createLocation('lg', 'Garage');
      await categories.create(
        CategoriesCompanion.insert(name: 'Electronics'),
      );
      final cats = await categories.getAll();
      final electronicsId = cats.single.id;

      final drillId = await belongings.create(
        BelongingsCompanion.insert(
          name: 'Drill',
          brand: const Value('Acme'),
          model: const Value('X200'),
          serialNumber: const Value('SN-98765'),
          notes: const Value('Heavy duty hammer drill'),
          locationId: Value(garage),
          categoryId: Value(electronicsId),
        ),
      );
      final tag = await tags.getOrCreate('Workshop');
      await tags.link(
          tagId: tag.id, entityType: 'belonging', entityId: drillId);
      await belongings.create(BelongingsCompanion.insert(name: 'Unrelated'));

      final service = GlobalSearchService(db);

      Future<List<String>> idsFor(String query) async {
        final results = await service.search(query);
        return [for (final b in results.belongings) b.id];
      }

      expect(await idsFor('X200'), contains(drillId));
      expect(await idsFor('SN-98765'), contains(drillId));
      expect(await idsFor('hammer drill'), contains(drillId));
      expect(await idsFor('Garage'), contains(drillId));
      expect(await idsFor('Electronics'), contains(drillId));
      expect(await idsFor('Workshop'), contains(drillId));
      // The unrelated item never matches these queries.
      expect(await idsFor('X200'), isNot(contains('unrelated')));
    });

    test('exact name match ranks before partial matches', () async {
      final exactId = await belongings.create(
        BelongingsCompanion.insert(name: 'Drill'),
      );
      final partialId = await belongings.create(
        BelongingsCompanion.insert(name: 'Cordless drill driver kit'),
      );

      final results = await GlobalSearchService(db).search('Drill');
      final ids = [for (final b in results.belongings) b.id];
      expect(ids, containsAll([exactId, partialId]));
      expect(ids.indexOf(exactId), lessThan(ids.indexOf(partialId)));
    });
  });

  group('backup and restore', () {
    late Directory filesRoot;
    late Directory tempRoot;

    setUp(() async {
      filesRoot = await Directory.systemTemp.createTemp('keepit-backup-test');
      tempRoot = Directory(p.join(filesRoot.path, 'tmp'))
        ..createSync(recursive: true);
    });

    tearDown(() async {
      if (await filesRoot.exists()) {
        await filesRoot.delete(recursive: true);
      }
    });

    BackupService serviceFor(KeepItDatabase database) => BackupService(
          db: database,
          filesRoot: filesRoot,
          tempRoot: tempRoot,
        );

    test('round-trips photos, history and new fields', () async {
      final purchaseId = await createPurchase('pb', 'Bike');
      final itemId = await belongings.create(
        BelongingsCompanion.insert(
          name: 'Bike',
          model: const Value('Trail 5'),
          serialNumber: const Value('BIKE-1'),
          purchaseId: Value(purchaseId),
          valueUnknown: const Value(true),
          condition: const Value(BelongingCondition.good),
          archiveState: const Value(BelongingArchiveState.owned),
        ),
      );
      await photos.add(
          belongingId: itemId, filePath: '/tmp/bike.jpg', caption: 'Side');
      await history.log(
        belongingId: itemId,
        eventType: BelongingHistoryEvent.note,
        title: 'Tuned gears',
      );

      final zip = await serviceFor(db).createBackup(appVersion: 'phase9-test');

      // Restore into a fresh database.
      final db2 = openInMemoryDatabase();
      addTearDown(db2.close);
      await serviceFor(db2).restoreBackup(zip);

      final restored =
          await BelongingRepository(db2).getById(itemId);
      expect(restored, isNotNull);
      expect(restored!.model, 'Trail 5');
      expect(restored.serialNumber, 'BIKE-1');
      expect(restored.purchaseId, purchaseId);
      expect(restored.valueUnknown, isTrue);
      expect(restored.condition, BelongingCondition.good);

      final restoredPhotos =
          await BelongingPhotoRepository(db2).photosFor(itemId);
      expect(restoredPhotos.length, 1);
      expect(restoredPhotos.single.caption, 'Side');

      final restoredHistory =
          await BelongingHistoryRepository(db2).historyFor(itemId);
      expect(
        restoredHistory.any((e) => e.title == 'Tuned gears'),
        isTrue,
      );
      // The automatic "purchased" entry (creation with a purchase link)
      // survived too.
      expect(
        restoredHistory.any(
            (e) => e.eventType == BelongingHistoryEvent.purchased),
        isTrue,
      );
    });

    test('legacy backup without photos/history tables still restores',
        () async {
      final itemId = await belongings.create(
        BelongingsCompanion.insert(name: 'Legacy item'),
      );

      final zip = await serviceFor(db).createBackup(appVersion: 'phase9-test');

      // Strip the two Phase 9 table files to mimic a pre-Phase-9 backup.
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final legacy = Archive();
      for (final file in archive.files) {
        if (file.name == 'tables/belonging_photos.json' ||
            file.name == 'tables/belonging_history.json') {
          continue;
        }
        legacy.addFile(file);
      }
      final legacyZip = File(p.join(filesRoot.path, 'legacy.zip'));
      await legacyZip.writeAsBytes(ZipEncoder().encode(legacy));

      final db2 = openInMemoryDatabase();
      addTearDown(db2.close);
      // Must not throw.
      await serviceFor(db2).restoreBackup(legacyZip);

      final restored = await BelongingRepository(db2).getById(itemId);
      expect(restored, isNotNull);
      expect(restored!.name, 'Legacy item');
      expect(
          await BelongingPhotoRepository(db2).photosFor(itemId), isEmpty);
      expect(
          await BelongingHistoryRepository(db2).historyFor(itemId), isEmpty);
    });

    test('backup manifest counts include the new tables', () async {
      final itemId = await belongings.create(
        BelongingsCompanion.insert(name: 'Counted'),
      );
      await photos.add(belongingId: itemId, filePath: '/tmp/c.jpg');

      final zip = await serviceFor(db).createBackup(appVersion: 'phase9-test');
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final manifestFile =
          archive.files.singleWhere((f) => f.name == 'manifest.json');
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
      final counts = manifest['counts'] as Map<String, dynamic>;
      expect(counts['belonging_photos'], 1);
      expect(counts['belonging_history'], greaterThanOrEqualTo(1));
    });
  });
}
