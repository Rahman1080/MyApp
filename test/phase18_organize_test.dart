import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/organize/domain/smart_organization_service.dart';

/// Phase 18: Smart Organization (detect → suggest → review → confirm).
void main() {
  late KeepItDatabase db;
  late SmartOrganizationService organize;
  late BelongingRepository belongings;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    organize = SmartOrganizationService(db);
    belongings = BelongingRepository(db);
  });

  tearDown(() => db.close());

  group('Phase 18 Smart Organization', () {
    test('detects items with missing location', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final suggestions = await organize.detectSuggestions();
      final missingLocation = suggestions.where(
        (s) => s.type == SuggestionType.missingLocation,
      );
      expect(missingLocation, isNotEmpty);
      expect(missingLocation.first.belongingIds.length, 1);
    });

    test('detects items with missing category', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final suggestions = await organize.detectSuggestions();
      final missingCategory = suggestions.where(
        (s) => s.type == SuggestionType.missingCategory,
      );
      expect(missingCategory, isNotEmpty);
    });

    test('detects items with missing value', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final suggestions = await organize.detectSuggestions();
      final missingValue = suggestions.where(
        (s) => s.type == SuggestionType.missingValue,
      );
      expect(missingValue, isNotEmpty);
    });

    test('detects possible duplicates', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );
      await belongings.create(
        const BelongingsCompanion(name: Value('hammer')),
      );

      final suggestions = await organize.detectSuggestions();
      final duplicates = suggestions.where(
        (s) => s.type == SuggestionType.possibleDuplicate,
      );
      expect(duplicates, isNotEmpty);
      expect(duplicates.first.belongingIds.length, 2);
    });

    test('returns empty list when inventory is well-organized', () async {
      // Create a real location first.
      final locId = 'loc-${DateTime.now().microsecondsSinceEpoch}';
      await db.into(db.locations).insert(
            LocationsCompanion(
              id: Value(locId),
              name: const Value('Garage'),
            ),
          );

      // Create a well-organized item (has location and value;
      // category is optional for this test).
      await db.into(db.belongings).insert(
            BelongingsCompanion(
              id: Value('item-${DateTime.now().microsecondsSinceEpoch}'),
              name: const Value('Hammer'),
              locationId: Value(locId),
              valueCents: const Value(2500),
            ),
          );

      final suggestions = await organize.detectSuggestions();
      // Should have no missing-location or missing-value suggestions.
      final critical = suggestions.where((s) =>
          s.type == SuggestionType.missingLocation ||
          s.type == SuggestionType.missingValue);
      expect(critical, isEmpty);
    });

    test('suggestion starts as pending', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final suggestions = await organize.detectSuggestions();
      expect(suggestions.first.status, SuggestionStatus.pending);
    });

    test('cannot apply suggestion that is not accepted', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final suggestions = await organize.detectSuggestions();
      final suggestion = suggestions.first;

      expect(
        () => organize.applySuggestion(suggestion, {}),
        throwsStateError,
      );
    });

    test('applySuggestion updates items after acceptance', () async {
      final itemId = newItemId();
      await belongings.create(
        BelongingsCompanion(
          id: Value(itemId),
          name: const Value('Hammer'),
        ),
      );

      final suggestions = await organize.detectSuggestions();
      final missingLocation = suggestions.firstWhere(
        (s) => s.type == SuggestionType.missingLocation,
      );

      // Accept the suggestion.
      final accepted = missingLocation.copyWith(
        status: SuggestionStatus.accepted,
      );

      // Create a real location and apply.
      final locId = 'loc-${DateTime.now().microsecondsSinceEpoch}';
      await db.into(db.locations).insert(
            LocationsCompanion(
              id: Value(locId),
              name: const Value('Garage'),
            ),
          );
      await organize.applySuggestion(accepted, {'locationId': locId});

      final updated = await belongings.getById(itemId);
      expect(updated!.locationId, locId);
    });

    test('detection does not modify data', () async {
      await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final before = await belongings.getAll();
      await organize.detectSuggestions();
      final after = await belongings.getAll();

      expect(after.length, before.length);
      expect(after.first.locationId, before.first.locationId);
    });
  });
}

String newItemId() => 'item-${DateTime.now().microsecondsSinceEpoch}';
String newLocId() => 'loc-${DateTime.now().microsecondsSinceEpoch}';
