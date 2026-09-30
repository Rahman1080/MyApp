import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/shared/services/location_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  late KeepItDatabase db;
  late LocationService locations;

  setUp(() {
    db = openInMemoryDatabase();
    locations = LocationService(db);
  });

  tearDown(() async {
    await db.close();
  });

  String newId() => const Uuid().v4();

  /// Builds Home -> Bedroom -> Drawer and returns the three ids.
  Future<(String, String, String)> seedThreeLevels() async {
    final homeId = newId();
    final bedroomId = newId();
    final drawerId = newId();
    await db.into(db.locations).insert(
          LocationsCompanion.insert(id: Value(homeId), name: 'Home'),
        );
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            id: Value(bedroomId),
            name: 'Bedroom',
            parentLocationId: Value(homeId),
          ),
        );
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            id: Value(drawerId),
            name: 'Drawer',
            parentLocationId: Value(bedroomId),
          ),
        );
    return (homeId, bedroomId, drawerId);
  }

  test('locationPath builds the breadcrumb', () async {
    final (homeId, _, drawerId) = await seedThreeLevels();
    expect(await locations.locationPath(drawerId), 'Home > Bedroom > Drawer');
    expect(await locations.locationPath(homeId), 'Home');
  });

  test('locationPath supports a custom separator', () async {
    final (_, _, drawerId) = await seedThreeLevels();
    expect(
      await locations.locationPath(drawerId, separator: ' / '),
      'Home / Bedroom / Drawer',
    );
  });

  test('locationPath returns empty for unknown id', () async {
    expect(await locations.locationPath('nope'), isEmpty);
  });

  test('descendants returns every level below', () async {
    final (homeId, bedroomId, drawerId) = await seedThreeLevels();
    final desc = await locations.descendants(homeId);
    expect(desc.map((l) => l.id).toSet(), {bedroomId, drawerId});

    final leafDesc = await locations.descendants(drawerId);
    expect(leafDesc, isEmpty);
  });

  test('belongingsInLocationTree finds nested belongings', () async {
    final (homeId, _, drawerId) = await seedThreeLevels();
    await db.into(db.belongings).insert(
          BelongingsCompanion.insert(
            id: Value(newId()),
            name: 'Passport',
            locationId: Value(drawerId),
          ),
        );
    await db.into(db.belongings).insert(
          BelongingsCompanion.insert(
            id: Value(newId()),
            name: 'Sofa',
            locationId: Value(homeId),
          ),
        );
    await db.into(db.belongings).insert(
          BelongingsCompanion.insert(
            id: Value(newId()),
            name: 'Unplaced item',
          ),
        );

    final inTree = await locations.belongingsInLocationTree(homeId);
    expect(inTree.map((b) => b.name).toSet(), {'Passport', 'Sofa'});
  });

  test('wouldCreateCycle detects direct and indirect cycles', () async {
    final (homeId, bedroomId, drawerId) = await seedThreeLevels();

    // Home cannot move under its own descendant Drawer.
    expect(await locations.wouldCreateCycle(homeId, drawerId), isTrue);
    // A location cannot be its own parent.
    expect(await locations.wouldCreateCycle(homeId, homeId), isTrue);
    // Bedroom under Home is fine (already the case, no new cycle).
    expect(await locations.wouldCreateCycle(bedroomId, homeId), isFalse);
    // Null parent is always safe.
    expect(await locations.wouldCreateCycle(bedroomId, null), isFalse);
  });
}
