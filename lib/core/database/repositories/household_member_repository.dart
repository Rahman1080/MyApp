import 'package:drift/drift.dart';

import '../keepit_database.dart';
import '../tables.dart';

/// Repository for household members (Phase 15).
///
/// Local-only family/household member management. No cloud sync.
class HouseholdMemberRepository {
  HouseholdMemberRepository(this._db);

  final KeepItDatabase _db;

  /// Creates a new household member.
  Future<String> create({
    required String name,
    String? relationship,
    String? colorHex,
    String? notes,
  }) async {
    final id = newRecordId();
    await _db
        .into(_db.householdMembers)
        .insert(
          HouseholdMembersCompanion(
            id: Value(id),
            name: Value(name),
            relationship: Value(relationship),
            colorHex: Value(colorHex),
            notes: Value(notes),
          ),
        );
    return id;
  }

  /// Gets a member by ID.
  Future<HouseholdMember?> getById(String id) {
    return (_db.select(
      _db.householdMembers,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
  }

  /// Lists all household members, ordered by name.
  Future<List<HouseholdMember>> getAll() {
    return (_db.select(
      _db.householdMembers,
    )..orderBy([(m) => OrderingTerm(expression: m.name)])).get();
  }

  /// Updates a household member.
  Future<void> update(String id, HouseholdMembersCompanion companion) {
    return (_db.update(_db.householdMembers)..where((m) => m.id.equals(id)))
        .write(companion.copyWith(updatedAt: Value(DateTime.now())));
  }

  /// Deletes a household member. Belongings referencing this member
  /// will have their owner_member_id set to NULL (via FK).
  Future<void> delete(String id) {
    return (_db.delete(
      _db.householdMembers,
    )..where((m) => m.id.equals(id))).go();
  }

  /// Gets belongings owned by a specific member.
  Future<List<Belonging>> belongingsForMember(String memberId) {
    return (_db.select(
      _db.belongings,
    )..where((b) => b.ownerMemberId.equals(memberId))).get();
  }
}

/// Privacy levels for belongings (Phase 15).
///
/// - `private`: Only visible to the device owner (default).
/// - `shared`: Visible to household members (when sharing is enabled).
class PrivacyLevel {
  PrivacyLevel._();

  static const String private = 'private';
  static const String shared = 'shared';

  static const List<String> values = [private, shared];

  /// Human-readable label for a privacy level.
  static String label(String level) {
    switch (level) {
      case private:
        return 'Private';
      case shared:
        return 'Shared';
      default:
        return level;
    }
  }

  /// Whether the level is valid.
  static bool isValid(String level) => values.contains(level);
}
