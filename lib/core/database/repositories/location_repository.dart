import 'package:drift/drift.dart';

import '../../../shared/services/location_service.dart';
import '../keepit_database.dart';
import 'exceptions.dart';

/// Hierarchical locations: Home -> Bedroom -> Drawer -> Folder.
///
/// Phase 10: every location belongs to a [Place] (`place_id`, defaulting
/// to the default place). Deleting a parent sets children's
/// parentLocationId to NULL (schema-level ON DELETE SET NULL). Parent
/// changes go through [setParent], which prevents cycles and keeps the
/// whole subtree in the new parent's place.
class LocationRepository {
  LocationRepository(this._db) : _service = LocationService(_db);

  final KeepItDatabase _db;
  final LocationService _service;

  Future<Location?> getById(String id) {
    return (_db.select(_db.locations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Location> requireById(String id) async {
    final location = await getById(id);
    if (location == null) throw RecordNotFoundException('Location', id);
    return location;
  }

  Future<List<Location>> getAll() {
    return (_db.select(_db.locations)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<Location>> watchAll() {
    return ((_db.select(_db.locations)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Top-level locations (no parent).
  Stream<List<Location>> watchRoots() {
    return ((_db.select(_db.locations)
          ..where((t) => t.parentLocationId.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Top-level locations inside one place.
  Stream<List<Location>> watchRootsInPlace(String placeId) {
    return ((_db.select(_db.locations)
          ..where(
            (t) =>
                t.parentLocationId.isNull() & t.placeId.equals(placeId),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Every location inside one place (flat, ordered by name).
  Stream<List<Location>> watchByPlace(String placeId) {
    return ((_db.select(_db.locations)
          ..where((t) => t.placeId.equals(placeId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  Future<List<Location>> byPlace(String placeId) {
    return (_db.select(_db.locations)
          ..where((t) => t.placeId.equals(placeId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<Location>> watchChildren(String parentId) {
    return ((_db.select(_db.locations)
          ..where((t) => t.parentLocationId.equals(parentId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  Future<List<Location>> childrenOf(String parentId) {
    return (_db.select(_db.locations)
          ..where((t) => t.parentLocationId.equals(parentId)))
        .get();
  }

  Future<List<Location>> searchByName(String query) {
    return (_db.select(_db.locations)..where((t) => t.name.contains(query)))
        .get();
  }

  Future<void> create(LocationsCompanion companion) async {
    var toInsert = companion;
    // Inherit the parent's place when none was given explicitly, so a
    // sub-location created under "Garage" (Storage Unit place) does not
    // silently land in the default place.
    if (!companion.placeId.present && companion.parentLocationId.present) {
      final parentId = companion.parentLocationId.value;
      if (parentId != null) {
        final parent = await getById(parentId);
        if (parent != null) {
          toInsert = companion.copyWith(placeId: Value(parent.placeId));
        }
      }
    }
    await guardConstraints(
      () => _db.into(_db.locations).insert(toInsert),
      entity: 'Location',
    );
  }

  Future<void> update(String id, LocationsCompanion companion) async {
    final existing = await requireById(id);
    var toWrite = companion;
    // Parent changes go through the cycle-guarded path so a direct update
    // can never create a hierarchy cycle.
    if (companion.parentLocationId.present &&
        companion.parentLocationId.value != existing.parentLocationId) {
      await _applyParentChange(id, companion.parentLocationId.value);
      toWrite = companion.copyWith(
        parentLocationId: const Value.absent(),
        placeId: const Value.absent(),
      );
    }
    await guardConstraints(
      () => (_db.update(_db.locations)..where((t) => t.id.equals(id))).write(
        toWrite.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Location',
    );
  }

  /// Moves [id] under [newParentId] (null = top level). Throws
  /// [ReferentialIntegrityException] when the move would create a cycle.
  /// The location — and its whole subtree — adopts the new parent's place
  /// (or keeps its place when moved to the top level).
  Future<void> setParent(String id, String? newParentId) async {
    final existing = await requireById(id);
    if (newParentId == existing.parentLocationId) return;
    await _applyParentChange(id, newParentId);
  }

  Future<void> _applyParentChange(String id, String? newParentId) async {
    await requireById(id);
    if (await _service.wouldCreateCycle(id, newParentId)) {
      throw ReferentialIntegrityException(
        'Cannot move a location inside itself or one of its sub-locations.',
      );
    }
    String? placeId;
    if (newParentId != null) {
      final parent = await requireById(newParentId);
      placeId = parent.placeId;
    }
    await _db.transaction(() async {
      await (_db.update(_db.locations)..where((t) => t.id.equals(id))).write(
        LocationsCompanion(
          parentLocationId: Value(newParentId),
          placeId:
              placeId == null ? const Value.absent() : Value(placeId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (placeId != null) {
        await _setSubtreePlace(id, placeId);
      }
    });
  }

  /// Moves the location — and its whole subtree — to another place.
  Future<void> setPlace(String id, String placeId) async {
    await requireById(id);
    // Ensures the place exists (throws RecordNotFoundException otherwise).
    final placeExists = await (_db.select(_db.places)
          ..where((t) => t.id.equals(placeId)))
        .getSingleOrNull();
    if (placeExists == null) {
      throw RecordNotFoundException('Place', placeId);
    }
    await _db.transaction(() async {
      await (_db.update(_db.locations)..where((t) => t.id.equals(id))).write(
        LocationsCompanion(
          placeId: Value(placeId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _setSubtreePlace(id, placeId);
    });
  }

  /// Re-points every descendant of [rootId] at [placeId].
  Future<void> _setSubtreePlace(String rootId, String placeId) async {
    final descendants = await _service.descendants(rootId);
    if (descendants.isEmpty) return;
    final ids = descendants.map((l) => l.id).toList();
    await (_db.update(_db.locations)
          ..where((t) => t.id.isIn(ids)))
        .write(
      LocationsCompanion(
        placeId: Value(placeId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.locations)..where((t) => t.id.equals(id))).go();
  }
}
