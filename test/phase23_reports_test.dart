import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/reports/domain/advanced_report_service.dart';
import 'package:keepit/features/reports/domain/report_filter.dart';

/// Phase 23: Advanced reporting with filters and CSV export.
void main() {
  late KeepItDatabase db;
  late AdvancedReportService service;
  late BelongingRepository belongings;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    service = AdvancedReportService(db);
    belongings = BelongingRepository(db);

    // Create test categories (FK constraint).
    await db.into(db.categories).insert(
      const CategoriesCompanion(
        id: Value('cat-tools'),
        name: Value('Tools'),
      ),
    );
    await db.into(db.categories).insert(
      const CategoriesCompanion(
        id: Value('cat-books'),
        name: Value('Books'),
      ),
    );
  });

  tearDown(() => db.close());

  Future<String> createItem({
    required String name,
    String? categoryId,
    String? locationId,
    String? condition,
    int? valueCents,
    String? privacyLevel,
    String? archiveState,
    DateTime? acquisitionDate,
    String? brand,
  }) {
    return belongings.create(
      BelongingsCompanion(
        name: Value(name),
        categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
        locationId: locationId == null ? const Value.absent() : Value(locationId),
        condition: condition == null ? const Value.absent() : Value(condition),
        valueCents: valueCents == null ? const Value.absent() : Value(valueCents),
        privacyLevel: privacyLevel == null ? const Value.absent() : Value(privacyLevel),
        archiveState: archiveState == null ? const Value.absent() : Value(archiveState),
        acquisitionDate: acquisitionDate == null ? const Value.absent() : Value(acquisitionDate),
        brand: brand == null ? const Value.absent() : Value(brand),
      ),
    );
  }

  group('Phase 23 Advanced Reporting', () {
    test('empty filter returns all items', () async {
      await createItem(name: 'Hammer');
      await createItem(name: 'Wrench');

      final results = await service.filterBelongings(const ReportFilter());
      expect(results.length, 2);
    });

    test('category filter', () async {
      await createItem(name: 'Hammer', categoryId: 'cat-tools');
      await createItem(name: 'Book', categoryId: 'cat-books');

      final results = await service.filterBelongings(
        const ReportFilter(categoryIds: {'cat-tools'}),
      );
      expect(results.length, 1);
      expect(results.first.name, 'Hammer');
    });

    test('value range filter', () async {
      await createItem(name: 'Cheap', valueCents: 100);
      await createItem(name: 'Expensive', valueCents: 10000);

      final results = await service.filterBelongings(
        const ReportFilter(minValueCents: 1000, maxValueCents: 20000),
      );
      expect(results.length, 1);
      expect(results.first.name, 'Expensive');
    });

    test('privacy level filter', () async {
      await createItem(name: 'Private Item', privacyLevel: 'private');
      await createItem(name: 'Shared Item', privacyLevel: 'shared');

      final results = await service.filterBelongings(
        const ReportFilter(privacyLevels: {'shared'}),
      );
      expect(results.length, 1);
      expect(results.first.name, 'Shared Item');
    });

    test('text search filter', () async {
      await createItem(name: 'Hammer', brand: 'DeWalt');
      await createItem(name: 'Screwdriver', brand: 'Stanley');

      final results = await service.filterBelongings(
        const ReportFilter(searchText: 'dewalt'),
      );
      expect(results.length, 1);
      expect(results.first.name, 'Hammer');
    });

    test('acquisition date range filter', () async {
      await createItem(
        name: 'Old',
        acquisitionDate: DateTime(2020, 1, 1),
      );
      await createItem(
        name: 'New',
        acquisitionDate: DateTime(2024, 6, 15),
      );

      final results = await service.filterBelongings(
        ReportFilter(acquiredAfter: DateTime(2023, 1, 1)),
      );
      expect(results.length, 1);
      expect(results.first.name, 'New');
    });

    test('multiple filters combine with AND', () async {
      await createItem(
        name: 'Expensive Tool',
        categoryId: 'cat-tools',
        valueCents: 5000,
      );
      await createItem(
        name: 'Cheap Tool',
        categoryId: 'cat-tools',
        valueCents: 100,
      );
      await createItem(
        name: 'Expensive Book',
        categoryId: 'cat-books',
        valueCents: 5000,
      );

      final results = await service.filterBelongings(
        const ReportFilter(
          categoryIds: {'cat-tools'},
          minValueCents: 1000,
        ),
      );
      expect(results.length, 1);
      expect(results.first.name, 'Expensive Tool');
    });

    test('CSV export generates valid output', () async {
      await createItem(name: 'Hammer', brand: 'DeWalt', valueCents: 2500);

      final csv = await service.exportCsv(const ReportFilter());
      expect(csv, contains('Name'));
      expect(csv, contains('Hammer'));
      expect(csv, contains('DeWalt'));
      expect(csv, contains('2500'));
    });

    test('CSV escapes special characters', () async {
      await createItem(name: 'Hammer, "Deluxe" Edition');

      final csv = await service.exportCsv(const ReportFilter());
      // Field with comma and quotes should be quoted with doubled quotes.
      expect(csv, contains('"Hammer, ""Deluxe"" Edition"'));
    });

    test('CSV export respects filters', () async {
      await createItem(name: 'Hammer', categoryId: 'cat-tools');
      await createItem(name: 'Book', categoryId: 'cat-books');

      final csv = await service.exportCsv(
        const ReportFilter(categoryIds: {'cat-tools'}),
      );
      expect(csv, contains('Hammer'));
      expect(csv, isNot(contains('Book')));
    });
  });
}
