import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Receipts — at most one per purchase (unique purchaseId).
class ReceiptRepository {
  ReceiptRepository(this._db);

  final KeepItDatabase _db;

  Future<Receipt?> getById(String id) {
    return (_db.select(_db.receipts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Receipt> requireById(String id) async {
    final receipt = await getById(id);
    if (receipt == null) throw RecordNotFoundException('Receipt', id);
    return receipt;
  }

  Future<Receipt?> getByPurchaseId(String purchaseId) {
    return (_db.select(_db.receipts)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .getSingleOrNull();
  }

  Stream<Receipt?> watchByPurchase(String purchaseId) {
    return ((_db.select(_db.receipts)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .watchSingleOrNull());
  }

  /// Receipts whose store name contains [query] (case-insensitive).
  Future<List<Receipt>> searchByStore(String query) {
    return (_db.select(_db.receipts)..where((t) => t.store.contains(query)))
        .get();
  }

  Future<void> create(ReceiptsCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.receipts).insert(companion),
      entity: 'Receipt',
    );
  }

  Future<void> update(String id, ReceiptsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.receipts)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Receipt',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.receipts)..where((t) => t.id.equals(id))).go();
  }
}
