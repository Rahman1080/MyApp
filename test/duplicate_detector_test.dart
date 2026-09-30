import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/shared/services/duplicate_detector.dart';
import 'package:uuid/uuid.dart';

void main() {
  late KeepItDatabase db;
  late PurchaseRepository purchases;
  late DuplicateDetector detector;

  setUp(() {
    db = openInMemoryDatabase();
    purchases = PurchaseRepository(db);
    detector = DuplicateDetector(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Purchase> insertPurchase({
    required String name,
    String? store,
    int? priceCents,
    DateTime? date,
  }) async {
    final id = const Uuid().v4();
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(id),
            productName: name,
            store: Value(store),
            priceCents: Value(priceCents),
            purchaseDate: Value(date),
          ),
        );
    return purchases.requireById(id);
  }

  test('exact duplicate is found with a high score', () async {
    final original = await insertPurchase(
      name: 'Sony WH-1000XM5',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );
    final candidate = await insertPurchase(
      name: 'Sony WH-1000XM5',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );

    final matches = await detector.findCandidates(candidate);

    expect(matches, hasLength(1));
    expect(matches.first.purchase.id, original.id);
    expect(matches.first.score, greaterThan(0.9));
  });

  test('near-duplicate (reworded name, close price/date) is found', () async {
    final original = await insertPurchase(
      name: 'Sony WH-1000XM5 Wireless Headphones',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );
    final candidate = await insertPurchase(
      name: 'WH-1000XM5 Sony headphones',
      store: 'best buy', // different casing still matches
      priceCents: 40200, // within $1 + 1%
      date: DateTime(2026, 9, 24), // within 7 days
    );

    final matches = await detector.findCandidates(candidate);

    expect(matches.map((m) => m.purchase.id), contains(original.id));
  });

  test('different product is not flagged', () async {
    await insertPurchase(
      name: 'Air Fryer',
      store: 'Walmart',
      priceCents: 7999,
      date: DateTime(2026, 9, 20),
    );
    final candidate = await insertPurchase(
      name: 'Running Shoes',
      store: 'Walmart',
      priceCents: 7999,
      date: DateTime(2026, 9, 20),
    );

    expect(await detector.findCandidates(candidate), isEmpty);
  });

  test('same name but different store and price is not flagged', () async {
    await insertPurchase(
      name: 'AA Batteries 24-pack',
      store: 'Costco',
      priceCents: 1299,
      date: DateTime(2026, 9, 20),
    );
    final candidate = await insertPurchase(
      name: 'AA Batteries 24-pack',
      store: 'Target',
      priceCents: 1899,
      date: DateTime(2026, 9, 21),
    );

    expect(await detector.findCandidates(candidate), isEmpty);
  });

  test('same name but purchase far apart in time is not flagged', () async {
    await insertPurchase(
      name: 'AA Batteries 24-pack',
      store: 'Costco',
      priceCents: 1299,
      date: DateTime(2026, 1, 5),
    );
    final candidate = await insertPurchase(
      name: 'AA Batteries 24-pack',
      store: 'Costco',
      priceCents: 1299,
      date: DateTime(2026, 9, 20),
    );

    expect(await detector.findCandidates(candidate), isEmpty);
  });

  test('candidates are ranked by score, best first', () async {
    final close = await insertPurchase(
      name: 'Sony WH-1000XM5',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );
    await insertPurchase(
      name: 'Sony WH-1000XM5 headphones black',
      store: 'Best Buy',
      priceCents: 39500,
      date: DateTime(2026, 9, 25),
    );
    final candidate = await insertPurchase(
      name: 'Sony WH-1000XM5',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );

    final matches = await detector.findCandidates(candidate);

    expect(matches, hasLength(2));
    expect(matches.first.purchase.id, close.id);
    expect(
      matches.first.score,
      greaterThanOrEqualTo(matches.last.score),
    );
  });

  test('detection never deletes or merges — originals stay intact', () async {
    final original = await insertPurchase(
      name: 'Sony WH-1000XM5',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );
    final candidate = await insertPurchase(
      name: 'Sony WH-1000XM5',
      store: 'Best Buy',
      priceCents: 39999,
      date: DateTime(2026, 9, 20),
    );

    final matches = await detector.findCandidates(candidate);
    expect(matches, isNotEmpty);

    // Both rows still exist afterwards.
    expect(await purchases.getById(original.id), isNotNull);
    expect(await purchases.getById(candidate.id), isNotNull);
    final all = await (db.select(db.purchases)).get();
    expect(all, hasLength(2));
  });
}
