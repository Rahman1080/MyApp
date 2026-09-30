import 'package:drift/drift.dart';

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

  // -----------------------------------------------------------------------
  // Containers (Phase 10): belongings with isContainer = true hold other
  // belongings via belongings.container_id.
  // -----------------------------------------------------------------------

  /// Every belonging stored directly inside [containerId].
  Future<List<Belonging>> containerContents(String containerId) {
    return (_db.select(_db.belongings)
          ..where((t) => t.containerId.equals(containerId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<Belonging>> watchContainerContents(String containerId) {
    return ((_db.select(_db.belongings)
          ..where((t) => t.containerId.equals(containerId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Every belonging nested inside [containerId] at any depth (not including
  /// the container itself). Guards against cycles.
  Future<List<Belonging>> containerDescendants(String containerId) async {
    final result = <Belonging>[];
    final visited = <String>{containerId};
    var frontier = <String>[containerId];

    while (frontier.isNotEmpty) {
      final children = await (_db.select(_db.belongings)
            ..where((t) => t.containerId.isIn(frontier)))
          .get();
      frontier = [];
      for (final child in children) {
        if (visited.add(child.id)) {
          result.add(child);
          if (child.isContainer) frontier.add(child.id);
        }
      }
    }
    return result;
  }

  /// True when placing [belongingId] inside [targetContainerId] would create
  /// a cycle (the target is the item itself or one of its descendants).
  /// A null target (taking the item out) is always safe.
  Future<bool> wouldCreateContainerCycle(
      String belongingId, String? targetContainerId) async {
    if (targetContainerId == null) return false;
    if (targetContainerId == belongingId) return true;
    final desc = await containerDescendants(belongingId);
    return desc.any((b) => b.id == targetContainerId);
  }

  /// The container chain above [belonging], outermost first. Guards against
  /// cycles; unknown ids stop the chain.
  Future<List<Belonging>> containerAncestors(Belonging belonging) async {
    final chain = <Belonging>[];
    final visited = <String>{belonging.id};
    String? currentId = belonging.containerId;

    while (currentId != null && visited.add(currentId)) {
      final id = currentId;
      final container = await (_db.select(_db.belongings)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (container == null) break;
      chain.insert(0, container);
      currentId = container.containerId;
    }
    return chain;
  }

  /// Full "where is it?" path for a belonging, e.g.
  /// "My Home > Garage > Shelf 2 > Box 7". The place comes first, then the
  /// location ancestors, then the container chain (if any).
  Future<String> belongingWherePath(Belonging belonging,
      {String separator = ' > '}) async {
    final parts = <String>[];
    String? locationId = belonging.locationId;
    final containers = await containerAncestors(belonging);
    if (containers.isNotEmpty) {
      // Items inside a container derive their location from the outermost
      // container.
      locationId = containers.first.locationId;
    }
    if (locationId != null) {
      final visited = <String>{};
      String? currentId = locationId;
      String? placeName;
      final names = <String>[];
      while (currentId != null && visited.add(currentId)) {
        final id = currentId;
        final location = await (_db.select(_db.locations)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (location == null) break;
        names.insert(0, location.name);
        if (placeName == null) {
          final place = await (_db.select(_db.places)
                ..where((t) => t.id.equals(location.placeId)))
              .getSingleOrNull();
          placeName = place?.name;
        }
        currentId = location.parentLocationId;
      }
      // The place is looked up from the deepest location; parent changes
      // cascade the place to the whole subtree, so every ancestor shares it.
      if (names.isNotEmpty) {
        parts.addAll(names);
      }
      if (placeName != null) parts.insert(0, placeName);
    }
    for (final container in containers) {
      parts.add(container.name);
    }
    return parts.join(separator);
  }

  /// "What is here?" summary counts for a location: direct sub-locations,
  /// containers stored directly in it, and items stored directly in it
  /// (excluding items inside containers).
  Future<LocationContents> locationContents(String locationId) async {
    final subLocations = await childrenOf(locationId);
    final belongings = await (_db.select(_db.belongings)
          ..where((t) => t.locationId.equals(locationId)))
        .get();
    var containers = 0;
    var items = 0;
    for (final b in belongings) {
      if (b.containerId != null) continue; // lives inside a container
      if (b.isContainer) {
        containers++;
      } else {
        items++;
      }
    }
    return LocationContents(
      subLocationCount: subLocations.length,
      containerCount: containers,
      itemCount: items,
    );
  }

  Future<List<Location>> childrenOf(String parentId) {
    return (_db.select(_db.locations)
          ..where((t) => t.parentLocationId.equals(parentId)))
        .get();
  }
}

/// Direct-content counts for the "What is here?" view.
class LocationContents {
  const LocationContents({
    required this.subLocationCount,
    required this.containerCount,
    required this.itemCount,
  });

  final int subLocationCount;
  final int containerCount;
  final int itemCount;

  int get total => subLocationCount + containerCount + itemCount;
}
