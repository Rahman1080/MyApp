import 'package:drift/native.dart';

/// Thrown when a record expected to exist cannot be found.
class RecordNotFoundException implements Exception {
  RecordNotFoundException(this.entity, this.id);

  final String entity;
  final String id;

  @override
  String toString() => '$entity with id "$id" was not found.';
}

/// Thrown when an insert/update/delete violates a foreign key, e.g. linking
/// a purchase to a category that does not exist.
class ReferentialIntegrityException implements Exception {
  ReferentialIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'Referential integrity violated: $message';
}

/// Thrown when a uniqueness constraint is violated, e.g. creating a second
/// tag with the same name or a second receipt for one purchase.
class RecordAlreadyExistsException implements Exception {
  RecordAlreadyExistsException(this.message);

  final String message;

  @override
  String toString() => 'Duplicate record: $message';
}

/// SQLite extended result codes (https://www.sqlite.org/rescode.html).
const int _sqliteConstraintForeignKey = 787;
const int _sqliteConstraintUnique = 2067;

/// Runs a database write, translating raw SQLite constraint failures into
/// typed exceptions. Repositories use this for every insert/update/delete
/// so callers never have to parse SQLite error strings.
Future<T> guardConstraints<T>(
  Future<T> Function() action, {
  required String entity,
}) async {
  try {
    return await action();
  } on SqliteException catch (e) {
    if (e.extendedResultCode == _sqliteConstraintForeignKey) {
      throw ReferentialIntegrityException(
        'Cannot save $entity: a linked record does not exist.',
      );
    }
    if (e.extendedResultCode == _sqliteConstraintUnique) {
      throw RecordAlreadyExistsException(
        'Cannot save $entity: an identical record already exists.',
      );
    }
    rethrow;
  }
}
