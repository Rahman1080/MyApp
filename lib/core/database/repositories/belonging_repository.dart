import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Belongings — physical items with an optional hierarchical location.
class BelongingRepository {
  BelongingRepository(this._db);

  final KeepItDatabase _db;

  Future<Belonging?> getById(String id) {
    return (_db.select(_db.belongings)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Belonging> requireById(String id) async {
    final belonging = await getById(id);
    if (belonging == null) throw RecordNotFoundException('Belonging', id);
    return belonging;
  }

  Stream<List<Belonging>> watchAll() {
    return ((_db.select(_db.belongings)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  Stream<List<Belonging>> watchByLocation(String locationId) {
    return ((_db.select(_db.belongings)
          ..where((t) => t.locationId.equals(locationId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Belongings whose name or brand contains [query] (case-insensitive).
  Future<List<Belonging>> search(String query) {
    return (_db.select(_db.belongings)
          ..where(
            (t) => t.name.contains(query) | t.brand.contains(query),
          ))
        .get();
  }

  Future<List<Belonging>> inLocations(List<String> locationIds) {
    if (locationIds.isEmpty) return Future.value(const []);
    return (_db.select(_db.belongings)
          ..where((t) => t.locationId.isIn(locationIds)))
        .get();
  }

  Future<void> create(BelongingsCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.belongings).insert(companion),
      entity: 'Belonging',
    );
  }

  Future<void> update(String id, BelongingsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.belongings)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Belonging',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.belongings)..where((t) => t.id.equals(id))).go();
  }
}
