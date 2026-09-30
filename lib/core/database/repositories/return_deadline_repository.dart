import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Return deadlines — at most one per purchase (unique purchaseId).
class ReturnDeadlineRepository {
  ReturnDeadlineRepository(this._db);

  final KeepItDatabase _db;

  Future<ReturnDeadline?> getById(String id) {
    return (_db.select(_db.returnDeadlines)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<ReturnDeadline> requireById(String id) async {
    final deadline = await getById(id);
    if (deadline == null) throw RecordNotFoundException('ReturnDeadline', id);
    return deadline;
  }

  Future<ReturnDeadline?> getByPurchaseId(String purchaseId) {
    return (_db.select(_db.returnDeadlines)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .getSingleOrNull();
  }

  Stream<ReturnDeadline?> watchByPurchase(String purchaseId) {
    return ((_db.select(_db.returnDeadlines)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .watchSingleOrNull());
  }

  /// Deadlines on or before [date], soonest first. Powers the
  /// "return window closing" reminders.
  /// Every return deadline, soonest first.
  Future<List<ReturnDeadline>> getAll() {
    return (_db.select(_db.returnDeadlines)
          ..orderBy([(t) => OrderingTerm.asc(t.deadlineDate)]))
        .get();
  }

  /// Reactive feed of all return deadlines (drives home-screen refresh).
  Stream<List<ReturnDeadline>> watchAll() {
    return (_db.select(_db.returnDeadlines)
          ..orderBy([(t) => OrderingTerm.asc(t.deadlineDate)]))
        .watch();
  }

  Future<List<ReturnDeadline>> dueOnOrBefore(DateTime date) {
    return (_db.select(_db.returnDeadlines)
          ..where((t) => t.deadlineDate.isSmallerOrEqualValue(date))
          ..orderBy([(t) => OrderingTerm.asc(t.deadlineDate)]))
        .get();
  }

  Future<void> create(ReturnDeadlinesCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.returnDeadlines).insert(companion),
      entity: 'ReturnDeadline',
    );
  }

  Future<void> update(String id, ReturnDeadlinesCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () =>
          (_db.update(_db.returnDeadlines)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'ReturnDeadline',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.returnDeadlines)..where((t) => t.id.equals(id))).go();
  }
}
