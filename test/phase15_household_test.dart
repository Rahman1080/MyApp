import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/household_member_repository.dart';
import 'package:keepit/features/household/domain/household_service.dart';

/// Phase 15: Household/Family Sharing (local-only, privacy Private by default).
void main() {
  late KeepItDatabase db;
  late HouseholdService service;
  late BelongingRepository belongings;

  setUp(() {
    db = KeepItDatabase(NativeDatabase.memory());
    service = HouseholdService(db);
    belongings = BelongingRepository(db);
  });

  tearDown(() => db.close());

  group('Phase 15 Household Sharing', () {
    test('schema is v9 with household_members table', () async {
      expect(db.schemaVersion, 9);
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('household_members'));
    });

    test('addMember creates household member', () async {
      final id = await service.addMember(
        name: 'Alice',
        relationship: 'spouse',
        colorHex: '#FF5722',
      );
      expect(id, isNotEmpty);

      final members = await service.members();
      expect(members, hasLength(1));
      expect(members.single.name, 'Alice');
      expect(members.single.relationship, 'spouse');
    });

    test('belongings default to private privacy', () async {
      final id = await belongings.create(
        const BelongingsCompanion(name: Value('Lamp')),
      );
      final item = await belongings.getById(id);
      expect(item, isNotNull);
      expect(item!.privacyLevel, PrivacyLevel.private);
      expect(item.ownerMemberId, isNull);
    });

    test('setPrivacy changes privacy level', () async {
      final id = await belongings.create(
        const BelongingsCompanion(name: Value('Chair')),
      );
      await service.setPrivacy(id, PrivacyLevel.shared);

      final item = await belongings.getById(id);
      expect(item!.privacyLevel, PrivacyLevel.shared);
    });

    test('setPrivacy rejects invalid level', () async {
      final id = await belongings.create(
        const BelongingsCompanion(name: Value('Table')),
      );
      expect(() => service.setPrivacy(id, 'public'), throwsArgumentError);
    });

    test('assignOwner links belonging to member', () async {
      final memberId = await service.addMember(name: 'Bob');
      final itemId = await belongings.create(
        const BelongingsCompanion(name: Value('Bike')),
      );

      await service.assignOwner(itemId, memberId);

      final item = await belongings.getById(itemId);
      expect(item!.ownerMemberId, memberId);

      final owned = await service.belongingsForMember(memberId);
      expect(owned, hasLength(1));
      expect(owned.single.id, itemId);
    });

    test('assignOwner rejects unknown member', () async {
      final itemId = await belongings.create(
        const BelongingsCompanion(name: Value('Desk')),
      );
      expect(
        () => service.assignOwner(itemId, 'nonexistent'),
        throwsArgumentError,
      );
    });

    test('assignOwner with null clears owner', () async {
      final memberId = await service.addMember(name: 'Carol');
      final itemId = await belongings.create(
        const BelongingsCompanion(name: Value('Sofa')),
      );
      await service.assignOwner(itemId, memberId);
      await service.assignOwner(itemId, null);

      final item = await belongings.getById(itemId);
      expect(item!.ownerMemberId, isNull);
    });

    test('sharedBelongings returns only shared items', () async {
      final id1 = await belongings.create(
        const BelongingsCompanion(name: Value('Shared Item')),
      );
      await belongings.create(
        const BelongingsCompanion(name: Value('Private Item')),
      );
      await service.setPrivacy(id1, PrivacyLevel.shared);

      final shared = await service.sharedBelongings();
      expect(shared, hasLength(1));
      expect(shared.single.id, id1);

      final private = await service.privateBelongings();
      expect(private, hasLength(1));
    });

    test('removeMember clears owner references', () async {
      final memberId = await service.addMember(name: 'Dave');
      final itemId = await belongings.create(
        const BelongingsCompanion(name: Value('Tool')),
      );
      await service.assignOwner(itemId, memberId);
      await service.removeMember(memberId);

      final item = await belongings.getById(itemId);
      // FK ON DELETE SET NULL clears the reference.
      expect(item!.ownerMemberId, isNull);
    });

    test('privacy level labels resolve', () {
      expect(PrivacyLevel.label('private'), 'Private');
      expect(PrivacyLevel.label('shared'), 'Shared');
    });
  });
}
