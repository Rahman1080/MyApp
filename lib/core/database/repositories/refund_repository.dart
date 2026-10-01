import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Refunds — at most one per purchase (unique purchaseId).
/// Statuses: requested | pending | received.
class RefundRepository {
  RefundRepository(this._db);

  final KeepItDatabase _db;

  Future<Refund?> getById(String id) {
    return (_db.select(_db.refunds)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Refund> requireById(String id) async {
    final refund = await getById(id);
    if (refund == null) throw RecordNotFoundException('Refund', id);
    return refund;
  }

  Future<List<Refund>> getAll() {
    return (_db.select(_db.refunds)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<Refund?> getByPurchaseId(String purchaseId) {
    return (_db.select(_db.refunds)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .getSingleOrNull();
  }

  Stream<Refund?> watchByPurchase(String purchaseId) {
    return ((_db.select(_db.refunds)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .watchSingleOrNull());
  }

  Stream<List<Refund>> watchByStatus(String status) {
    return ((_db.select(_db.refunds)
          ..where((t) => t.status.equals(status))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch());
  }

  Future<void> create(RefundsCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.refunds).insert(companion),
      entity: 'Refund',
    );
  }

  Future<void> update(String id, RefundsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.refunds)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Refund',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.refunds)..where((t) => t.id.equals(id))).go();
  }
}
