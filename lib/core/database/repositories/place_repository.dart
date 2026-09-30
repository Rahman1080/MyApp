import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';
import 'exceptions.dart';

/// Places — top-level physical properties (My Home, Parents' Home, Office,
/// Storage Unit, ...). Added in schema v5 (Phase 10).
///
/// The v4 -> v5 migration creates the default place ([defaultPlaceId],
/// "My Home"), so existing users never have to create one manually. The
/// default place cannot be deleted.
class PlaceRepository {
  PlaceRepository(this._db);

  final KeepItDatabase _db;

  /// Returns the default place, creating it if it does not exist (e.g.
  /// after restoring a legacy backup that has no places table).
  Future<Place> ensureDefaultPlace() async {
    final existing = await getById(defaultPlaceId);
    if (existing != null) return existing;
    await _db.into(_db.places).insert(
          PlacesCompanion.insert(
            id: const Value(defaultPlaceId),
            name: 'My Home',
          ),
        );
    return requireById(defaultPlaceId);
  }

  Future<Place?> getById(String id) {
    return (_db.select(_db.places)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Place> requireById(String id) async {
    final place = await getById(id);
    if (place == null) throw RecordNotFoundException('Place', id);
    return place;
  }

  Future<List<Place>> getAll() {
    return (_db.select(_db.places)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<Place>> watchAll() {
    return ((_db.select(_db.places)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Convenience: create a place with just a name.
  Future<String> createNamed(String name, {String? notes}) {
    return create(PlacesCompanion.insert(
      name: name,
      notes: notes == null ? const Value.absent() : Value(notes),
    ));
  }

  /// Convenience: rename a place.
  Future<void> rename(String id, String name) {
    return update(id, PlacesCompanion(name: Value(name)));
  }

  Future<String> create(PlacesCompanion companion) async {    final withId = companion.id.present
        ? companion
        : companion.copyWith(id: Value(newRecordId()));
    final id = withId.id.value;
    await guardConstraints(
      () => _db.into(_db.places).insert(withId),
      entity: 'Place',
    );
    return id;
  }

  Future<void> update(String id, PlacesCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.places)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Place',
    );
  }

  /// Deletes a place. The default place can never be deleted, and a place
  /// that still contains locations cannot be deleted either — move or
  /// delete its locations first.
  Future<void> delete(String id) async {
    await requireById(id);
    if (id == defaultPlaceId) {
      throw ReferentialIntegrityException(
        'The default place cannot be deleted.',
      );
    }
    final locationCount = await (_db.select(_db.locations)
          ..where((t) => t.placeId.equals(id)))
        .get()
        .then((rows) => rows.length);
    if (locationCount > 0) {
      throw ReferentialIntegrityException(
        'This place still contains $locationCount location'
        '${locationCount == 1 ? '' : 's'}. Move or delete them first.',
      );
    }
    await (_db.delete(_db.places)..where((t) => t.id.equals(id))).go();
  }

  /// Number of locations directly in [placeId].
  Future<int> locationCount(String placeId) async {
    final rows = await (_db.select(_db.locations)
          ..where((t) => t.placeId.equals(placeId)))
        .get();
    return rows.length;
  }
}
