import 'package:drift/drift.dart';

import '../belonging_meta.dart';
import '../keepit_database.dart';
import '../tables.dart';
import 'belonging_history_repository.dart';
import 'exceptions.dart';

/// Per-item photo gallery. The legacy single `photo_path` on belongings is
/// kept as the cover photo; this table holds any additional photos.
/// Adding a photo writes an automatic history entry on the item.
class BelongingPhotoRepository {
  BelongingPhotoRepository(this._db)
      : _history = BelongingHistoryRepository(_db);

  final KeepItDatabase _db;
  final BelongingHistoryRepository _history;

  Future<BelongingPhoto?> getById(String id) {
    return (_db.select(_db.belongingPhotos)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<BelongingPhoto> requireById(String id) async {
    final photo = await getById(id);
    if (photo == null) throw RecordNotFoundException('BelongingPhoto', id);
    return photo;
  }

  /// Photos for one item, oldest first (gallery order).
  Future<List<BelongingPhoto>> photosFor(String belongingId) {
    return ((_db.select(_db.belongingPhotos)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get());
  }

  Stream<List<BelongingPhoto>> watchFor(String belongingId) {
    return ((_db.select(_db.belongingPhotos)
          ..where((t) => t.belongingId.equals(belongingId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch());
  }

  Future<String> add({
    required String belongingId,
    required String filePath,
    String? caption,
  }) async {
    final existing = await photosFor(belongingId);
    final id = newRecordId();
    await guardConstraints(
      () => _db.into(_db.belongingPhotos).insert(
            BelongingPhotosCompanion.insert(
              id: Value(id),
              belongingId: belongingId,
              filePath: filePath,
              caption: Value(caption),
              sortOrder: Value(existing.length),
            ),
          ),
      entity: 'BelongingPhoto',
    );
    await _history.log(
      belongingId: belongingId,
      eventType: BelongingHistoryEvent.photoAdded,
      title: caption == null || caption.isEmpty
          ? 'Photo added'
          : 'Photo added: $caption',
    );
    return id;
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.belongingPhotos)..where((t) => t.id.equals(id)))
        .go();
  }
}
