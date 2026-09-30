import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';
import 'exceptions.dart';

/// Move item statuses. Flow: to_pack -> packed -> in_transit -> delivered ->
/// unpacked. 'unpacked' is terminal.
class MoveItemStatus {
  static const toPack = 'to_pack';
  static const packed = 'packed';
  static const inTransit = 'in_transit';
  static const delivered = 'delivered';
  static const unpacked = 'unpacked';

  static const all = [toPack, packed, inTransit, delivered, unpacked];

  static String label(String status) => switch (status) {
    toPack => 'To pack',
    packed => 'Packed',
    inTransit => 'In transit',
    delivered => 'Delivered',
    _ => 'Unpacked',
  };

  /// The next status in the normal flow, or null if terminal.
  static String? next(String status) => switch (status) {
    toPack => packed,
    packed => inTransit,
    inTransit => delivered,
    delivered => unpacked,
    _ => null,
  };

  /// Whether [from] may transition to [to]. Forward-only, one step at a
  /// time, except that any status may jump straight to 'unpacked' (e.g.
  /// something that never needed packing).
  static bool canTransition(String from, String to) {
    if (from == to) return true;
    if (to == unpacked) return from != unpacked;
    return next(from) == to;
  }
}

/// One belonging's participation in a move, with packing status and box label.
class MoveItemRepository {
  MoveItemRepository(this._db);

  final KeepItDatabase _db;

  Future<MoveItem?> getById(String id) {
    return (_db.select(
      _db.moveItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<MoveItem> requireById(String id) async {
    final item = await getById(id);
    if (item == null) throw RecordNotFoundException('MoveItem', id);
    return item;
  }

  /// All items in a move, ordered by box label then sort order.
  Future<List<MoveItem>> forMove(String moveId) {
    return ((_db.select(_db.moveItems)
          ..where((t) => t.moveId.equals(moveId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.boxLabel),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get());
  }

  Stream<List<MoveItem>> watchForMove(String moveId) {
    return (((_db.select(_db.moveItems)
          ..where((t) => t.moveId.equals(moveId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.boxLabel),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .watch()));
  }

  /// Distinct non-empty box labels used in a move.
  Future<List<String>> boxLabels(String moveId) async {
    final query = _db.selectOnly(_db.moveItems, distinct: true)
      ..addColumns([_db.moveItems.boxLabel])
      ..where(
        _db.moveItems.moveId.equals(moveId) &
            _db.moveItems.boxLabel.isNotNull(),
      );
    final rows = await query.get();
    return rows
        .map((r) => r.read(_db.moveItems.boxLabel))
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toList()
      ..sort();
  }

  /// Counts of move items per status.
  Future<Map<String, int>> countsByStatus(String moveId) async {
    final counts = <String, int>{for (final s in MoveItemStatus.all) s: 0};
    final query = _db.selectOnly(_db.moveItems)
      ..addColumns([_db.moveItems.status, _db.moveItems.id.count()])
      ..where(_db.moveItems.moveId.equals(moveId))
      ..groupBy([_db.moveItems.status]);
    for (final row in await query.get()) {
      final status = row.read(_db.moveItems.status)!;
      counts[status] = row.read(_db.moveItems.id.count()) ?? 0;
    }
    return counts;
  }

  /// Adds a belonging to a move. Idempotent: returns the existing row id if
  /// the belonging is already in the move.
  Future<String> add({
    required String moveId,
    required String belongingId,
    String? boxLabel,
    String? notes,
  }) async {
    final existing =
        await (_db.select(_db.moveItems)..where(
              (t) =>
                  t.moveId.equals(moveId) & t.belongingId.equals(belongingId),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;

    final maxSort =
        await (_db.selectOnly(_db.moveItems)
              ..addColumns([_db.moveItems.sortOrder.max()])
              ..where(_db.moveItems.moveId.equals(moveId)))
            .getSingle()
            .then((r) => r.read(_db.moveItems.sortOrder.max()) ?? -1);

    final id = newRecordId();
    await guardConstraints(
      () => _db
          .into(_db.moveItems)
          .insert(
            MoveItemsCompanion.insert(
              id: Value(id),
              moveId: moveId,
              belongingId: belongingId,
              boxLabel: Value(boxLabel),
              notes: Value(notes),
              sortOrder: Value(maxSort + 1),
            ),
          ),
      entity: 'MoveItem',
    );
    return id;
  }

  /// Adds many belongings to a move, skipping ones already present.
  /// Returns the number of newly added rows.
  Future<int> addAll({
    required String moveId,
    required List<String> belongingIds,
    String? boxLabel,
  }) async {
    var added = 0;
    for (final belongingId in belongingIds) {
      final existing =
          await (_db.select(_db.moveItems)..where(
                (t) =>
                    t.moveId.equals(moveId) & t.belongingId.equals(belongingId),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await add(moveId: moveId, belongingId: belongingId, boxLabel: boxLabel);
        added++;
      }
    }
    return added;
  }

  Future<void> setStatus(String id, String status) async {
    final item = await requireById(id);
    if (!MoveItemStatus.canTransition(item.status, status)) {
      throw StateError(
        'Cannot move item ${item.id} from ${item.status} to $status',
      );
    }
    await (_db.update(_db.moveItems)..where((t) => t.id.equals(id))).write(
      MoveItemsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Advances one item to its next status. No-op for terminal items.
  Future<void> advance(String id) async {
    final item = await requireById(id);
    final next = MoveItemStatus.next(item.status);
    if (next != null) await setStatus(id, next);
  }

  /// Bulk status update. Items that cannot legally transition are skipped;
  /// returns the number actually updated.
  Future<int> setStatusBulk(List<String> ids, String status) async {
    var updated = 0;
    for (final id in ids) {
      final item = await getById(id);
      if (item == null) continue;
      if (!MoveItemStatus.canTransition(item.status, status)) continue;
      await (_db.update(_db.moveItems)..where((t) => t.id.equals(id))).write(
        MoveItemsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );
      updated++;
    }
    return updated;
  }

  /// All move-item ids in a move with the given box label.
  Future<List<String>> idsInBox(String moveId, String boxLabel) {
    return (_db.selectOnly(_db.moveItems)
          ..addColumns([_db.moveItems.id])
          ..where(
            _db.moveItems.moveId.equals(moveId) &
                _db.moveItems.boxLabel.equals(boxLabel),
          ))
        .get()
        .then((rows) => rows.map((r) => r.read(_db.moveItems.id)!).toList());
  }

  Future<void> setBoxLabel(String id, String? boxLabel) async {
    await requireById(id);
    await (_db.update(_db.moveItems)..where((t) => t.id.equals(id))).write(
      MoveItemsCompanion(
        boxLabel: Value(boxLabel),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> remove(String id) async {
    await requireById(id);
    await (_db.delete(_db.moveItems)..where((t) => t.id.equals(id))).go();
  }

  /// Removes every item from a move (used when deleting/cancelling).
  Future<void> clearMove(String moveId) async {
    await (_db.delete(
      _db.moveItems,
    )..where((t) => t.moveId.equals(moveId))).go();
  }
}
