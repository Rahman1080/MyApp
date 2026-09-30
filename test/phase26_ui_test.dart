import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/category_repository.dart';
import 'package:keepit/core/database/repositories/household_member_repository.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/features/ask/domain/ask_service.dart';
import 'package:keepit/features/ask/presentation/ask_screen.dart';
import 'package:keepit/features/belongings/domain/item_lifetime_service.dart';
import 'package:keepit/features/belongings/presentation/lifetime_record_screen.dart';
import 'package:keepit/features/household/domain/household_dashboard_service.dart';
import 'package:keepit/features/household/presentation/household_dashboard_screen.dart';
import 'package:keepit/features/organize/domain/smart_organization_service.dart';
import 'package:keepit/features/organize/presentation/organize_screen.dart';
import 'package:keepit/features/sync/domain/sync_service.dart';
import 'package:keepit/features/sync/presentation/sync_screen.dart';

/// Widget tests for the Phase 16–22 UI screens (the "missing UI" fix).
///
/// Verifies each screen renders, loads its data, and responds to the
/// primary user action — without touching real device storage or network.
void main() {
  late KeepItDatabase db;
  late BelongingRepository belongings;
  late LocationRepository locations;
  late CategoryRepository categories;
  late HouseholdMemberRepository members;

  setUp(() async {
    db = openInMemoryDatabase();
    belongings = BelongingRepository(db);
    locations = LocationRepository(db);
    categories = CategoryRepository(db);
    members = HouseholdMemberRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  group('AskScreen (Phase 16 UI)', () {
    testWidgets('asks a question and shows a grounded answer',
        (tester) async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Power Drill')),
      );
      final service = AskKeepitService(db);

      await tester.pumpWidget(wrap(AskScreen(askService: service)));
      await tester.pumpAndSettle();

      // Empty state shows example questions.
      expect(find.text('Where is my drill?'), findsOneWidget);

      // Ask a question.
      await tester.enterText(
        find.byType(TextField),
        'where is drill',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // The user's question and the grounded answer both appear.
      expect(find.text('where is drill'), findsOneWidget);
      expect(find.textContaining('Power Drill'), findsWidgets);
    });
  });

  group('OrganizeScreen (Phase 18 UI)', () {
    testWidgets('shows suggestions and dismisses one', (tester) async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Orphan Item')),
      );
      final service = SmartOrganizationService(db);

      await tester.pumpWidget(
        wrap(OrganizeScreen(
          organizationService: service,
          belongingRepository: belongings,
          locationRepository: locations,
          categoryRepository: categories,
        )),
      );
      await tester.pumpAndSettle();

      // The missing-location suggestion appears.
      expect(find.textContaining('have no location'), findsOneWidget);
      // The item appears in the suggestion cards (one chip per suggestion).
      expect(find.text('Orphan Item'), findsWidgets);

      // Dismiss the missing-location suggestion specifically.
      final locationCard = find.ancestor(
        of: find.textContaining('have no location'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(
          of: locationCard,
          matching: find.text('Dismiss'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows all-good state when nothing to suggest',
        (tester) async {
      final service = SmartOrganizationService(db);

      await tester.pumpWidget(
        wrap(OrganizeScreen(
          organizationService: service,
          belongingRepository: belongings,
          locationRepository: locations,
          categoryRepository: categories,
        )),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Everything looks organized!'),
        findsOneWidget,
      );
    });
  });

  group('HouseholdDashboardScreen (Phase 21 UI)', () {
    testWidgets('renders totals, privacy, members and locations',
        (tester) async {
      final memberId = await members.create(name: 'Alex');
      await belongings.create(
        BelongingsCompanion(
          name: const Value('Shared Bike'),
          privacyLevel: const Value('shared'),
          ownerMemberId: Value(memberId),
          valueCents: const Value(15000),
        ),
      );
      final service = HouseholdDashboardService(db);

      await tester.pumpWidget(
        wrap(HouseholdDashboardScreen(dashboardService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Household Command Center'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Shared Bike').hitTestable(), findsNothing);
      // Member card shows item count and value.
      expect(find.text('1 items'), findsWidgets);
      expect(find.textContaining('150'), findsWidgets);
    });
  });

  group('LifetimeRecordScreen (Phase 22 UI)', () {
    testWidgets('renders all record sections', (tester) async {
      final id = await belongings.create(
        const BelongingsCompanion(
          name: Value('Vintage Camera'),
          brand: Value('Canon'),
        ),
      );
      final service = ItemLifetimeService(db);

      await tester.pumpWidget(
        wrap(LifetimeRecordScreen(
          lifetimeService: service,
          belongingId: id,
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lifetime Record'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Canon'), findsOneWidget);
      expect(find.text('Acquisition & Disposition'), findsOneWidget);
      expect(find.textContaining('History'), findsOneWidget);
      expect(find.textContaining('Warranties'), findsOneWidget);
      expect(find.textContaining('Service'), findsOneWidget);
      // Scroll down to reveal the remaining sections (ListView is lazy).
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Purchase'), findsOneWidget);
      expect(find.textContaining('Documents'), findsOneWidget);
      // Export button is available.
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });
  });

  group('SyncScreen (Phase 17 UI)', () {
    testWidgets('shows device ID and export/import actions', (tester) async {
      final service = SyncService(db, FileSyncProvider({}), 'test-device-1');

      await tester.pumpWidget(
        wrap(SyncScreen(database: db, syncService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('test-device-1'), findsOneWidget);
      expect(find.text('Export to another device'), findsOneWidget);
      expect(find.text('Import from another device'), findsOneWidget);
    });
  });
}
