import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/deadline_repository.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/core/database/repositories/return_deadline_repository.dart';
import 'package:keepit/core/database/repositories/warranty_repository.dart';
import 'package:keepit/features/home/presentation/home_screen.dart';
import 'package:uuid/uuid.dart';

/// Widget tests for the home dashboard: empty state for new users and
/// data-driven sections for users with records.
void main() {
  late KeepItDatabase db;

  setUp(() {
    db = openInMemoryDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  String newId() => const Uuid().v4();

  HomeScreen buildScreen() {
    return HomeScreen(
      purchaseRepository: PurchaseRepository(db),
      warrantyRepository: WarrantyRepository(db),
      returnDeadlineRepository: ReturnDeadlineRepository(db),
      deadlineRepository: DeadlineRepository(db),
    );
  }

  Future<void> seedPurchase({
    required String name,
    String? store,
    int? priceCents,
    DateTime? date,
  }) {
    return db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(newId()),
            productName: name,
            store: Value(store),
            priceCents: Value(priceCents),
            purchaseDate: Value(date),
          ),
        );
  }

  testWidgets('shows a friendly empty state for a brand-new user',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: buildScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to KeepIt'), findsOneWidget);
    expect(find.textContaining('privately on this device'), findsOneWidget);
    expect(find.text('Add your first purchase'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('shows counts, attention items and recent purchases',
      (tester) async {
    final now = DateTime.now();
    final purchaseId = newId();
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: Value(purchaseId),
            productName: 'Air Fryer',
            store: const Value('Walmart'),
            priceCents: const Value(7999),
            purchaseDate: Value(now),
          ),
        );
    await seedPurchase(name: 'Headphones', store: 'Best Buy');
    // Warranty expiring in 10 days (within the 30-day "expiring soon" band).
    await db.into(db.warranties).insert(
          WarrantiesCompanion.insert(
            id: Value(newId()),
            purchaseId: purchaseId,
            expirationDate: Value(now.add(const Duration(days: 10))),
          ),
        );
    // Return deadline 2 days overdue.
    await db.into(db.returnDeadlines).insert(
          ReturnDeadlinesCompanion.insert(
            id: Value(newId()),
            purchaseId: purchaseId,
            deadlineDate: now.subtract(const Duration(days: 2)),
          ),
        );

    await tester.pumpWidget(MaterialApp(home: buildScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('need your attention'), findsOneWidget);
    expect(find.textContaining('Return overdue'), findsOneWidget);
    expect(find.textContaining('Warranty expiring'), findsOneWidget);
    expect(find.text('Purchases'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Recent purchases'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('Recent purchases'), findsOneWidget);
    expect(find.text('Air Fryer'), findsWidgets);
    expect(find.text('Headphones'), findsOneWidget);
  });
}
