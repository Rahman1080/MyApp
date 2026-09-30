import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Documents — local files (PDFs/images) attached to purchases or belongings.
/// Document types: receipt | warranty | manual | invoice | contract |
/// registration | other.
class DocumentRepository {
  DocumentRepository(this._db);

  final KeepItDatabase _db;

  Future<Document?> getById(String id) {
    return (_db.select(_db.documents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Document> requireById(String id) async {
    final document = await getById(id);
    if (document == null) throw RecordNotFoundException('Document', id);
    return document;
  }

  Stream<List<Document>> watchByPurchase(String purchaseId) {
    return ((_db.select(_db.documents)
          ..where((t) => t.purchaseId.equals(purchaseId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch());
  }

  /// One-shot read of a purchase's documents (widget-test safe).
  Future<List<Document>> getByPurchase(String purchaseId) {
    return ((_db.select(_db.documents)
          ..where((t) => t.purchaseId.equals(purchaseId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get());
  }

  /// One-shot read of a belonging's documents (widget-test safe).
  Future<List<Document>> getByBelonging(String belongingId) {
    return ((_db.select(_db.documents)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get());
  }

  Stream<List<Document>> watchByBelonging(String belongingId) {
    return ((_db.select(_db.documents)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch());
  }

  Future<List<Document>> searchByTitle(String query) {
    return (_db.select(_db.documents)..where((t) => t.title.contains(query)))
        .get();
  }

  Future<void> create(DocumentsCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.documents).insert(companion),
      entity: 'Document',
    );
  }

  Future<void> update(String id, DocumentsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.documents)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Document',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
  }
}
