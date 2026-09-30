import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Warranties — at most one per purchase (unique purchaseId).
class WarrantyRepository {
  WarrantyRepository(this._db);

  final KeepItDatabase _db;

  Future<Warranty?> getById(String id) {
    return (_db.select(_db.warranties)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Warranty> requireById(String id) async {
    final warranty = await getById(id);
    if (warranty == null) throw RecordNotFoundException('Warranty', id);
    return warranty;
  }

  Future<Warranty?> getByPurchaseId(String purchaseId) {
    return (_db.select(_db.warranties)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .getSingleOrNull();
  }

  /// Warranties directly linked to a belonging (Phase 14+).
  Future<List<Warranty>> forBelonging(String belongingId) {
    return (_db.select(_db.warranties)
          ..where((t) => t.belongingId.equals(belongingId)))
        .get();
  }

  Stream<Warranty?> watchByPurchase(String purchaseId) {
    return ((_db.select(_db.warranties)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .watchSingleOrNull());
  }

  /// Every warranty, newest first. Home-screen summaries compute expiry via
  /// [warrantyExpiryDate], which also covers duration-based warranties that
  /// [expiringOnOrBefore] (explicit expiration date only) would miss.
  Future<List<Warranty>> getAll() {
    return (_db.select(_db.warranties)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Reactive feed of all warranties (drives home-screen refresh).
  Stream<List<Warranty>> watchAll() {
    return (_db.select(_db.warranties)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Warranties expiring on or before [date], ordered by expiry.
  Future<List<Warranty>> expiringOnOrBefore(DateTime date) {
    return (_db.select(_db.warranties)
          ..where((t) => t.expirationDate.isSmallerOrEqualValue(date))
          ..orderBy([(t) => OrderingTerm.asc(t.expirationDate)]))
        .get();
  }

  Future<void> create(WarrantiesCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.warranties).insert(companion),
      entity: 'Warranty',
    );
  }

  Future<void> update(String id, WarrantiesCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.warranties)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Warranty',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.warranties)..where((t) => t.id.equals(id))).go();
  }
}
