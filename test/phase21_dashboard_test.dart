import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/household/domain/household_dashboard_service.dart';
import 'package:keepit/features/household/domain/household_service.dart';

/// Phase 21: Household Command Center.
void main() {
  late KeepItDatabase db;
  late HouseholdDashboardService dashboard;
  late HouseholdService household;
  late BelongingRepository belongings;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    dashboard = HouseholdDashboardService(db);
    household = HouseholdService(db);
    belongings = BelongingRepository(db);
  });

  tearDown(() => db.close());

  group('Phase 21 Household Command Center', () {
    test('empty household returns zero dashboard', () async {
      final data = await dashboard.getDashboard();
      expect(data.totalItems, 0);
      expect(data.totalValueCents, 0);
      expect(data.memberSummaries, isEmpty);
      expect(data.privacyBreakdown.sharedCount, 0);
      expect(data.privacyBreakdown.privateCount, 0);
    });

    test('member summaries include item counts and values', () async {
      final memberId = await household.addMember(name: 'Alice');

      final itemId = 'item-${DateTime.now().microsecondsSinceEpoch}';
      await belongings.create(
        BelongingsCompanion(
          id: Value(itemId),
          name: const Value('Hammer'),
          valueCents: const Value(2500),
        ),
      );
      await household.assignOwner(itemId, memberId);

      final data = await dashboard.getDashboard();
      expect(data.memberSummaries.length, 1);

      final summary = data.memberSummaries.first;
      expect(summary.member.name, 'Alice');
      expect(summary.itemCount, 1);
      expect(summary.totalValueCents, 2500);
      expect(summary.totalValueDollars, 25.0);
    });

    test('privacy breakdown counts shared vs private', () async {
      final item1 = 'item1-${DateTime.now().microsecondsSinceEpoch}';
      final item2 = 'item2-${DateTime.now().microsecondsSinceEpoch}';

      await belongings.create(
        BelongingsCompanion(
          id: Value(item1),
          name: const Value('Hammer'),
        ),
      );
      await belongings.create(
        BelongingsCompanion(
          id: Value(item2),
          name: const Value('Screwdriver'),
        ),
      );

      await household.setPrivacy(item1, 'shared');
      // item2 stays private (default).

      final data = await dashboard.getDashboard();
      expect(data.privacyBreakdown.sharedCount, 1);
      expect(data.privacyBreakdown.privateCount, 1);
      expect(data.privacyBreakdown.total, 2);
    });

    test('unassigned count tracks items without owner', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );
      await belongings.create(
        const BelongingsCompanion(name: Value('Wrench')),
      );

      final memberId = await household.addMember(name: 'Bob');

      final items = await belongings.getAll();
      await household.assignOwner(items.first.id, memberId);
      // Second item remains unassigned.

      final data = await dashboard.getDashboard();
      expect(data.privacyBreakdown.unassignedCount, 1);
    });

    test('location summaries are sorted by item count', () async {
      // Create two locations.
      final loc1 = 'loc1-${DateTime.now().microsecondsSinceEpoch}';
      final loc2 = 'loc2-${DateTime.now().microsecondsSinceEpoch}';
      await db.into(db.locations).insert(
            LocationsCompanion(id: Value(loc1), name: const Value('Garage')),
          );
      await db.into(db.locations).insert(
            LocationsCompanion(id: Value(loc2), name: const Value('Attic')),
          );

      // Put 2 items in Garage, 1 in Attic.
      await belongings.create(
        BelongingsCompanion(
          name: const Value('Hammer'),
          locationId: Value(loc1),
        ),
      );
      await belongings.create(
        BelongingsCompanion(
          name: const Value('Wrench'),
          locationId: Value(loc1),
        ),
      );
      await belongings.create(
        BelongingsCompanion(
          name: const Value('Ladder'),
          locationId: Value(loc2),
        ),
      );

      final data = await dashboard.getDashboard();
      expect(data.locationSummaries.length, 2);
      // Garage should come first (2 items vs 1).
      expect(data.locationSummaries.first.location.name, 'Garage');
      expect(data.locationSummaries.first.itemCount, 2);
    });

    test('total value aggregates all items', () async {
      await belongings.create(
        const BelongingsCompanion(
          name: Value('Hammer'),
          valueCents: Value(2500),
        ),
      );
      await belongings.create(
        const BelongingsCompanion(
          name: Value('Drill'),
          valueCents: Value(15000),
        ),
      );

      final data = await dashboard.getDashboard();
      expect(data.totalItems, 2);
      expect(data.totalValueCents, 17500);
      expect(data.totalValueDollars, 175.0);
    });

    test('dashboard is read-only', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final before = await belongings.getAll();
      await dashboard.getDashboard();
      final after = await belongings.getAll();

      expect(after.length, before.length);
    });
  });
}
