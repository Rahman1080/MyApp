import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/belonging_meta.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_history_repository.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/features/belongings/domain/lifecycle_service.dart';

KeepItDatabase _openDb() => KeepItDatabase(NativeDatabase.memory());

Future<String> _addBelonging(
  BelongingRepository repo, {
  required String name,
  int? valueCents,
}) async {
  return repo.create(
    BelongingsCompanion.insert(
      name: name,
      valueCents: valueCents != null ? Value(valueCents) : const Value.absent(),
    ),
  );
}

void main() {
  late KeepItDatabase db;
  late BelongingRepository belongings;
  late BelongingHistoryRepository history;
  late LifecycleService lifecycle;

  setUp(() {
    db = _openDb();
    belongings = BelongingRepository(db);
    history = BelongingHistoryRepository(db);
    lifecycle = LifecycleService(db);
  });

  tearDown(() => db.close());

  group('Phase 13 Item Lifecycle', () {
    test('schema is v9 with lifecycle columns', () async {
      expect(db.schemaVersion, 9);
      final cols = await db.customSelect("PRAGMA table_info(belongings)").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      for (final col in [
        'acquisition_type',
        'acquisition_date',
        'disposition_date',
        'disposition_price_cents',
        'disposition_currency_code',
        'disposition_recipient',
        'disposition_method',
        'disposition_notes',
      ]) {
        expect(names, contains(col), reason: 'missing column $col');
      }
    });

    test('recordAcquisition stores type and date', () async {
      final id = await _addBelonging(belongings, name: 'Bike');
      final date = DateTime(2023, 3, 15);
      await lifecycle.recordAcquisition(
        belongingId: id,
        acquisitionType: BelongingAcquisitionType.purchased,
        acquisitionDate: date,
      );

      final item = await belongings.getById(id);
      expect(item?.acquisitionType, BelongingAcquisitionType.purchased);
      expect(item?.acquisitionDate, date);

      final entries = await history.historyFor(id);
      expect(
        entries.any((e) => e.title.contains('Acquired (purchased)')),
        isTrue,
      );
    });

    test('markSold records sale details and history', () async {
      final id = await _addBelonging(
        belongings,
        name: 'Camera',
        valueCents: 50000,
      );
      await lifecycle.markSold(
        belongingId: id,
        details: const DispositionDetails(
          priceCents: 35000,
          currencyCode: 'USD',
          recipient: 'Alex',
          notes: 'Sold on marketplace',
        ),
      );

      final item = await belongings.getById(id);
      expect(item?.archiveState, BelongingArchiveState.sold);
      expect(item?.dispositionPriceCents, 35000);
      expect(item?.dispositionCurrencyCode, 'USD');
      expect(item?.dispositionRecipient, 'Alex');
      expect(item?.dispositionMethod, BelongingDispositionMethod.sold);
      expect(item?.dispositionNotes, 'Sold on marketplace');
      expect(item?.dispositionDate, isNotNull);

      final entries = await history.historyFor(id);
      final soldEntry = entries.firstWhere(
        (e) => e.eventType == BelongingHistoryEvent.sold,
      );
      expect(soldEntry.title, contains('Alex'));
    });

    test('markDonated records recipient', () async {
      final id = await _addBelonging(belongings, name: 'Jacket');
      await lifecycle.markDonated(
        belongingId: id,
        details: const DispositionDetails(
          recipient: 'Goodwill',
          notes: 'Tax receipt filed',
        ),
      );

      final item = await belongings.getById(id);
      expect(item?.archiveState, BelongingArchiveState.donated);
      expect(item?.dispositionRecipient, 'Goodwill');
      expect(item?.dispositionMethod, BelongingDispositionMethod.donated);
    });

    test('markDisposed records method', () async {
      final id = await _addBelonging(belongings, name: 'Broken chair');
      await lifecycle.markDisposed(
        belongingId: id,
        details: const DispositionDetails(
          method: BelongingDispositionMethod.recycled,
        ),
      );

      final item = await belongings.getById(id);
      expect(item?.archiveState, BelongingArchiveState.disposed);
      expect(item?.dispositionMethod, BelongingDispositionMethod.recycled);
    });

    test('summarize computes ownership duration', () async {
      final id = await _addBelonging(belongings, name: 'Desk');
      final acquisitionDate = DateTime.now().subtract(
        const Duration(days: 400),
      );
      await lifecycle.recordAcquisition(
        belongingId: id,
        acquisitionType: BelongingAcquisitionType.purchased,
        acquisitionDate: acquisitionDate,
      );

      final item = await belongings.getById(id);
      final summary = lifecycle.summarize(item!);
      expect(summary.isRetired, isFalse);
      expect(summary.durationLabel, contains('year'));
      expect(summary.acquisitionType, BelongingAcquisitionType.purchased);
    });

    test('summarize computes value retention for sold items', () async {
      final id = await _addBelonging(
        belongings,
        name: 'Phone',
        valueCents: 80000,
      );
      await lifecycle.markSold(
        belongingId: id,
        details: const DispositionDetails(
          priceCents: 40000,
          currencyCode: 'USD',
        ),
      );

      final item = await belongings.getById(id);
      final summary = lifecycle.summarize(item!);
      expect(summary.isRetired, isTrue);
      expect(summary.valueRetentionPercent, 50.0);
    });

    test('value retention is null when values missing', () async {
      final id = await _addBelonging(belongings, name: 'Mystery box');
      final item = await belongings.getById(id);
      final summary = lifecycle.summarize(item!);
      expect(summary.valueRetentionPercent, isNull);
    });

    test('acquisition type labels resolve', () {
      expect(
        BelongingAcquisitionType.labelOf(BelongingAcquisitionType.gifted),
        'Gifted',
      );
      expect(BelongingAcquisitionType.labelOf(null), 'Not set');
      expect(BelongingAcquisitionType.labelOf('bogus'), 'Not set');
    });

    test('disposition method labels resolve', () {
      expect(
        BelongingDispositionMethod.labelOf(BelongingDispositionMethod.recycled),
        'Recycled',
      );
      expect(BelongingDispositionMethod.labelOf(null), 'Not set');
    });
  });
}
