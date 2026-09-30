import 'package:drift/drift.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_history_repository.dart';
import '../../../core/database/repositories/household_member_repository.dart';

/// Domain service for household/family sharing (Phase 15).
///
/// Local-only by default. Privacy is Private unless explicitly shared.
/// No cloud sync — sharing is via local export (future Phase 17).
class HouseholdService {
  HouseholdService(KeepItDatabase db)
    : _members = HouseholdMemberRepository(db),
      _history = BelongingHistoryRepository(db),
      _db = db;

  final HouseholdMemberRepository _members;
  final BelongingHistoryRepository _history;
  final KeepItDatabase _db;

  /// Adds a household member.
  Future<String> addMember({
    required String name,
    String? relationship,
    String? colorHex,
    String? notes,
  }) {
    return _members.create(
      name: name,
      relationship: relationship,
      colorHex: colorHex,
      notes: notes,
    );
  }

  /// Lists all household members.
  Future<List<HouseholdMember>> members() => _members.getAll();

  /// Removes a household member.
  Future<void> removeMember(String memberId) => _members.delete(memberId);

  /// Sets the privacy level for a belonging.
  ///
  /// Defaults to 'private'. Must be 'private' or 'shared'.
  Future<void> setPrivacy(String belongingId, String level) async {
    if (!PrivacyLevel.isValid(level)) {
      throw ArgumentError('Invalid privacy level: $level');
    }
    await (_db.update(
      _db.belongings,
    )..where((b) => b.id.equals(belongingId))).write(
      BelongingsCompanion(
        privacyLevel: Value(level),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _history.log(
      belongingId: belongingId,
      eventType: 'privacy_changed',
      title: 'Privacy set to ${PrivacyLevel.label(level)}',
    );
  }

  /// Assigns a belonging to a household member (owner).
  Future<void> assignOwner(String belongingId, String? memberId) async {
    if (memberId != null) {
      final member = await _members.getById(memberId);
      if (member == null) {
        throw ArgumentError('Household member not found: $memberId');
      }
    }

    await (_db.update(
      _db.belongings,
    )..where((b) => b.id.equals(belongingId))).write(
      BelongingsCompanion(
        ownerMemberId: Value(memberId),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final member = memberId == null ? null : await _members.getById(memberId);
    await _history.log(
      belongingId: belongingId,
      eventType: 'owner_changed',
      title: member == null ? 'Owner cleared' : 'Assigned to ${member.name}',
    );
  }

  /// Gets belongings for a specific member.
  Future<List<Belonging>> belongingsForMember(String memberId) {
    return _members.belongingsForMember(memberId);
  }

  /// Gets all shared belongings (privacy = 'shared').
  Future<List<Belonging>> sharedBelongings() {
    return (_db.select(
      _db.belongings,
    )..where((b) => b.privacyLevel.equals(PrivacyLevel.shared))).get();
  }

  /// Gets all private belongings (privacy = 'private').
  Future<List<Belonging>> privateBelongings() {
    return (_db.select(
      _db.belongings,
    )..where((b) => b.privacyLevel.equals(PrivacyLevel.private))).get();
  }
}
