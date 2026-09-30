import 'package:drift/drift.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/move_item_repository.dart';
import '../../../core/database/repositories/move_repository.dart';
import '../../../shared/services/location_service.dart';

/// Progress snapshot for a move.
class MoveProgress {
  const MoveProgress({
    required this.total,
    required this.byStatus,
    required this.boxCount,
  });

  final int total;
  final Map<String, int> byStatus;
  final int boxCount;

  int get packed =>
      (byStatus[MoveItemStatus.packed] ?? 0) +
      (byStatus[MoveItemStatus.inTransit] ?? 0) +
      (byStatus[MoveItemStatus.delivered] ?? 0) +
      (byStatus[MoveItemStatus.unpacked] ?? 0);

  int get unpacked => byStatus[MoveItemStatus.unpacked] ?? 0;

  double get packedFraction => total == 0 ? 0 : packed / total;
  double get unpackedFraction => total == 0 ? 0 : unpacked / total;
}

/// Phase 12 "Moving Mode" orchestration: building a move's item list,
/// advancing statuses in bulk, and completing a move (optionally
/// re-homing unpacked items to a destination location).
class MoveService {
  MoveService({
    required KeepItDatabase db,
    required MoveRepository moves,
    required MoveItemRepository moveItems,
    required BelongingRepository belongings,
    required LocationRepository locations,
    required LocationService locationService,
  }) : _db = db,
       _moves = moves,
       _moveItems = moveItems,
       _belongings = belongings,
       _locations = locations,
       _locationService = locationService;

  final KeepItDatabase _db;
  final MoveRepository _moves;
  final MoveItemRepository _moveItems;
  final BelongingRepository _belongings;
  final LocationRepository _locations;
  final LocationService _locationService;

  /// Adds every owned belonging in a place (via its locations) to the move.
  /// Returns the number of newly added items.
  Future<int> addPlaceContents(String moveId, String placeId) async {
    final locations = await _locations.byPlace(placeId);
    final locationIds = locations.map((l) => l.id).toList();
    if (locationIds.isEmpty) return 0;
    final ids =
        await (_db.select(_db.belongings)..where(
              (t) =>
                  t.locationId.isIn(locationIds) &
                  t.archiveState.equals('owned'),
            ))
            .get()
            .then((rows) => rows.map((r) => r.id).toList());
    return _moveItems.addAll(moveId: moveId, belongingIds: ids);
  }

  /// Adds every owned belonging in a location subtree to the move.
  Future<int> addLocationContents(String moveId, String locationId) async {
    final descendants = await _locationService.descendants(locationId);
    final locationIds = [locationId, ...descendants.map((l) => l.id)];
    final ids =
        await (_db.select(_db.belongings)..where(
              (t) =>
                  t.locationId.isIn(locationIds) &
                  t.archiveState.equals('owned'),
            ))
            .get()
            .then((rows) => rows.map((r) => r.id).toList());
    return _moveItems.addAll(moveId: moveId, belongingIds: ids);
  }

  /// Adds everything stored inside a container (box) to the move, labelled
  /// with the container's name as the box label.
  Future<int> addContainerContents(String moveId, String containerId) async {
    final container = await _belongings.getById(containerId);
    final ids =
        await (_db.select(_db.belongings)..where(
              (t) =>
                  t.containerId.equals(containerId) &
                  t.archiveState.equals('owned'),
            ))
            .get()
            .then((rows) => rows.map((r) => r.id).toList());
    // The container itself travels too.
    ids.add(containerId);
    return _moveItems.addAll(
      moveId: moveId,
      belongingIds: ids,
      boxLabel: container?.name,
    );
  }

  /// Marks every item with [boxLabel] as packed. Returns updated count.
  Future<int> packBox(String moveId, String boxLabel) async {
    final ids = await _moveItems.idsInBox(moveId, boxLabel);
    return _moveItems.setStatusBulk(ids, MoveItemStatus.packed);
  }

  /// Marks every item in the move with the given status. Returns updated count.
  Future<int> setAllWithStatus(
    String moveId,
    String fromStatus,
    String toStatus,
  ) async {
    final items = await _moveItems.forMove(moveId);
    final ids = items
        .where((i) => i.status == fromStatus)
        .map((i) => i.id)
        .toList();
    return _moveItems.setStatusBulk(ids, toStatus);
  }

  Future<MoveProgress> progress(String moveId) async {
    final byStatus = await _moveItems.countsByStatus(moveId);
    final total = byStatus.values.fold(0, (a, b) => a + b);
    final boxes = await _moveItems.boxLabels(moveId);
    return MoveProgress(
      total: total,
      byStatus: byStatus,
      boxCount: boxes.length,
    );
  }

  /// Completes a move: advances its status to completed and, when
  /// [destinationLocationId] is given, re-homes every delivered/unpacked
  /// item to that location (clearing container links, since moving boxes
  /// are unpacked at the destination).
  ///
  /// Items still in earlier statuses keep their current locations — the
  /// user never loses track of something that has not arrived.
  Future<void> completeMove(
    String moveId, {
    String? destinationLocationId,
  }) async {
    final move = await _moves.requireById(moveId);
    if (move.status == MoveStatus.completed) return;

    if (destinationLocationId != null) {
      await _locations.requireById(destinationLocationId);
      final items = await _moveItems.forMove(moveId);
      for (final item in items) {
        if (item.status == MoveItemStatus.delivered ||
            item.status == MoveItemStatus.unpacked) {
          await _belongings.update(
            item.belongingId,
            BelongingsCompanion(
              locationId: Value(destinationLocationId),
              containerId: const Value.absent(),
            ),
          );
          if (item.status == MoveItemStatus.delivered) {
            await _moveItems.setStatus(item.id, MoveItemStatus.unpacked);
          }
        }
      }
    }

    // Walk the move through any remaining statuses to completed.
    var current = (await _moves.requireById(moveId)).status;
    while (MoveStatus.next(current) != null) {
      await _moves.advanceStatus(moveId);
      current = (await _moves.requireById(moveId)).status;
    }
  }
}
