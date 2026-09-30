import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';
import 'exceptions.dart';

/// Tags and their normalized links to any entity.
/// Entity types used across the app: purchase | belonging | document |
/// deadline | location.
class TagRepository {
  TagRepository(this._db);

  final KeepItDatabase _db;

  Future<Tag?> getById(String id) {
    return (_db.select(_db.tags)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Tag> requireById(String id) async {
    final tag = await getById(id);
    if (tag == null) throw RecordNotFoundException('Tag', id);
    return tag;
  }

  Stream<List<Tag>> watchAll() {
    return ((_db.select(_db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  Future<Tag?> getByName(String name) {
    return (_db.select(_db.tags)..where((t) => t.name.equals(name)))
        .getSingleOrNull();
  }

  /// Returns the existing tag with [name] or creates it.
  Future<Tag> getOrCreate(String name) async {
    final existing = await getByName(name);
    if (existing != null) return existing;
    final id = newRecordId();
    await create(TagsCompanion.insert(id: Value(id), name: name));
    return requireById(id);
  }

  Future<void> create(TagsCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.tags).insert(companion),
      entity: 'Tag',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    // Tag links cascade at the schema level.
    await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
  }

  /// Links [tagId] to an entity. Idempotent — re-linking is a no-op.
  Future<void> link({
    required String tagId,
    required String entityType,
    required String entityId,
  }) async {
    await requireById(tagId);
    await guardConstraints(
      () => _db.into(_db.tagLinks).insert(
            TagLinksCompanion.insert(
              tagId: tagId,
              entityType: entityType,
              entityId: entityId,
            ),
            mode: InsertMode.insertOrIgnore,
          ),
      entity: 'TagLink',
    );
  }

  Future<void> unlink({
    required String tagId,
    required String entityType,
    required String entityId,
  }) {
    return (_db.delete(_db.tagLinks)
          ..where((t) => t.tagId.equals(tagId))
          ..where((t) => t.entityType.equals(entityType))
          ..where((t) => t.entityId.equals(entityId)))
        .go()
        .then((_) {});
  }

  /// All tags attached to one entity.
  Future<List<Tag>> tagsForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final query = _db.select(_db.tagLinks).join([
      innerJoin(
        _db.tags,
        _db.tags.id.equalsExp(_db.tagLinks.tagId),
      ),
    ])
      ..where(_db.tagLinks.entityType.equals(entityType))
      ..where(_db.tagLinks.entityId.equals(entityId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.tags)).toList();
  }

  /// Ids of every entity of [entityType] carrying the tag [tagId].
  Future<List<String>> entityIdsForTag(String tagId, String entityType) async {
    final rows = await (_db.select(_db.tagLinks)
          ..where((t) => t.tagId.equals(tagId))
          ..where((t) => t.entityType.equals(entityType)))
        .get();
    return rows.map((row) => row.entityId).toList();
  }
}
