import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Hierarchical locations: Home -> Bedroom -> Drawer -> Folder.
/// Deleting a parent sets children's parentLocationId to NULL
/// (schema-level ON DELETE SET NULL).
class LocationRepository {
  LocationRepository(this._db);

  final KeepItDatabase _db;

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
    await guardConstraints(
      () => _db.into(_db.locations).insert(companion),
      entity: 'Location',
    );
  }

  Future<void> update(String id, LocationsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.locations)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Location',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.locations)..where((t) => t.id.equals(id))).go();
  }
}
