import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/features/purchases/presentation/purchase_form_screen.dart';
import 'package:uuid/uuid.dart';

/// Widget tests for the purchase form: validation and the duplicate-warning
/// dialog. Navigation is stubbed via callbacks so no router is needed.
void main() {
  late KeepItDatabase db;
  late PurchaseRepository purchases;

  setUp(() {
    db = openInMemoryDatabase();
    purchases = PurchaseRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildForm({VoidCallback? onSaved}) {
    return MaterialApp(
      home: PurchaseFormScreen(
        purchaseRepository: purchases,
        database: db,
        onSaved: onSaved ?? () {},
      ),
    );
  }

  Future<void> fillField(WidgetTester tester, int index, String text) async {
    await tester.enterText(find.byType(TextFormField).at(index), text);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final saveButton = find.byKey(const Key('savePurchaseButton'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();
  }

  testWidgets('requires a purchase name before saving', (tester) async {
    var saved = false;
    await tester.pumpWidget(buildForm(onSaved: () => saved = true));
    await tester.pumpAndSettle();

    // Leave the name empty, fill another field, then save.
    await fillField(tester, 2, 'Walmart');
    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('Give your purchase a name'), findsOneWidget);
    expect(saved, isFalse);
  });

  testWidgets('shows the duplicate dialog when a similar purchase exists',
      (tester) async {
    final now = DateTime.now();
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(const Uuid().v4()),
            productName: 'Air Fryer',
            store: const Value('Walmart'),
            priceCents: const Value(7999),
            purchaseDate: Value(now),
          ),
        );

    var saved = false;
    await tester.pumpWidget(buildForm(onSaved: () => saved = true));
    await tester.pumpAndSettle();

    await fillField(tester, 0, 'Air Fryer');
    await fillField(tester, 2, 'Walmart');
    await fillField(tester, 3, '79.99');
    await tapSave(tester);
    await tester.pumpAndSettle();

    // The duplicate warning appears; nothing was saved yet.
    expect(find.text('Possible duplicate'), findsOneWidget);
    expect(find.text('Create anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(saved, isFalse);

    // "Create anyway" persists the new purchase.
    await tester.tap(find.widgetWithText(FilledButton, 'Create anyway'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);

    final all = await purchases.getAll();
    expect(all.length, 2);
  });

  testWidgets('saves directly when no duplicate exists', (tester) async {
    var saved = false;
    await tester.pumpWidget(buildForm(onSaved: () => saved = true));
    await tester.pumpAndSettle();

    await fillField(tester, 0, 'Espresso Machine');
    await fillField(tester, 2, 'Breville Store');
    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('Possible duplicate'), findsNothing);
    expect(saved, isTrue);

    final all = await purchases.getAll();
    expect(all.length, 1);
    expect(all.first.productName, 'Espresso Machine');
  });
}
