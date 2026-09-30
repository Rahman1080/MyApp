import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/household_member_repository.dart';
import '../../../core/database/repositories/location_repository.dart';

/// Summary for a single household member.
class MemberSummary {
  const MemberSummary({
    required this.member,
    required this.itemCount,
    required this.totalValueCents,
    required this.sharedCount,
    required this.privateCount,
  });

  final HouseholdMember member;
  final int itemCount;
  final int totalValueCents;
  final int sharedCount;
  final int privateCount;

  double get totalValueDollars => totalValueCents / 100;
}

/// Privacy breakdown across the household.
class PrivacyBreakdown {
  const PrivacyBreakdown({
    required this.sharedCount,
    required this.privateCount,
    required this.unassignedCount,
  });

  final int sharedCount;
  final int privateCount;
  final int unassignedCount;

  int get total => sharedCount + privateCount;
}

/// Location summary with item counts.
class LocationSummary {
  const LocationSummary({
    required this.location,
    required this.itemCount,
    required this.totalValueCents,
  });

  final Location location;
  final int itemCount;
  final int totalValueCents;

  double get totalValueDollars => totalValueCents / 100;
}

/// Complete household dashboard data.
class HouseholdDashboard {
  const HouseholdDashboard({
    required this.memberSummaries,
    required this.privacyBreakdown,
    required this.locationSummaries,
    required this.totalItems,
    required this.totalValueCents,
    required this.generatedAt,
  });

  final List<MemberSummary> memberSummaries;
  final PrivacyBreakdown privacyBreakdown;
  final List<LocationSummary> locationSummaries;
  final int totalItems;
  final int totalValueCents;
  final DateTime generatedAt;

  double get totalValueDollars => totalValueCents / 100;
}

/// Household Command Center (Phase 21).
///
/// Aggregates household data into a dashboard view:
/// - Per-member summaries (items, value, shared/private breakdown)
/// - Privacy breakdown (shared vs private)
/// - Per-location summaries
/// - Totals
///
/// Read-only: never modifies data. All calculations are done
/// in-memory from repository queries.
class HouseholdDashboardService {
  HouseholdDashboardService(KeepItDatabase db)
    : _belongings = BelongingRepository(db),
      _members = HouseholdMemberRepository(db),
      _locations = LocationRepository(db);

  final BelongingRepository _belongings;
  final HouseholdMemberRepository _members;
  final LocationRepository _locations;

  /// Generates the complete household dashboard.
  Future<HouseholdDashboard> getDashboard() async {
    final members = await _members.getAll();
    final items = await _belongings.getAll();
    final locations = await _locations.getAll();

    // Per-member summaries.
    final memberSummaries = <MemberSummary>[];
    for (final member in members) {
      final memberItems =
          items.where((i) => i.ownerMemberId == member.id).toList();
      final totalValue = memberItems.fold<int>(
        0,
        (sum, i) => sum + (i.valueCents ?? 0),
      );
      final shared =
          memberItems.where((i) => i.privacyLevel == 'shared').length;
      final private = memberItems.length - shared;

      memberSummaries.add(MemberSummary(
        member: member,
        itemCount: memberItems.length,
        totalValueCents: totalValue,
        sharedCount: shared,
        privateCount: private,
      ));
    }

    // Privacy breakdown.
    final sharedCount =
        items.where((i) => i.privacyLevel == 'shared').length;
    final privateCount =
        items.where((i) => i.privacyLevel != 'shared').length;
    final unassignedCount =
        items.where((i) => i.ownerMemberId == null).length;

    // Per-location summaries.
    final locationSummaries = <LocationSummary>[];
    for (final location in locations) {
      final locationItems =
          items.where((i) => i.locationId == location.id).toList();
      final totalValue = locationItems.fold<int>(
        0,
        (sum, i) => sum + (i.valueCents ?? 0),
      );
      locationSummaries.add(LocationSummary(
        location: location,
        itemCount: locationItems.length,
        totalValueCents: totalValue,
      ));
    }

    // Sort locations by item count (descending).
    locationSummaries.sort((a, b) => b.itemCount.compareTo(a.itemCount));

    // Totals.
    final totalValue = items.fold<int>(
      0,
      (sum, i) => sum + (i.valueCents ?? 0),
    );

    return HouseholdDashboard(
      memberSummaries: memberSummaries,
      privacyBreakdown: PrivacyBreakdown(
        sharedCount: sharedCount,
        privateCount: privateCount,
        unassignedCount: unassignedCount,
      ),
      locationSummaries: locationSummaries,
      totalItems: items.length,
      totalValueCents: totalValue,
      generatedAt: DateTime.now(),
    );
  }
}
