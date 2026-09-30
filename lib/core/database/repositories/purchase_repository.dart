import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// CRUD + reactive queries for [Purchase], the central record of the app.
class PurchaseRepository {
  PurchaseRepository(this._db);

  final KeepItDatabase _db;

  Future<Purchase?> getById(String id) {
    return (_db.select(_db.purchases)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Purchase> requireById(String id) async {
    final purchase = await getById(id);
    if (purchase == null) throw RecordNotFoundException('Purchase', id);
    return purchase;
  }

  /// All purchases, newest first. Optional [status] filter.
  Stream<List<Purchase>> watchAll({String? status}) {
    final query = _db.select(_db.purchases)
      ..orderBy([
        (t) => OrderingTerm.desc(t.purchaseDate),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }
    return query.watch();
  }

  /// One-shot variant of [watchAll]: every purchase, newest first. Used for
  /// point-in-time snapshots where no reactivity is needed.
  Future<List<Purchase>> getAll() {
    return (_db.select(_db.purchases)
          ..orderBy([
            (t) => OrderingTerm.desc(t.purchaseDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
  }

  /// Purchases whose name contains [query] (case-insensitive). Used by
  /// duplicate detection and global search; excludes [excludeId] when set.
  Future<List<Purchase>> searchByName(String query, {String? excludeId}) {
    final select = _db.select(_db.purchases)
      ..where((t) => t.productName.contains(query));
    if (excludeId != null) {
      select.where((t) => t.id.isNotValue(excludeId));
    }
    return select.get();
  }

  /// Every other purchase — the candidate pool for duplicate detection.
  Future<List<Purchase>> allExcept(String id) {
    return (_db.select(_db.purchases)..where((t) => t.id.isNotValue(id))).get();
  }

  Future<void> create(PurchasesCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.purchases).insert(companion),
      entity: 'Purchase',
    );
  }

  Future<void> update(String id, PurchasesCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.purchases)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Purchase',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.purchases)..where((t) => t.id.equals(id))).go();
  }
}
