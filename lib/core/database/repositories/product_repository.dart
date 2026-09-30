import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Line items belonging to a purchase (e.g. products on a receipt).
class ProductRepository {
  ProductRepository(this._db);

  final KeepItDatabase _db;

  Future<Product?> getById(String id) {
    return (_db.select(_db.products)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Product> requireById(String id) async {
    final product = await getById(id);
    if (product == null) throw RecordNotFoundException('Product', id);
    return product;
  }

  Stream<List<Product>> watchByPurchase(String purchaseId) {
    return ((_db.select(_db.products)
          ..where((t) => t.purchaseId.equals(purchaseId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch());
  }

  Future<List<Product>> getByPurchase(String purchaseId) {
    return (_db.select(_db.products)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .get();
  }

  Future<void> create(ProductsCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.products).insert(companion),
      entity: 'Product',
    );
  }

  Future<void> update(String id, ProductsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Product',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.products)..where((t) => t.id.equals(id))).go();
  }
}
