import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepit/features/receipts/domain/receipt_text_parser.dart';
import 'package:keepit/features/receipts/presentation/widgets/receipt_confirm_form.dart';

void main() {
  Widget wrap(ReceiptConfirmForm form) {
    return MaterialApp(home: Scaffold(body: form));
  }

  ReceiptConfirmForm buildForm({
    void Function({
      required String? store,
      required DateTime? date,
      required int? totalCents,
      required int? subtotalCents,
      required int? taxCents,
    })? onConfirm,
    VoidCallback? onDiscard,
  }) {
    return ReceiptConfirmForm(
      // Image.file falls back to errorBuilder for a missing file — fine here.
      image: File('/tmp/keepit-test-missing.jpg'),
      rawText: 'ACME MART\nTotal \$12.50',
      parsed: const ParsedReceipt(
        store: 'ACME MART',
        date: null,
        totalCents: 1250,
      ),
      onConfirm: onConfirm ??
          ({required store,
          required date,
          required totalCents,
          required subtotalCents,
          required taxCents}) {},
      onDiscard: onDiscard ?? () {},
    );
  }

  testWidgets('renders parsed fields with Confirm and Discard',
      (tester) async {
    await tester.pumpWidget(wrap(buildForm()));

    expect(find.text('ACME MART'), findsOneWidget);
    expect(find.text('12.50'), findsOneWidget);
    expect(find.byKey(const Key('confirmReceiptButton')), findsOneWidget);
    expect(find.byKey(const Key('discardReceiptButton')), findsOneWidget);
    // The raw OCR text is shown for transparency.
    expect(find.text('What the scan read'), findsOneWidget);
  });

  testWidgets('Confirm passes the reviewed values to onConfirm', (tester) async {
    String? confirmedStore;
    int? confirmedTotal;
    await tester.pumpWidget(wrap(buildForm(
      onConfirm: ({
        required store,
        required date,
        required totalCents,
        required subtotalCents,
        required taxCents,
      }) {
        confirmedStore = store;
        confirmedTotal = totalCents;
      },
    )));

    await tester.ensureVisible(find.byKey(const Key('confirmReceiptButton')));
    await tester.tap(find.byKey(const Key('confirmReceiptButton')));
    await tester.pump();

    expect(confirmedStore, 'ACME MART');
    expect(confirmedTotal, 1250);
  });

  testWidgets('user can edit the total before confirming', (tester) async {
    int? confirmedTotal;
    await tester.pumpWidget(wrap(buildForm(
      onConfirm: ({
        required store,
        required date,
        required totalCents,
        required subtotalCents,
        required taxCents,
      }) {
        confirmedTotal = totalCents;
      },
    )));

    // Find the total field (hint 0.00) and replace its value.
    final totalField = find.widgetWithText(TextField, '0.00');
    await tester.ensureVisible(totalField);
    await tester.enterText(totalField, '99.99');
    await tester.ensureVisible(find.byKey(const Key('confirmReceiptButton')));
    await tester.tap(find.byKey(const Key('confirmReceiptButton')));
    await tester.pump();

    expect(confirmedTotal, 9999);
  });

  testWidgets('Discard calls onDiscard', (tester) async {
    var discarded = false;
    await tester.pumpWidget(wrap(buildForm(onDiscard: () => discarded = true)));

    await tester.ensureVisible(find.byKey(const Key('discardReceiptButton')));
    await tester.tap(find.byKey(const Key('discardReceiptButton')));
    await tester.pump();

    expect(discarded, isTrue);
  });

  testWidgets('empty parse leaves fields blank for manual entry',
      (tester) async {
    await tester.pumpWidget(wrap(ReceiptConfirmForm(
      image: File('/tmp/keepit-test-missing.jpg'),
      rawText: '',
      parsed: const ParsedReceipt(),
      onConfirm: ({required store,
      required date,
      required totalCents,
      required subtotalCents,
      required taxCents}) {},
      onDiscard: () {},
    )));

    expect(find.text('No date found'), findsOneWidget);
    expect(find.byKey(const Key('confirmReceiptButton')), findsOneWidget);
  });
}
