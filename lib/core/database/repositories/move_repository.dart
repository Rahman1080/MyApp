import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';
import 'exceptions.dart';

/// Move statuses. Flow: planning -> packing -> in_transit -> unpacking ->
/// completed. Any non-completed status can go to cancelled.
class MoveStatus {
  static const planning = 'planning';
  static const packing = 'packing';
  static const inTransit = 'in_transit';
  static const unpacking = 'unpacking';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static const all = [
    planning,
    packing,
    inTransit,
    unpacking,
    completed,
    cancelled,
  ];

  /// Statuses that still allow editing the move's item list.
  static const editable = [planning, packing];

  static bool isTerminal(String status) =>
      status == completed || status == cancelled;

  /// Human-readable label.
  static String label(String status) => switch (status) {
    planning => 'Planning',
    inTransit => 'In transit',
    unpacking => 'Unpacking',
    completed => 'Completed',
    cancelled => 'Cancelled',
    _ => 'Packing',
  };

  /// The next status in the normal flow, or null if terminal.
  static String? next(String status) => switch (status) {
    planning => packing,
    packing => inTransit,
    inTransit => unpacking,
    unpacking => completed,
    _ => null,
  };
}

/// Moves — Phase 12 "Moving Mode" relocation projects.
class MoveRepository {
  MoveRepository(this._db);

  final KeepItDatabase _db;

  Future<Move?> getById(String id) {
    return (_db.select(
      _db.moves,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Move> requireById(String id) async {
    final move = await getById(id);
    if (move == null) throw RecordNotFoundException('Move', id);
    return move;
  }

  Future<List<Move>> getAll({bool includeCompleted = true}) {
    final query = _db.select(_db.moves)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (!includeCompleted) {
      query.where(
        (t) => t.status.isNotIn([MoveStatus.completed, MoveStatus.cancelled]),
      );
    }
    return query.get();
  }

  Stream<List<Move>> watchAll() {
    return ((_db.select(
      _db.moves,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch());
  }

  Stream<Move?> watchById(String id) {
    return ((_db.select(
      _db.moves,
    )..where((t) => t.id.equals(id))).watchSingleOrNull());
  }

  Future<String> create(MovesCompanion companion) async {
    final withId = companion.id.present
        ? companion
        : companion.copyWith(id: Value(newRecordId()));
    final id = withId.id.value;
    await guardConstraints(
      () => _db.into(_db.moves).insert(withId),
      entity: 'Move',
    );
    return id;
  }

  /// Convenience: create a move with just a name and optional places/date.
  Future<String> createNamed(
    String name, {
    String? fromPlaceId,
    String? toPlaceId,
    DateTime? moveDate,
    String? notes,
  }) {
    return create(
      MovesCompanion.insert(
        name: name,
        fromPlaceId: Value(fromPlaceId),
        toPlaceId: Value(toPlaceId),
        moveDate: Value(moveDate),
        notes: Value(notes),
      ),
    );
  }

  Future<void> update(String id, MovesCompanion companion) async {
    await requireById(id);
    await (_db.update(_db.moves)..where((t) => t.id.equals(id))).write(
      companion.copyWith(updatedAt: Value(DateTime.now())),
    );
  }

  /// Advances the move to the next status in the normal flow.
  /// Throws [StateError] if the move is already terminal.
  Future<void> advanceStatus(String id) async {
    final move = await requireById(id);
    final next = MoveStatus.next(move.status);
    if (next == null) {
      throw StateError('Move ${move.id} is already ${move.status}');
    }
    await update(
      id,
      MovesCompanion(
        status: Value(next),
        completedAt: next == MoveStatus.completed
            ? Value(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  /// Cancels a move. Terminal moves cannot be cancelled.
  Future<void> cancel(String id) async {
    final move = await requireById(id);
    if (MoveStatus.isTerminal(move.status)) {
      throw StateError('Move ${move.id} is already ${move.status}');
    }
    await update(id, const MovesCompanion(status: Value(MoveStatus.cancelled)));
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.moves)..where((t) => t.id.equals(id))).go();
  }
}
