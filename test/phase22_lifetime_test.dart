import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_history_repository.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/belongings/domain/item_lifetime_service.dart';

/// Phase 22: Complete Item Lifetime Record and export.
void main() {
  late KeepItDatabase db;
  late ItemLifetimeService service;
  late BelongingRepository belongings;

  setUp(() async {
    db = KeepItDatabase(NativeDatabase.memory());
    service = ItemLifetimeService(db);
    belongings = BelongingRepository(db);
  });

  tearDown(() => db.close());

  group('Phase 22 Item Lifetime Record', () {
    test('generates record for basic item', () async {
      final id = await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final record = await service.getLifetimeRecord(id);
      expect(record.belonging.id, id);
      expect(record.belonging.name, 'Hammer');
      // Creating an item auto-logs a "created" history entry.
      expect(record.history.length, 1);
      expect(record.history.first.eventType, 'created');
      expect(record.warranties, isEmpty);
      expect(record.serviceRecords, isEmpty);
      expect(record.warrantyClaims, isEmpty);
      expect(record.purchase, isNull);
      expect(record.documents, isEmpty);
    });

    test('throws StateError for non-existent item', () async {
      expect(
        () => service.getLifetimeRecord('non-existent-id'),
        throwsStateError,
      );
    });

    test('includes acquisition and disposition data', () async {
      final id = await belongings.create(
        BelongingsCompanion(
          name: const Value('Laptop'),
          acquisitionType: const Value('purchased'),
          acquisitionDate: Value(DateTime(2023, 1, 15)),
        ),
      );

      final record = await service.getLifetimeRecord(id);
      expect(record.belonging.acquisitionType, 'purchased');
      expect(record.belonging.acquisitionDate, DateTime(2023, 1, 15));
    });

    test('exportToJson produces valid JSON', () async {
      final id = await belongings.create(
        BelongingsCompanion(
          name: const Value('Drill'),
          brand: const Value('DeWalt'),
          valueCents: const Value(15000),
        ),
      );

      final jsonString = await service.exportToJson(id);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(decoded['belonging']['name'], 'Drill');
      expect(decoded['belonging']['brand'], 'DeWalt');
      expect(decoded['belonging']['valueCents'], 15000);
      expect(decoded['history'], isA<List>());
      expect(decoded['warranties'], isA<List>());
      expect(decoded['serviceRecords'], isA<List>());
      expect(decoded['exportedAt'], isNotNull);
    });

    test('record includes history entries', () async {
      final id = await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      // Log a history entry.
      final historyRepo = BelongingHistoryRepository(db);
      await historyRepo.log(
        belongingId: id,
        eventType: 'created',
        title: 'Item created',
      );

      final record = await service.getLifetimeRecord(id);
      // Auto-created entry + manual entry = 2.
      expect(record.history.length, 2);
      expect(
        record.history.any((h) => h.eventType == 'created'),
        isTrue,
      );
    });

    test('record is read-only', () async {
      final id = await belongings.create(
        const BelongingsCompanion(name: Value('Hammer')),
      );

      final before = await belongings.getById(id);
      await service.getLifetimeRecord(id);
      final after = await belongings.getById(id);

      expect(after?.name, before?.name);
      expect(after?.updatedAt, before?.updatedAt);
    });
  });
}
