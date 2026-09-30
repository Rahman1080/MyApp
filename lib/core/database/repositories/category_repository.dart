import 'package:drift/drift.dart';

import '../keepit_database.dart';
import 'exceptions.dart';

/// Categories — built-in and user-defined. Names are unique.
class CategoryRepository {
  CategoryRepository(this._db);

  final KeepItDatabase _db;

  Future<Category?> getById(String id) {
    return (_db.select(_db.categories)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Category> requireById(String id) async {
    final category = await getById(id);
    if (category == null) throw RecordNotFoundException('Category', id);
    return category;
  }

  Stream<List<Category>> watchAll() {
    return ((_db.select(_db.categories)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch());
  }

  Future<List<Category>> getAll() {
    return (_db.select(_db.categories)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<void> create(CategoriesCompanion companion) async {
    await guardConstraints(
      () => _db.into(_db.categories).insert(companion),
      entity: 'Category',
    );
  }

  Future<void> update(String id, CategoriesCompanion companion) async {
    await requireById(id);
    await guardConstraints(
      () => (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        companion.copyWith(updatedAt: Value(DateTime.now())),
      ),
      entity: 'Category',
    );
  }

  Future<void> delete(String id) async {
    await requireById(id);
    await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
  }
}
