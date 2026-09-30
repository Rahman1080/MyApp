import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Generic deadlines (bills, registrations, custom reminders...).
/// Repeat rules: none | daily | weekly | monthly | yearly | custom.
class DeadlineRepository {
  DeadlineRepository(this._db);

  final KeepItDatabase _db;

  Future<Deadline?> getById(String id) {
    return (_db.select(_db.deadlines)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Deadline> requireById(String id) async {
    final deadline = await getById(id);
    if (deadline == null) throw RecordNotFoundException('Deadline', id);
    return deadline;
  }

  /// Open deadlines ordered by due date. Set [includeDone] to also list
  /// completed ones.
  Stream<List<Deadline>> watchUpcoming({bool includeDone = false}) {
    final query = _db.select(_db.deadlines)
      ..orderBy([
        (t) => OrderingTerm.asc(t.dueDate),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (!includeDone) {
      query.where((t) => t.isDone.equals(false));
    }
    return query.watch();
  }

  /// One-shot variant of [watchUpcoming]: open deadlines ordered by due date.
  /// Used for point-in-time snapshots where no reactivity is needed.
  Future<List<Deadline>> getUpcoming({bool includeDone = false}) {
    final query = _db.select(_db.deadlines)
      ..orderBy([
        (t) => OrderingTerm.asc(t.dueDate),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (!includeDone) {
      query.where((t) => t.isDone.equals(false));
    }
    return query.get();
  }

  /// Open deadlines due on or before [date].
  Future<List<Deadline>> dueOnOrBefore(DateTime date) {
    return (_db.select(_db.deadlines)
          ..where((t) => t.isDone.equals(false))
          ..where((t) => t.dueDate.isSmallerOrEqualValue(date))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();
  }

  Future<List<Deadline>> searchByTitle(String query) {
    return (_db.select(_db.deadlines)..where((t) => t.title.contains(query)))
        .get();
  }

  Future<List<Deadline>> forPurchase(String purchaseId) {
    return (_db.select(_db.deadlines)
          ..where((t) => t.relatedPurchaseId.equals(purchaseId)))
        .get();
  }

  Future<void> create(DeadlinesCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.deadlines).insert(companion),
      entity: 'Deadline',
    );
  }

  Future<void> update(String id, DeadlinesCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.deadlines)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Deadline',
    );
  }

  Future<void> markDone(String id, {required bool done}) async {
    await requireById(id);
    await (_db.update(_db.deadlines)..where((t) => t.id.equals(id))).write(
      DeadlinesCompanion(
        isDone: Value(done),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.deadlines)..where((t) => t.id.equals(id))).go();
  }
}
