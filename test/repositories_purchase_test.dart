import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/repositories.dart';
import 'package:uuid/uuid.dart';

/// Repository CRUD, streams, not-found errors and constraint translation
/// for the purchase-side entities.
void main() {
  late KeepItDatabase db;
  late PurchaseRepository purchases;
  late ProductRepository products;
  late ReceiptRepository receipts;
  late WarrantyRepository warranties;
  late ReturnDeadlineRepository returnDeadlines;
  late RefundRepository refunds;

  setUp(() {
    db = openInMemoryDatabase();
    purchases = PurchaseRepository(db);
    products = ProductRepository(db);
    receipts = ReceiptRepository(db);
    warranties = WarrantyRepository(db);
    returnDeadlines = ReturnDeadlineRepository(db);
    refunds = RefundRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  String newId() => const Uuid().v4();

  Future<String> insertPurchase({String name = 'Air Fryer'}) async {
    final id = newId();
    await purchases.create(
      PurchasesCompanion.insert(
        id: Value(id),
        productName: name,
        priceCents: const Value(7999),
      ),
    );
    return id;
  }

  group('PurchaseRepository', () {
    test('create -> getById -> update -> delete', () async {
      final id = await insertPurchase();
      final fetched = await purchases.requireById(id);
      expect(fetched.productName, 'Air Fryer');
      expect(fetched.status, 'active');

      await purchases.update(
        id,
        const PurchasesCompanion(status: Value('refunded')),
      );
      expect((await purchases.requireById(id)).status, 'refunded');

      await purchases.delete(id);
      expect(await purchases.getById(id), isNull);
    });

    test('requireById throws RecordNotFoundException', () async {
      expect(
        () => purchases.requireById('missing'),
        throwsA(isA<RecordNotFoundException>()),
      );
    });

    test('update/delete of missing id throws RecordNotFoundException', () async {
      expect(
        () => purchases.update('missing', const PurchasesCompanion()),
        throwsA(isA<RecordNotFoundException>()),
      );
      expect(
        () => purchases.delete('missing'),
        throwsA(isA<RecordNotFoundException>()),
      );
    });

    test('watchAll streams inserts', () async {
      // Each fresh subscription immediately emits the current table state.
      expect(await purchases.watchAll().first, isEmpty);

      await insertPurchase(name: 'Kettle');

      final after = await purchases.watchAll().first;
      expect(after.map((p) => p.productName), contains('Kettle'));
    });

    test('deleting a purchase cascades to products and receipts', () async {
      final purchaseId = await insertPurchase();
      await products.create(
        ProductsCompanion.insert(
          id: Value(newId()),
          purchaseId: purchaseId,
          name: 'Heating element',
        ),
      );
      await receipts.create(
        ReceiptsCompanion.insert(
          id: Value(newId()),
          purchaseId: purchaseId,
          totalCents: const Value(8599),
        ),
      );

      await purchases.delete(purchaseId);

      expect(await products.getByPurchase(purchaseId), isEmpty);
      expect(await receipts.getByPurchaseId(purchaseId), isNull);
    });
  });

  group('ProductRepository', () {
    test('product with unknown purchaseId violates FK', () async {
      expect(
        () => products.create(
          ProductsCompanion.insert(
            id: Value(newId()),
            purchaseId: 'no-such-purchase',
            name: 'Widget',
          ),
        ),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });

    test('watchByPurchase streams the line items', () async {
      final purchaseId = await insertPurchase();
      await products.create(
        ProductsCompanion.insert(
          id: Value(newId()),
          purchaseId: purchaseId,
          name: 'Item A',
        ),
      );
      final items = await products.watchByPurchase(purchaseId).first;
      expect(items.map((p) => p.name), ['Item A']);
    });
  });

  group('ReceiptRepository', () {
    test('second receipt for the same purchase is rejected', () async {
      final purchaseId = await insertPurchase();
      await receipts.create(
        ReceiptsCompanion.insert(id: Value(newId()), purchaseId: purchaseId),
      );
      expect(
        () => receipts.create(
          ReceiptsCompanion.insert(
              id: Value(newId()), purchaseId: purchaseId),
        ),
        throwsA(isA<RecordAlreadyExistsException>()),
      );
    });

    test('watchByPurchase emits the receipt', () async {
      final purchaseId = await insertPurchase();
      expect(await receipts.watchByPurchase(purchaseId).first, isNull);

      await receipts.create(
        ReceiptsCompanion.insert(
          id: Value(newId()),
          purchaseId: purchaseId,
          store: const Value('Walmart'),
        ),
      );
      final emitted = await receipts.watchByPurchase(purchaseId).first;
      expect(emitted?.store, 'Walmart');
    });
  });

  group('WarrantyRepository', () {
    test('getByPurchaseId and unique constraint', () async {
      final purchaseId = await insertPurchase();
      final warrantyId = newId();
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(warrantyId),
          purchaseId: purchaseId,
          expirationDate: Value(DateTime(2027, 5, 1)),
        ),
      );
      expect((await warranties.getByPurchaseId(purchaseId))?.id, warrantyId);

      expect(
        () => warranties.create(
          WarrantiesCompanion.insert(
              id: Value(newId()), purchaseId: purchaseId),
        ),
        throwsA(isA<RecordAlreadyExistsException>()),
      );
    });

    test('expiringOnOrBefore lists soon-expiring warranties', () async {
      final p1 = await insertPurchase(name: 'TV');
      final p2 = await insertPurchase(name: 'Fridge');
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(newId()),
          purchaseId: p1,
          expirationDate: Value(DateTime(2026, 10, 5)),
        ),
      );
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(newId()),
          purchaseId: p2,
          expirationDate: Value(DateTime(2028, 1, 1)),
        ),
      );

      final expiring =
          await warranties.expiringOnOrBefore(DateTime(2026, 12, 31));
      expect(expiring.map((w) => w.purchaseId), [p1]);
    });
  });

  group('ReturnDeadlineRepository', () {
    test('dueOnOrBefore orders by deadline', () async {
      final p1 = await insertPurchase(name: 'Shoes');
      final p2 = await insertPurchase(name: 'Jacket');
      await returnDeadlines.create(
        ReturnDeadlinesCompanion.insert(
          id: Value(newId()),
          purchaseId: p1,
          deadlineDate: DateTime(2026, 10, 2),
        ),
      );
      await returnDeadlines.create(
        ReturnDeadlinesCompanion.insert(
          id: Value(newId()),
          purchaseId: p2,
          deadlineDate: DateTime(2026, 10, 1),
        ),
      );

      final due =
          await returnDeadlines.dueOnOrBefore(DateTime(2026, 10, 31));
      expect(due.map((d) => d.purchaseId), [p2, p1]);
    });
  });

  group('RefundRepository', () {
    test('create and watchByStatus', () async {
      final purchaseId = await insertPurchase();
      await refunds.create(
        RefundsCompanion.insert(
          id: Value(newId()),
          purchaseId: purchaseId,
          amountCents: const Value(7999),
        ),
      );

      final pending = await refunds.watchByStatus('requested').first;
      expect(pending.map((r) => r.purchaseId), [purchaseId]);

      await refunds.update(
        (await refunds.getByPurchaseId(purchaseId))!.id,
        const RefundsCompanion(status: Value('received')),
      );
      expect(await refunds.watchByStatus('requested').first, isEmpty);
      expect(
        (await refunds.watchByStatus('received').first).map((r) => r.amountCents),
        [7999],
      );
    });
  });
}
