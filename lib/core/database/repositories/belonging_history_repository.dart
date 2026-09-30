import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';

/// Lightweight timeline of what happened to an item. Entries are written
/// automatically by the repositories for important actions (added, moved,
/// archived, ...) and users can append their own notes from the item
/// detail screen.
class BelongingHistoryRepository {
  BelongingHistoryRepository(this._db);

  final KeepItDatabase _db;

  /// Newest entries first.
  Future<List<BelongingHistoryData>> historyFor(String belongingId,
      {int limit = 100}) {
    return ((_db.select(_db.belongingHistory)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit))
        .get());
  }

  Stream<List<BelongingHistoryData>> watchFor(String belongingId,
      {int limit = 100}) {
    return ((_db.select(_db.belongingHistory)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit))
        .watch());
  }

  /// Appends one entry. [occurredAt] defaults to now; pass an explicit
  /// date for back-dated events (e.g. "purchased" with the receipt date).
  Future<String> log({
    required String belongingId,
    required String eventType,
    required String title,
    String? details,
    DateTime? occurredAt,
    String? relatedEntityType,
    String? relatedEntityId,
  }) async {
    final id = newRecordId();
    await _db.into(_db.belongingHistory).insert(
          BelongingHistoryCompanion.insert(
            id: Value(id),
            belongingId: belongingId,
            eventType: eventType,
            title: title,
            details: Value(details),
            occurredAt: Value(occurredAt ?? DateTime.now()),
            relatedEntityType: Value(relatedEntityType),
            relatedEntityId: Value(relatedEntityId),
          ),
        );
    return id;
  }

  Future<void> deleteForBelonging(String belongingId) async {
    await (_db.delete(_db.belongingHistory)
          ..where((t) => t.belongingId.equals(belongingId)))
        .go();
  }
}
