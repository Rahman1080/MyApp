import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Reminders — one row per scheduled local notification.
/// Entity types: purchase | deadline | warranty | return_deadline | custom.
class ReminderRepository {
  ReminderRepository(this._db);

  final KeepItDatabase _db;

  Future<Reminder?> getById(String id) {
    return (_db.select(_db.reminders)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Reminder> requireById(String id) async {
    final reminder = await getById(id);
    if (reminder == null) throw RecordNotFoundException('Reminder', id);
    return reminder;
  }

  /// Pending reminders ordered by fire time.
  Stream<List<Reminder>> watchPending() {
    return ((_db.select(_db.reminders)
          ..where((t) => t.isDone.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.remindAt)]))
        .watch());
  }

  /// Pending reminders for one linked entity (e.g. all reminders of a
  /// deadline), so rescheduling can replace them atomically.
  Future<List<Reminder>> forEntity(String entityType, String entityId) {
    return (_db.select(_db.reminders)
          ..where((t) => t.entityType.equals(entityType))
          ..where((t) => t.entityId.equals(entityId)))
        .get();
  }

  /// Fire times that are now in the past and still pending — candidates for
  /// immediate delivery or cleanup on app start.
  Future<List<Reminder>> overduePending(DateTime now) {
    return (_db.select(_db.reminders)
          ..where((t) => t.isDone.equals(false))
          ..where((t) => t.remindAt.isSmallerThanValue(now))
          ..orderBy([(t) => OrderingTerm.asc(t.remindAt)]))
        .get();
  }

  /// One-shot pending reminders ordered by fire time. Used by the
  /// notification sync pass (the stream variant cannot be awaited).
  Future<List<Reminder>> getPending() {
    return ((_db.select(_db.reminders)
          ..where((t) => t.isDone.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.remindAt)]))
        .get());
  }

  Future<void> create(RemindersCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.reminders).insert(companion),
      entity: 'Reminder',
    );
  }

  Future<void> update(String id, RemindersCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.reminders)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Reminder',
    );
  }

  Future<void> markDone(String id, {required bool done}) async {
    await requireById(id);
    await (_db.update(_db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        isDone: Value(done),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.reminders)..where((t) => t.id.equals(id))).go();
  }

  /// Deletes every reminder linked to one entity. Used when the parent
  /// deadline/purchase is deleted or reminders are rescheduled.
  Future<void> deleteForEntity(String entityType, String entityId) {
    return (_db.delete(_db.reminders)
          ..where((t) => t.entityType.equals(entityType))
          ..where((t) => t.entityId.equals(entityId)))
        .go()
        .then((_) {});
  }
}
