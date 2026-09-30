import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/shared/services/global_search.dart';
import 'package:uuid/uuid.dart';

void main() {
  late KeepItDatabase db;
  late GlobalSearchService search;

  setUp(() {
    db = openInMemoryDatabase();
    search = GlobalSearchService(db);
  });

  tearDown(() async {
    await db.close();
  });

  String newId() => const Uuid().v4();

  Future<void> seed() async {
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(newId()),
            productName: 'Sony WH-1000XM5',
            store: const Value('Best Buy'),
            notes: const Value('noise cancelling headphones'),
          ),
        );
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(newId()),
            productName: 'Air Fryer',
            store: const Value('Walmart'),
          ),
        );
    final homeId = newId();
    await db.into(db.locations).insert(
          LocationsCompanion.insert(id: Value(homeId), name: 'Home'),
        );
    await db.into(db.belongings).insert(
          BelongingsCompanion.insert(
            id: Value(newId()),
            name: 'Sony Camera',
            brand: const Value('Sony'),
            locationId: Value(homeId),
          ),
        );
    await db.into(db.deadlines).insert(
          DeadlinesCompanion.insert(
            id: Value(newId()),
            title: 'Sony warranty registration',
            dueDate: DateTime(2026, 10, 15),
          ),
        );
    await db.into(db.documents).insert(
          DocumentsCompanion.insert(
            id: Value(newId()),
            title: 'Apartment lease',
            filePath: '/tmp/lease.pdf',
          ),
        );
  }

  test('empty or blank query returns empty results', () async {
    await seed();
    expect((await search.search('')).isEmpty, isTrue);
    expect((await search.search('   ')).isEmpty, isTrue);
  });

  test('finds matches across multiple entity types', () async {
    await seed();
    final results = await search.search('sony');

    expect(results.purchases, hasLength(1));
    expect(results.purchases.first.productName, 'Sony WH-1000XM5');
    expect(results.belongings, hasLength(1));
    expect(results.belongings.first.name, 'Sony Camera');
    expect(results.deadlines, hasLength(1));
    expect(results.locations, isEmpty);
    expect(results.documents, isEmpty);
    expect(results.totalCount, 3);
  });

  test('search is case-insensitive', () async {
    await seed();
    final lower = await search.search('sony');
    final upper = await search.search('SONY');
    expect(upper.totalCount, lower.totalCount);
    expect(upper.totalCount, greaterThan(0));
  });

  test('matches notes fields', () async {
    await seed();
    final results = await search.search('noise cancelling');
    expect(results.purchases, hasLength(1));
  });

  test('exact name match ranks before substring match', () async {
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(newId()),
            productName: 'Drill',
          ),
        );
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(newId()),
            productName: 'Cordless Drill Driver Kit',
          ),
        );

    final results = await search.search('drill');
    expect(results.purchases, hasLength(2));
    expect(results.purchases.first.productName, 'Drill');
  });

  test('limitPerEntity caps results', () async {
    for (var i = 0; i < 10; i++) {
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: Value(newId()),
              productName: 'Lamp model $i',
            ),
          );
    }
    final results = await search.search('lamp', limitPerEntity: 3);
    expect(results.purchases, hasLength(3));
  });

  test('no matches returns empty results', () async {
    await seed();
    final results = await search.search('xylophone');
    expect(results.isEmpty, isTrue);
    expect(results.totalCount, 0);
  });
}
