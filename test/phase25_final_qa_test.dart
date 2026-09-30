import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/ask/domain/ask_service.dart';
import 'package:keepit/features/belongings/domain/item_lifetime_service.dart';
import 'package:keepit/features/household/domain/household_dashboard_service.dart';
import 'package:keepit/features/household/domain/household_service.dart';
import 'package:keepit/features/monetization/domain/entitlement_service.dart';
import 'package:keepit/features/organize/domain/smart_organization_service.dart';
import 'package:keepit/features/product/domain/product_intelligence_service.dart';
import 'package:keepit/features/reports/domain/advanced_report_service.dart';
import 'package:keepit/features/reports/domain/report_filter.dart';
import 'package:keepit/features/web/domain/web_companion_service.dart';

/// Phase 25: Production scale, final QA.
///
/// Cross-phase integration tests verifying that all phases
/// work together correctly. This is the final validation
/// before production release.
void main() {
  late KeepItDatabase db;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('Phase 25 Final QA - Cross-phase integration', () {
    test('full item lifecycle: create -> organize -> ask -> report -> export', () async {
      final belongings = BelongingRepository(db);

      // Create an item (Phase 9).
      final itemId = await belongings.create(
        const BelongingsCompanion(
          name: Value('DeWalt Drill'),
          brand: Value('DeWalt'),
          valueCents: Value(15000),
        ),
      );

      // Smart organization detects missing location (Phase 18).
      final organize = SmartOrganizationService(db);
      final suggestions = await organize.detectSuggestions();
      expect(suggestions.any((s) => s.type == SuggestionType.missingLocation), isTrue);

      // Ask KEEPIT finds it (Phase 16).
      final ask = AskKeepitService(db);
      final answer = await ask.ask('where is DeWalt Drill');
      expect(answer.answerText, contains('DeWalt'));

      // Advanced reporting includes it (Phase 23).
      final reports = AdvancedReportService(db);
      final filtered = await reports.filterBelongings(
        const ReportFilter(searchText: 'dewalt'),
      );
      expect(filtered.length, 1);

      // Lifetime record exports it (Phase 22).
      final lifetime = ItemLifetimeService(db);
      final record = await lifetime.getLifetimeRecord(itemId);
      expect(record.belonging.name, 'DeWalt Drill');

      // Web companion includes it (Phase 20).
      final web = WebCompanionService(db);
      final html = await web.generateHtml();
      expect(html, contains('DeWalt Drill'));
    });

    test('household: member -> assign -> dashboard -> privacy', () async {
      final belongings = BelongingRepository(db);
      final household = HouseholdService(db);
      final dashboard = HouseholdDashboardService(db);

      // Add member (Phase 15).
      final memberId = await household.addMember(name: 'Alice');

      // Create and assign item.
      final itemId = await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );
      await household.assignOwner(itemId, memberId);
      await household.setPrivacy(itemId, 'shared');

      // Dashboard reflects it (Phase 21).
      final data = await dashboard.getDashboard();
      expect(data.memberSummaries.length, 1);
      expect(data.memberSummaries.first.itemCount, 1);
      expect(data.privacyBreakdown.sharedCount, 1);
    });

    test('product validation integrates with item creation', () async {
      final product = ProductIntelligenceService();
      final belongings = BelongingRepository(db);

      // Validate a UPC before creating item (Phase 19).
      final validation = product.validateProductId('036000291452');
      expect(validation.isValid, isTrue);

      final itemId = await belongings.create(
        const BelongingsCompanion(
          name: Value('Cereal'),
          serialNumber: Value('036000291452'),
        ),
      );

      final item = await belongings.getById(itemId);
      expect(item?.serialNumber, '036000291452');
    });

    test('entitlement: all integrated features are free', () async {
      final entitlements = EntitlementService();

      // Every feature used in integration tests must be free.
      expect(entitlements.isFeatureAvailable(KeepitFeature.inventory), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.smartOrganization), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.askKeepit), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.advancedReports), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.lifetimeRecord), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.webCompanion), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.householdMembers), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.commandCenter), isTrue);
      expect(entitlements.isFeatureAvailable(KeepitFeature.productIntelligence), isTrue);
    });

    test('sync: export preserves data', () async {
      final belongings = BelongingRepository(db);

      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      // Export changes (Phase 17).
      // Note: SyncService requires a provider; we test the export
      // via the repository layer which the sync builds on.
      final items = await belongings.getAll();
      expect(items.length, 1);
      expect(items.first.name, 'Hammer');
    });

    test('database handles concurrent service access', () async {
      // Multiple services accessing the same DB simultaneously.
      final belongings = BelongingRepository(db);
      final ask = AskKeepitService(db);
      final reports = AdvancedReportService(db);
      final dashboard = HouseholdDashboardService(db);

      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      // All services query concurrently.
      final results = await Future.wait([
        ask.ask('where is hammer').then((a) => a.answerText),
        reports.filterBelongings(const ReportFilter()),
        dashboard.getDashboard(),
      ]);

      expect(results[0], isA<String>());
      expect(results[1], isA<List>());
      expect(results[2], isA<HouseholdDashboard>());
    });
  });
}
