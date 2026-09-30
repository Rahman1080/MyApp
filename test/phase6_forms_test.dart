import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_history_repository.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/category_repository.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/core/database/repositories/place_repository.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/core/database/repositories/tag_repository.dart';
import 'package:keepit/features/belongings/presentation/belonging_form_screen.dart';
import 'package:keepit/features/locations/presentation/location_form_screen.dart';
import 'package:keepit/shared/services/location_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

/// Widget tests for the Phase 6 forms: belonging validation and the
/// cycle-proof location parent picker. Navigation is stubbed via callbacks
/// so no router is needed.
void main() {
  late KeepItDatabase db;
  late BelongingRepository belongings;
  late LocationRepository locations;
  late PlaceRepository places;
  late CategoryRepository categories;
  late PurchaseRepository purchases;
  late TagRepository tags;
  late BelongingHistoryRepository history;
  late LocationService locationService;

  setUp(() {
    db = openInMemoryDatabase();
    belongings = BelongingRepository(db);
    locations = LocationRepository(db);
    places = PlaceRepository(db);
    categories = CategoryRepository(db);
    purchases = PurchaseRepository(db);
    tags = TagRepository(db);
    history = BelongingHistoryRepository(db);
    locationService = LocationService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createLocation(String name, [String? parentId]) async {
    final id = 'loc-$name';
    await locations.create(
      LocationsCompanion(
        id: Value(id),
        name: Value(name),
        parentLocationId: Value(parentId),
      ),
    );
    return id;
  }

  group('BelongingFormScreen', () {
    Widget buildForm({VoidCallback? onSaved, String? belongingId}) {
      return MaterialApp(
        home: BelongingFormScreen(
          belongingRepository: belongings,
          categoryRepository: categories,
          locationRepository: locations,
          purchaseRepository: purchases,
          tagRepository: tags,
          historyRepository: history,
          belongingId: belongingId,
          onSaved: onSaved ?? () {},
        ),
      );
    }

    testWidgets('requires a belonging name before saving', (tester) async {
      var saved = false;
      await tester.pumpWidget(buildForm(onSaved: () => saved = true));
      await tester.pumpAndSettle();

      final saveButton = find.byKey(const Key('saveBelongingButton'));
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Give your belonging a name.'), findsOneWidget);
      expect(saved, isFalse);
    });

    testWidgets('saves when a name is provided', (tester) async {
      var saved = false;
      await tester.pumpWidget(buildForm(onSaved: () => saved = true));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('belonging-name')), 'Passport');
      await tester.pump();

      final saveButton = find.byKey(const Key('saveBelongingButton'));
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(saved, isTrue);
      final all = await belongings.search('Passport');
      expect(all, hasLength(1));
    });

    testWidgets('saves an optional value with a currency', (tester) async {
      var saved = false;
      await tester.pumpWidget(buildForm(onSaved: () => saved = true));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('belonging-name')), 'Camera');
      // The value field sits below the fold in the lengthened Phase 9 form,
      // and ListView builds sliver children lazily. Unfocus first: a focused
      // field pins the scroll position, then jump to the end.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final scrollState =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('belonging-value')), '249.99');
      await tester.pump();

      final saveButton = find.byKey(const Key('saveBelongingButton'));
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(saved, isTrue);
      final all = await belongings.search('Camera');
      expect(all, hasLength(1));
      expect(all.single.valueCents, 24999);
      expect(all.single.currencyCode, isNotNull);
      expect(all.single.currencyCode!.length, 3);
    });

    testWidgets('rejects a non-numeric value', (tester) async {
      var saved = false;
      await tester.pumpWidget(buildForm(onSaved: () => saved = true));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('belonging-name')), 'Lamp');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final scrollState =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('belonging-value')), 'abc');
      await tester.pump();

      final saveButton = find.byKey(const Key('saveBelongingButton'));
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid amount, e.g. 49.99'), findsOneWidget);
      expect(saved, isFalse);
    });
  });

  group('LocationFormScreen parent picker', () {
    Widget buildForm({String? locationId}) {
      return MaterialApp(
        home: LocationFormScreen(
          locationRepository: locations,
          locationService: locationService,
          placeRepository: places,
          locationId: locationId,
          onSaved: () {},
        ),
      );
    }

    testWidgets('excludes the location itself and its descendants',
        (tester) async {
      final homeId = await createLocation('Home');
      final bedroomId = await createLocation('Bedroom', homeId);
      await createLocation('Drawer', bedroomId);

      // Editing "Bedroom": "Home" is a legal parent, but "Bedroom" itself
      // and its descendant "Drawer" must not be offered.
      await tester.pumpWidget(buildForm(locationId: bedroomId));
      await tester.pumpAndSettle();

      // Open the parent dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();

      expect(find.text('Top level'), findsOneWidget);
      // "Home" appears twice: as the pre-filled selected parent of Bedroom
      // and as a menu item — both are correct.
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Home > Bedroom'), findsNothing);
      expect(find.text('Home > Bedroom > Drawer'), findsNothing);
    });

    testWidgets('new locations may nest under anything', (tester) async {
      final homeId = await createLocation('Home');
      await createLocation('Bedroom', homeId);

      await tester.pumpWidget(buildForm());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Home > Bedroom'), findsOneWidget);
    });
  });
}
