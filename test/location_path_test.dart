import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/features/belongings/presentation/widgets/location_path.dart';

/// Unit tests for the location path helpers used by the My Stuff tab,
/// the locations browser and "where is it?" search.
void main() {
  Location makeLocation(String id, String name, [String? parentId]) {
    final now = DateTime(2026, 1, 1);
    return Location(
      id: id,
      name: name,
      parentLocationId: parentId,
      placeId: 'place-default',
      notes: null,
      photoPath: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('buildLocationPaths', () {
    test('builds root-to-leaf breadcrumbs', () {
      final locations = [
        makeLocation('home', 'Home'),
        makeLocation('bed', 'Bedroom', 'home'),
        makeLocation('drawer', 'Drawer', 'bed'),
      ];
      final paths = buildLocationPaths(locations);
      expect(paths['home'], 'Home');
      expect(paths['bed'], 'Home > Bedroom');
      expect(paths['drawer'], 'Home > Bedroom > Drawer');
    });

    test('unknown parent stops the chain instead of crashing', () {
      final locations = [makeLocation('x', 'Drawer', 'missing')];
      expect(buildLocationPaths(locations)['x'], 'Drawer');
    });

    test('cycles terminate', () {
      final locations = [
        makeLocation('a', 'A', 'b'),
        makeLocation('b', 'B', 'a'),
      ];
      final paths = buildLocationPaths(locations);
      // Either rendering order is acceptable as long as it terminates and
      // contains both names exactly once.
      expect(paths['a']!.split(' > ').toSet(), {'A', 'B'});
      expect(paths['b']!.split(' > ').toSet(), {'A', 'B'});
    });

    test('empty input yields an empty map', () {
      expect(buildLocationPaths(const []), isEmpty);
    });
  });

  group('flattenLocationTree', () {
    test('flattens depth-first with depths', () {
      final locations = [
        makeLocation('home', 'Home'),
        makeLocation('bed', 'Bedroom', 'home'),
        makeLocation('drawer', 'Drawer', 'bed'),
        makeLocation('kitchen', 'Kitchen', 'home'),
      ];
      final flat = flattenLocationTree(locations);
      expect(
        flat.map((e) => (e.location.id, e.depth)).toList(),
        [
          ('home', 0),
          ('bed', 1),
          ('drawer', 2),
          ('kitchen', 1),
        ],
      );
    });

    test('cycles do not cause infinite recursion', () {
      final locations = [
        makeLocation('a', 'A', 'b'),
        makeLocation('b', 'B', 'a'),
      ];
      final flat = flattenLocationTree(locations);
      // Neither is a root, so the forest is empty — but it must terminate.
      expect(flat, isEmpty);
    });
  });
}
