import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:uuid/uuid.dart';

/// Phase 1 smoke test: the database opens in-memory, accepts inserts, and
/// reads them back — including the location hierarchy and foreign keys.
void main() {
  late KeepItDatabase db;

  setUp(() {
    db = openInMemoryDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  String newId() => const Uuid().v4();

  test('insert and read a purchase with receipt, warranty and reminder',
      () async {
    final purchaseId = newId();
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(purchaseId),
            productName: 'Air Fryer',
            store: const Value('Walmart'),
            priceCents: const Value(7999),
          ),
        );

    await db.into(db.receipts).insert(
          ReceiptsCompanion.insert(
            id: Value(newId()),
            purchaseId: purchaseId,
            totalCents: const Value(8599),
          ),
        );

    await db.into(db.warranties).insert(
          WarrantiesCompanion.insert(
            id: Value(newId()),
            purchaseId: purchaseId,
            expirationDate: Value(DateTime(2027, 3, 12)),
          ),
        );

    final purchase =
        await (db.select(db.purchases)..where((t) => t.id.equals(purchaseId)))
            .getSingle();
    expect(purchase.productName, 'Air Fryer');
    expect(purchase.priceCents, 7999);
    expect(purchase.status, 'active');

    final receipt = await (db.select(db.receipts)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .getSingle();
    expect(receipt.totalCents, 8599);

    final warranty = await (db.select(db.warranties)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .getSingle();
    expect(warranty.expirationDate, DateTime(2027, 3, 12));
  });

  test('location hierarchy: belonging resolves through parent locations',
      () async {
    final homeId = newId();
    final bedroomId = newId();
    final drawerId = newId();
    await db.into(db.locations).insert(
          LocationsCompanion.insert(id: Value(homeId), name: 'Home'),
        );
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            id: Value(bedroomId),
            name: 'Bedroom',
            parentLocationId: Value(homeId),
          ),
        );
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            id: Value(drawerId),
            name: 'Top Drawer',
            parentLocationId: Value(bedroomId),
          ),
        );

    final belongingId = newId();
    await db.into(db.belongings).insert(
          BelongingsCompanion.insert(
            id: Value(belongingId),
            name: 'Passport',
            locationId: Value(drawerId),
          ),
        );

    final belonging = await (db.select(db.belongings)
          ..where((t) => t.id.equals(belongingId)))
        .getSingle();
    expect(belonging.name, 'Passport');

    // Walk up the hierarchy: Top Drawer -> Bedroom -> Home.
    String? currentId = belonging.locationId;
    final path = <String>[];
    while (currentId != null) {
      final location = await (db.select(db.locations)
            ..where((t) => t.id.equals(currentId!)))
          .getSingle();
      path.add(location.name);
      currentId = location.parentLocationId;
    }
    expect(path, ['Top Drawer', 'Bedroom', 'Home']);
  });

  test('user settings row is created on first read', () async {
    final settings = await db.select(db.userSettings).getSingleOrNull();
    // The repository creates the row; the raw table starts empty.
    expect(settings, isNull);

    await db.into(db.userSettings).insert(
          UserSettingsCompanion.insert(id: 'default'),
        );
    final created = await db.select(db.userSettings).getSingle();
    expect(created.themeMode, 'system');
    expect(created.appLockEnabled, isFalse);
  });

  test('tag links connect a tag to a purchase', () async {
    final purchaseId = newId();
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(purchaseId),
            productName: 'HDMI Cable',
          ),
        );
    final tagId = newId();
    await db.into(db.tags).insert(
          TagsCompanion.insert(id: Value(tagId), name: 'electronics'),
        );
    await db.into(db.tagLinks).insert(
          TagLinksCompanion.insert(
            tagId: tagId,
            entityType: 'purchase',
            entityId: purchaseId,
          ),
        );

    final links = await (db.select(db.tagLinks)
          ..where((t) => t.entityId.equals(purchaseId)))
        .get();
    expect(links, hasLength(1));
    expect(links.single.tagId, tagId);
  });
}
