import '../../core/database/keepit_database.dart';

/// Helpers over the hierarchical [Location] tree.
class LocationService {
  LocationService(this._db);

  final KeepItDatabase _db;

  /// Breadcrumb path, e.g. "Home > Bedroom > Drawer".
  /// Guards against parent cycles; unknown ids return an empty string.
  Future<String> locationPath(String locationId,
      {String separator = ' > '}) async {
    final names = <String>[];
    final visited = <String>{};
    String? currentId = locationId;

    while (currentId != null && visited.add(currentId)) {
      final id = currentId;
      final location = await (_db.select(_db.locations)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (location == null) break;
      names.insert(0, location.name);
      currentId = location.parentLocationId;
    }
    return names.join(separator);
  }

  /// Every descendant of [locationId] at any depth (not including itself).
  /// Guards against cycles.
  Future<List<Location>> descendants(String locationId) async {
    final result = <Location>[];
    final visited = <String>{locationId};
    var frontier = <String>[locationId];

    while (frontier.isNotEmpty) {
      final children = await (_db.select(_db.locations)
            ..where((t) => t.parentLocationId.isIn(frontier)))
          .get();
      frontier = [];
      for (final child in children) {
        if (visited.add(child.id)) {
          result.add(child);
          frontier.add(child.id);
        }
      }
    }
    return result;
  }

  /// Every belonging stored in [locationId] or any of its descendants.
  Future<List<Belonging>> belongingsInLocationTree(String locationId) async {
    final ids = <String>[locationId];
    for (final child in await descendants(locationId)) {
      ids.add(child.id);
    }
    return (_db.select(_db.belongings)
          ..where((t) => t.locationId.isIn(ids)))
        .get();
  }

  /// True when assigning [parentId] as the parent of [locationId] would
  /// create a cycle (i.e. [parentId] is [locationId] itself or one of its
  /// descendants). Null parent is always safe.
  Future<bool> wouldCreateCycle(String locationId, String? parentId) async {
    if (parentId == null) return false;
    if (parentId == locationId) return true;
    final desc = await descendants(locationId);
    return desc.any((l) => l.id == parentId);
  }
}
