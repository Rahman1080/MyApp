import 'package:drift/drift.dart';

import '../../../shared/services/location_service.dart';
import '../belonging_meta.dart';
import '../keepit_database.dart';
import '../tables.dart';
import 'belonging_history_repository.dart';
import 'exceptions.dart';

/// Belongings — physical items with an optional hierarchical location.
///
/// Phase 9 adds: an optional purchase link (which surfaces that purchase's
/// receipt and warranty), condition, archive states, model/serial number,
/// and automatic history entries for important actions.
///
/// Phase 10 adds container mode: a belonging with [isContainer] true is a
/// box/bin/folder that holds other belongings via [containerId]. Items
/// inside a container derive their physical location from it, so their own
/// [locationId] is cleared. Container nesting is cycle-guarded.
class BelongingRepository {
  BelongingRepository(this._db)
    : _history = BelongingHistoryRepository(_db),
      _locations = LocationService(_db);

  final KeepItDatabase _db;
  final BelongingHistoryRepository _history;
  final LocationService _locations;

  Future<Belonging?> getById(String id) {
    return (_db.select(
      _db.belongings,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Belonging> requireById(String id) async {
    final belonging = await getById(id);
    if (belonging == null) throw RecordNotFoundException('Belonging', id);
    return belonging;
  }

  Stream<List<Belonging>> watchAll() {
    return ((_db.select(
      _db.belongings,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch());
  }

  /// Every belonging, as a one-shot query. Prefer this over
  /// `watchAll().first` for one-time loads: a cancelled watch stream can
  /// stall subsequent queries under Flutter's FakeAsync test clock.
  Future<List<Belonging>> getAll() {
    return ((_db.select(
      _db.belongings,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get());
  }

  /// Items in any of [states], e.g. `[BelongingArchiveState.owned]` for the
  /// default "My Stuff" list.
  Stream<List<Belonging>> watchByArchiveStates(List<String> states) {
    return ((_db.select(_db.belongings)
          ..where((t) => t.archiveState.isIn(states))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  Stream<List<Belonging>> watchByLocation(String locationId) {
    return ((_db.select(_db.belongings)
          ..where((t) => t.locationId.equals(locationId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Reverse relationship: every item linked to [purchaseId].
  Future<List<Belonging>> byPurchaseId(String purchaseId) {
    return ((_db.select(_db.belongings)
          ..where((t) => t.purchaseId.equals(purchaseId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get());
  }

  Stream<List<Belonging>> watchByPurchaseId(String purchaseId) {
    return ((_db.select(_db.belongings)
          ..where((t) => t.purchaseId.equals(purchaseId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Belongings whose name or brand contains [query] (case-insensitive).
  Future<List<Belonging>> search(String query) {
    return (_db.select(
      _db.belongings,
    )..where((t) => t.name.contains(query) | t.brand.contains(query))).get();
  }

  Future<List<Belonging>> inLocations(List<String> locationIds) {
    if (locationIds.isEmpty) return Future.value(const []);
    return (_db.select(
      _db.belongings,
    )..where((t) => t.locationId.isIn(locationIds))).get();
  }

  Future<List<Belonging>> byIds(Set<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (_db.select(
      _db.belongings,
    )..where((t) => t.id.isIn(ids.toList()))).get();
  }

  /// Creates the item and logs a 'created' (or 'purchased' when a purchase
  /// is linked) history entry.
  Future<String> create(BelongingsCompanion companion) async {
    final withId = companion.id.present
        ? companion
        : companion.copyWith(id: Value(newRecordId()));
    final id = withId.id.value;
    await guardConstraints(
      () => _db.into(_db.belongings).insert(withId),
      entity: 'Belonging',
    );
    final purchaseId = withId.purchaseId.value;
    final isContainer = withId.isContainer.present && withId.isContainer.value;
    await _history.log(
      belongingId: id,
      eventType: purchaseId == null
          ? BelongingHistoryEvent.created
          : BelongingHistoryEvent.purchased,
      title: isContainer
          ? 'Container created'
          : purchaseId == null
          ? 'Added to My Stuff'
          : 'Purchased',
      details: withId.name.value,
      relatedEntityType: purchaseId == null ? null : 'purchase',
      relatedEntityId: purchaseId,
    );
    return id;
  }

  Future<void> update(String id, BelongingsCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.belongings)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Belonging',
    );
  }

  /// Moves the item and records a "Moved from X to Y" history entry.
  Future<void> moveToLocation(
    String id,
    String? newLocationId, {
    String? fromName,
    String? toName,
  }) async {
    final belonging = await requireById(id);
    if (newLocationId == belonging.locationId &&
        belonging.containerId == null) {
      return;
    }
    await update(
      id,
      BelongingsCompanion(
        locationId: Value(newLocationId),
        containerId: const Value<String?>(null),
      ),
    );
    final from = fromName ?? 'No location';
    final to = toName ?? 'No location';
    await _history.log(
      belongingId: id,
      eventType: BelongingHistoryEvent.moved,
      title: 'Moved from $from to $to',
      relatedEntityType: 'location',
      relatedEntityId: newLocationId,
    );
  }

  /// Links (or unlinks, when [purchaseId] is null) the item to a purchase
  /// and records the change in history. Never creates a purchase.
  Future<void> linkPurchase(String id, String? purchaseId) async {
    final belonging = await requireById(id);
    if (purchaseId == belonging.purchaseId) return;
    await update(id, BelongingsCompanion(purchaseId: Value(purchaseId)));
    if (purchaseId == null) {
      await _history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.note,
        title: 'Unlinked from purchase',
      );
    } else {
      await _history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.purchased,
        title: 'Linked to a purchase',
        relatedEntityType: 'purchase',
        relatedEntityId: purchaseId,
      );
    }
  }

  /// Changes the lifecycle state ('owned' | 'archived' | 'sold' |
  /// 'donated' | 'disposed'), stamps [archivedAt], and logs the change.
  /// Archiving hides the item from the default list; it never deletes it.
  Future<void> setArchiveState(String id, String state) async {
    if (!BelongingArchiveState.all.contains(state)) {
      throw ArgumentError('Unknown archive state: $state');
    }
    final belonging = await requireById(id);
    if (belonging.archiveState == state) return;
    final leavingOwned =
        belonging.archiveState == BelongingArchiveState.owned &&
        state != BelongingArchiveState.owned;
    await update(
      id,
      BelongingsCompanion(
        archiveState: Value(state),
        archivedAt: Value(
          state == BelongingArchiveState.owned ? null : DateTime.now(),
        ),
      ),
    );
    final eventType = switch (state) {
      BelongingArchiveState.archived => BelongingHistoryEvent.archived,
      BelongingArchiveState.sold => BelongingHistoryEvent.sold,
      BelongingArchiveState.donated => BelongingHistoryEvent.donated,
      BelongingArchiveState.disposed => BelongingHistoryEvent.disposed,
      _ => BelongingHistoryEvent.unarchived,
    };
    final title = switch (state) {
      BelongingArchiveState.archived => 'Archived',
      BelongingArchiveState.sold => 'Marked as sold',
      BelongingArchiveState.donated => 'Marked as donated',
      BelongingArchiveState.disposed => 'Marked as disposed',
      _ => leavingOwned ? 'Restored' : 'Restored to owned',
    };
    await _history.log(belongingId: id, eventType: eventType, title: title);
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.belongings)..where((t) => t.id.equals(id))).go();
  }

  // -----------------------------------------------------------------------
  // Containers (Phase 10).
  // -----------------------------------------------------------------------

  /// All containers, ordered by name.
  Future<List<Belonging>> containers() {
    return (_db.select(_db.belongings)
          ..where((t) => t.isContainer.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<Belonging>> watchContainers() {
    return ((_db.select(_db.belongings)
          ..where((t) => t.isContainer.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Containers stored directly in [locationId].
  Stream<List<Belonging>> watchContainersIn(String locationId) {
    return ((_db.select(_db.belongings)
          ..where(
            (t) =>
                t.isContainer.equals(true) &
                t.locationId.equals(locationId) &
                t.containerId.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  /// Items stored directly inside [containerId].
  Future<List<Belonging>> contentsOf(String containerId) {
    return _locations.containerContents(containerId);
  }

  Stream<List<Belonging>> watchContentsOf(String containerId) {
    return _locations.watchContainerContents(containerId);
  }

  /// Creates a container (a belonging with [isContainer] true) and logs it.
  Future<String> createContainer(BelongingsCompanion companion) async {
    final id = await create(companion.copyWith(isContainer: const Value(true)));
    return id;
  }

  /// Moves one or more items to [newLocationId] (null = no location),
  /// taking them out of any container. Logs a 'moved' entry per item.
  Future<void> moveItemsToLocation(
    Set<String> ids,
    String? newLocationId, {
    String? toName,
  }) async {
    if (ids.isEmpty) return;
    String? resolvedToName = toName;
    if (resolvedToName == null && newLocationId != null) {
      final path = await _locations.locationPath(newLocationId);
      resolvedToName = path.isEmpty ? null : path;
    }
    for (final id in ids) {
      final belonging = await requireById(id);
      if (belonging.locationId == newLocationId &&
          belonging.containerId == null) {
        continue;
      }
      await update(
        id,
        BelongingsCompanion(
          locationId: Value(newLocationId),
          containerId: const Value<String?>(null),
        ),
      );
      await _history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.moved,
        title: 'Moved to ${resolvedToName ?? 'no location'}',
        relatedEntityType: 'location',
        relatedEntityId: newLocationId,
      );
    }
  }

  /// Moves one or more items into [containerId]. Items derive their physical
  /// location from the container, so their own location is cleared. Throws
  /// [ReferentialIntegrityException] when moving a container into itself or
  /// one of its descendants.
  Future<void> moveItemsToContainer(Set<String> ids, String containerId) async {
    if (ids.isEmpty) return;
    final container = await requireById(containerId);
    if (!container.isContainer) {
      throw ReferentialIntegrityException(
        '"${container.name}" is not a container.',
      );
    }
    for (final id in ids) {
      if (await _locations.wouldCreateContainerCycle(id, containerId)) {
        throw ReferentialIntegrityException(
          'Cannot place a container inside itself or its own contents.',
        );
      }
    }
    for (final id in ids) {
      final belonging = await requireById(id);
      if (belonging.containerId == containerId) continue;
      await update(
        id,
        BelongingsCompanion(
          containerId: Value(containerId),
          locationId: const Value<String?>(null),
        ),
      );
      await _history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.moved,
        title: 'Moved into ${container.name}',
        relatedEntityType: 'container',
        relatedEntityId: containerId,
      );
    }
  }

  /// Takes items out of their container. They land in [locationId] when
  /// given, otherwise in the container's own location.
  Future<void> removeFromContainer(
    Set<String> ids, {
    String? locationId,
  }) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      final belonging = await requireById(id);
      final fromContainerId = belonging.containerId;
      if (fromContainerId == null) continue;
      String? targetLocationId = locationId;
      String? containerName;
      if (targetLocationId == null) {
        final container = await getById(fromContainerId);
        targetLocationId = container?.locationId;
        containerName = container?.name;
      }
      await update(
        id,
        BelongingsCompanion(
          containerId: const Value<String?>(null),
          locationId: Value(targetLocationId),
        ),
      );
      await _history.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.moved,
        title: containerName == null
            ? 'Taken out of container'
            : 'Taken out of $containerName',
        relatedEntityType: 'container',
        relatedEntityId: fromContainerId,
      );
    }
  }

  /// Moves everything stored in [containerId] out to [locationId] (or the
  /// container's own location when null). The container itself stays.
  Future<void> emptyContainer(String containerId, {String? locationId}) async {
    await requireById(containerId);
    final contents = await contentsOf(containerId);
    await removeFromContainer({
      for (final b in contents) b.id,
    }, locationId: locationId);
  }

  /// Full "where is it?" path for a belonging id, e.g.
  /// "My Home > Garage > Shelf 2 > Box 7". Empty when the item has no
  /// location and sits in no container.
  Future<String> wherePath(String belongingId) async {
    final belonging = await getById(belongingId);
    if (belonging == null) return '';
    return _locations.belongingWherePath(belonging);
  }

  // -----------------------------------------------------------------------
  // Household dashboard (Phase 10).
  // -----------------------------------------------------------------------

  /// Number of belongings that are not containers.
  Future<int> countItems() async {
    final rows = await (_db.select(
      _db.belongings,
    )..where((t) => t.isContainer.equals(false))).get();
    return rows.length;
  }

  Future<int> countContainers() async {
    final rows = await (_db.select(
      _db.belongings,
    )..where((t) => t.isContainer.equals(true))).get();
    return rows.length;
  }

  /// Items (not containers) with neither a location nor a container.
  Future<int> countWithoutLocation() async {
    final rows =
        await (_db.select(_db.belongings)..where(
              (t) =>
                  t.isContainer.equals(false) &
                  t.locationId.isNull() &
                  t.containerId.isNull(),
            ))
            .get();
    return rows.length;
  }

  /// Items (not containers) flagged as "value unknown".
  Future<int> countUnknownValue() async {
    final rows =
        await (_db.select(_db.belongings)..where(
              (t) => t.isContainer.equals(false) & t.valueUnknown.equals(true),
            ))
            .get();
    return rows.length;
  }
}
