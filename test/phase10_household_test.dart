import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/belonging_meta.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_history_repository.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/exceptions.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/core/database/repositories/place_repository.dart';
import 'package:keepit/core/database/tables.dart';
import 'package:keepit/features/locations/presentation/move_destination_sheet.dart';
import 'package:keepit/shared/services/backup_service.dart';
import 'package:keepit/shared/services/location_service.dart';
import 'package:path/path.dart' as p;

/// Phase 10 "Home and Household Inventory" tests: places, the
/// Place -> Room -> Shelf -> Box hierarchy, containers, moves with cycle
/// prevention, the household dashboard, "where is it?" paths, "what is
/// here?" summaries, and backup/restore compatibility.
void main() {
  late KeepItDatabase db;
  late PlaceRepository places;
  late LocationRepository locations;
  late BelongingRepository belongings;
  late LocationService locationService;
  late BelongingHistoryRepository history;

  setUp(() {
    db = openInMemoryDatabase();
    places = PlaceRepository(db);
    locations = LocationRepository(db);
    belongings = BelongingRepository(db);
    locationService = LocationService(db);
    history = BelongingHistoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createPlace(String name) => places.createNamed(name);

  Future<String> createLocation(
    String name, {
    String? id,
    String? parentId,
    String? placeId,
  }) async {
    final locId = id ?? 'loc-$name';
    await locations.create(
      LocationsCompanion(
        id: Value(locId),
        name: Value(name),
        parentLocationId: Value(parentId),
        placeId: placeId == null ? const Value.absent() : Value(placeId),
      ),
    );
    return locId;
  }

  Future<String> createItem(
    String name, {
    String? id,
    String? locationId,
    bool isContainer = false,
    String? containerId,
    bool valueUnknown = false,
    int? valueCents,
  }) async {
    return belongings.create(
      BelongingsCompanion.insert(
        id: id == null ? const Value.absent() : Value(id),
        name: name,
        locationId: Value(locationId),
        isContainer: Value(isContainer),
        containerId: Value(containerId),
        valueUnknown: Value(valueUnknown),
        valueCents: Value(valueCents),
      ),
    );
  }

  group('Places', () {
    test('fresh database seeds the default place', () async {
      final all = await places.getAll();
      expect(all.length, 1);
      expect(all.single.id, defaultPlaceId);
      expect(all.single.name, 'My Home');
    });

    test('createNamed, rename and getAll', () async {
      final id = await createPlace('Storage Unit');
      expect((await places.getById(id))?.name, 'Storage Unit');
      await places.rename(id, 'Off-site Storage');
      expect((await places.getById(id))?.name, 'Off-site Storage');
      final names = (await places.getAll()).map((e) => e.name);
      expect(names, containsAll(['My Home', 'Off-site Storage']));
    });

    test('cannot delete the default place', () async {
      expect(
        () => places.delete(defaultPlaceId),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });

    test('cannot delete a place that still has locations', () async {
      final id = await createPlace('Cabin');
      await createLocation('Porch', placeId: id);
      expect(
        () => places.delete(id),
        throwsA(isA<ReferentialIntegrityException>()),
      );
      // After moving the location away, deletion works.
      await locations.setPlace('loc-Porch', defaultPlaceId);
      await places.delete(id);
      expect(await places.getById(id), isNull);
    });
  });

  group('Location hierarchy and places', () {
    test('child inherits the parent place when none is given', () async {
      final cabin = await createPlace('Cabin');
      final porch = await createLocation('Porch', placeId: cabin);
      final swing = await createLocation('Swing', parentId: porch);
      expect((await locations.getById(swing))?.placeId, cabin);
    });

    test('setPlace moves the whole subtree to the new place', () async {
      final cabin = await createPlace('Cabin');
      final porch = await createLocation('Porch', placeId: cabin);
      final swing = await createLocation('Swing', parentId: porch);
      await locations.setPlace(porch, defaultPlaceId);
      expect((await locations.getById(porch))?.placeId, defaultPlaceId);
      expect((await locations.getById(swing))?.placeId, defaultPlaceId);
    });

    test('setParent rejects hierarchy cycles', () async {
      final home = await createLocation('Home');
      final bedroom = await createLocation('Bedroom', parentId: home);
      final drawer = await createLocation('Drawer', parentId: bedroom);
      expect(
        () => locations.setParent(home, drawer),
        throwsA(isA<ReferentialIntegrityException>()),
      );
      expect(
        () => locations.setParent(bedroom, bedroom),
        throwsA(isA<ReferentialIntegrityException>()),
      );
      // The tree is unchanged.
      expect((await locations.getById(home))?.parentLocationId, isNull);
    });

    test('descendants returns the whole subtree', () async {
      final home = await createLocation('Home');
      final bedroom = await createLocation('Bedroom', parentId: home);
      await createLocation('Drawer', parentId: bedroom);
      await createLocation('Garage', parentId: home);
      final names =
          (await locationService.descendants(home)).map((e) => e.name);
      expect(names, containsAll(['Bedroom', 'Drawer', 'Garage']));
      expect(names.length, 3);
    });
  });

  group('Containers', () {
    test('createContainer marks the belonging as a container', () async {
      final id = await belongings.createContainer(
        BelongingsCompanion.insert(name: 'Blue Folder'),
      );
      final box = await belongings.requireById(id);
      expect(box.isContainer, isTrue);
      expect((await belongings.containers()).map((e) => e.id), contains(id));
    });

    test('moving an item into a container clears its location', () async {
      final shelf = await createLocation('Shelf');
      final box = await createItem('Box', isContainer: true, locationId: shelf);
      final item = await createItem('Book', locationId: shelf);
      await belongings.moveItemsToContainer({item}, box);
      final moved = await belongings.requireById(item);
      expect(moved.containerId, box);
      expect(moved.locationId, isNull);
      expect((await belongings.contentsOf(box)).map((e) => e.id), [item]);
    });

    test('cannot move a container into itself or a descendant', () async {
      final outer = await createItem('Outer', isContainer: true);
      final inner = await createItem('Inner', isContainer: true);
      await belongings.moveItemsToContainer({inner}, outer);
      expect(
        () => belongings.moveItemsToContainer({outer}, outer),
        throwsA(isA<ReferentialIntegrityException>()),
      );
      expect(
        () => belongings.moveItemsToContainer({outer}, inner),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });

    test('cannot move items into a non-container', () async {
      final notBox = await createItem('Book');
      final item = await createItem('Pen');
      expect(
        () => belongings.moveItemsToContainer({item}, notBox),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });

    test('container nesting, ancestors and descendants', () async {
      final outer = await createItem('Crate', isContainer: true);
      final middle = await createItem('Box', isContainer: true);
      final item = await createItem('Cable');
      await belongings.moveItemsToContainer({middle}, outer);
      await belongings.moveItemsToContainer({item}, middle);
      final ancestors =
          (await locationService.containerAncestors(
            await belongings.requireById(item),
          ))
              .map((e) => e.name);
      expect(ancestors, ['Crate', 'Box']);
      final descendants =
          (await locationService.containerDescendants(outer))
              .map((e) => e.name);
      expect(descendants, containsAll(['Box', 'Cable']));
    });

    test('removeFromContainer returns the item to the container location',
        () async {
      final shelf = await createLocation('Shelf');
      final box =
          await createItem('Box', isContainer: true, locationId: shelf);
      final item = await createItem('Book', locationId: shelf);
      await belongings.moveItemsToContainer({item}, box);
      await belongings.removeFromContainer({item});
      final back = await belongings.requireById(item);
      expect(back.containerId, isNull);
      expect(back.locationId, shelf);
    });

    test('emptyContainer moves every content out, box stays', () async {
      final shelf = await createLocation('Shelf');
      final desk = await createLocation('Desk');
      final box =
          await createItem('Box', isContainer: true, locationId: shelf);
      final a = await createItem('A');
      final b = await createItem('B');
      await belongings.moveItemsToContainer({a, b}, box);
      await belongings.emptyContainer(box, locationId: desk);
      expect(await belongings.contentsOf(box), isEmpty);
      expect((await belongings.requireById(a)).locationId, desk);
      expect((await belongings.requireById(b)).locationId, desk);
      expect((await belongings.requireById(box)).isContainer, isTrue);
    });

    test('moves are recorded in item history', () async {
      final shelf = await createLocation('Shelf');
      final box = await createItem('Box', isContainer: true);
      final item = await createItem('Book', locationId: shelf);
      await belongings.moveItemsToContainer({item}, box);
      final entries = await history.historyFor(item);
      expect(
        entries.any((e) => e.eventType == BelongingHistoryEvent.moved),
        isTrue,
      );
    });
  });

  group('Bulk moves', () {
    test('moveItemsToLocation moves many items and clears containers',
        () async {
      final shelf = await createLocation('Shelf');
      final desk = await createLocation('Desk');
      final box = await createItem('Box', isContainer: true);
      final a = await createItem('A', locationId: shelf);
      final b = await createItem('B');
      await belongings.moveItemsToContainer({b}, box);
      await belongings.moveItemsToLocation({a, b}, desk);
      expect((await belongings.requireById(a)).locationId, desk);
      final movedB = await belongings.requireById(b);
      expect(movedB.locationId, desk);
      expect(movedB.containerId, isNull);
    });

    test('single moveToLocation also leaves the container', () async {
      final desk = await createLocation('Desk');
      final box = await createItem('Box', isContainer: true);
      final item = await createItem('Book');
      await belongings.moveItemsToContainer({item}, box);
      await belongings.moveToLocation(item, desk);
      final moved = await belongings.requireById(item);
      expect(moved.locationId, desk);
      expect(moved.containerId, isNull);
    });
  });

  group('Where is it? paths', () {
    test('full path reads Place > Room > Shelf > Box > item', () async {
      final bedroom = await createLocation('Bedroom');
      final drawer = await createLocation('Drawer', parentId: bedroom);
      final folder =
          await createItem('Blue Folder', isContainer: true, locationId: drawer);
      final item = await createItem('Passport');
      await belongings.moveItemsToContainer({item}, folder);
      expect(
        await belongings.wherePath(item),
        'My Home > Bedroom > Drawer > Blue Folder',
      );
    });

    test('path uses the location place, not the default', () async {
      final cabin = await createPlace('Cabin');
      final porch = await createLocation('Porch', placeId: cabin);
      final item = await createItem('Lantern', locationId: porch);
      expect(await belongings.wherePath(item), 'Cabin > Porch');
    });

    test('item with no location and no container has an empty path', () async {
      final item = await createItem('Loose screw');
      expect(await belongings.wherePath(item), '');
    });
  });

  group('What is here? summaries', () {
    test('locationContents counts sub-locations, containers and items',
        () async {
      final garage = await createLocation('Garage');
      await createLocation('Shelf', parentId: garage);
      await createItem('Toolbox', isContainer: true, locationId: garage);
      await createItem('Hammer', locationId: garage);
      final boxed = await createItem('Nails');
      final toolboxId = (await belongings.containers()).single.id;
      await belongings.moveItemsToContainer({boxed}, toolboxId);

      final contents = await locationService.locationContents(garage);
      expect(contents.subLocationCount, 1);
      expect(contents.containerCount, 1);
      // The nails are inside the toolbox, not directly in the garage.
      expect(contents.itemCount, 1);
    });
  });

  group('Household dashboard', () {
    test('counts items, containers, unlocated items and unknown values',
        () async {
      final shelf = await createLocation('Shelf');
      await createItem('Book', locationId: shelf, valueCents: 1299);
      await createItem('Mystery gadget', valueUnknown: true);
      await createItem('Loose cable');
      await createItem('Box', isContainer: true, locationId: shelf);

      expect(await belongings.countItems(), 3);
      expect(await belongings.countContainers(), 1);
      // Mystery gadget and loose cable have no location; the box does.
      expect(await belongings.countWithoutLocation(), 2);
      expect(await belongings.countUnknownValue(), 1);
    });
  });

  group('Backup and restore', () {
    late Directory sandbox;
    late Directory filesRoot;
    late Directory tempRoot;
    late BackupService service;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('keepit-p10-backup');
      filesRoot = Directory(p.join(sandbox.path, 'files'))
        ..createSync(recursive: true);
      tempRoot = Directory(p.join(sandbox.path, 'tmp'))
        ..createSync(recursive: true);
      service = BackupService(db: db, filesRoot: filesRoot, tempRoot: tempRoot);
    });

    tearDown(() async {
      await sandbox.delete(recursive: true);
    });

    Future<KeepItDatabase> restoreIntoFreshDb(File zip) async {
      final db2 = openInMemoryDatabase();
      final service2 =
          BackupService(db: db2, filesRoot: filesRoot, tempRoot: tempRoot);
      await service2.restoreBackup(zip);
      return db2;
    }

    test('backup round-trips places, containers and hierarchy', () async {
      final cabin = await createPlace('Cabin');
      final porch = await createLocation('Porch', placeId: cabin);
      final crate =
          await createItem('Crate', isContainer: true, locationId: porch);
      final item = await createItem('Lantern', locationId: porch);
      await belongings.moveItemsToContainer({item}, crate);

      final zip = await service.createBackup(appVersion: 'test');
      final db2 = await restoreIntoFreshDb(zip);
      addTearDown(db2.close);

      final places2 = PlaceRepository(db2);
      expect(
        (await places2.getAll()).map((e) => e.name),
        containsAll(['My Home', 'Cabin']),
      );
      final belongings2 = BelongingRepository(db2);
      final restoredItem = await belongings2.requireById(item);
      expect(restoredItem.containerId, crate);
      expect(restoredItem.isContainer, isFalse);
      expect((await belongings2.requireById(crate)).isContainer, isTrue);
      final locations2 = LocationRepository(db2);
      expect((await locations2.getById(porch))?.placeId, cabin);

      final archive =
          ZipDecoder().decodeBytes(await zip.readAsBytes());
      expect(
        archive.files.any((f) => f.name == 'tables/places.json'),
        isTrue,
      );
    });

    test('legacy backup without places restores onto the default place',
        () async {
      final shelf = await createLocation('Shelf');
      await createItem('Book', locationId: shelf);

      final zip = await service.createBackup(appVersion: 'test');
      // Strip the places table to simulate a pre-Phase-10 backup.
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final stripped = Archive();
      for (final file in archive.files) {
        if (file.name == 'tables/places.json') continue;
        var bytes = file.content as List<int>;
        if (file.name == 'tables/locations.json') {
          // Locations rows also lose place_id, like a legacy export.
          final legacyLocations =
              (jsonDecode(utf8.decode(bytes)) as List).toList();
          for (final row in legacyLocations) {
            (row as Map<String, dynamic>).remove('place_id');
          }
          bytes = utf8.encode(jsonEncode(legacyLocations));
        }
        stripped.addFile(ArchiveFile(file.name, bytes.length, bytes));
      }
      final legacyZip = File(p.join(tempRoot.path, 'legacy.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(stripped));

      final db2 = await restoreIntoFreshDb(legacyZip);
      addTearDown(db2.close);

      final places2 = PlaceRepository(db2);
      final all = await places2.getAll();
      expect(all.length, 1);
      expect(all.single.id, defaultPlaceId);
      final locations2 = LocationRepository(db2);
      expect((await locations2.getById(shelf))?.placeId, defaultPlaceId);
      final belongings2 = BelongingRepository(db2);
      expect(await belongings2.countItems(), 1);
    });
  });

  group('Move destination sheet', () {
    testWidgets('lists locations and containers, hides excluded ones',
        (tester) async {
      final garage = await createLocation('Garage');
      final toolbox = await createItem('Toolbox', isContainer: true, locationId: garage);
      final nested = await createItem('Small box', isContainer: true);
      await belongings.moveItemsToContainer({nested}, toolbox);

      MoveDestination? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showMoveDestinationSheet(
                    context: context,
                    locationRepository: locations,
                    belongingRepository: belongings,
                    locationService: locationService,
                    placeRepository: places,
                    excludeContainerIds: await containerMoveExclusions(
                      locationService,
                      {toolbox},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Move to…'), findsOneWidget);
      expect(find.text('Garage'), findsOneWidget);
      // Both containers are excluded: the toolbox itself and everything
      // nested inside it.
      expect(find.text('Toolbox'), findsNothing);
      expect(find.text('Small box'), findsNothing);
      expect(picked, isNull);
    });
  });
}
