import 'package:flutter_test/flutter_test.dart';

import 'package:keepit/features/receipts/domain/receipt_text_parser.dart';

void main() {
  group('parseReceiptText', () {
    test('parses a typical US receipt', () {
      const text = '''
WALMART SUPERCENTER
Store #1234
01/15/2026
Milk 3.49
Bread 2.99
Subtotal 6.48
Tax 0.52
TOTAL \$7.00
Thank you!
''';
      final parsed = parseReceiptText(text);
      expect(parsed.store, 'WALMART SUPERCENTER');
      expect(parsed.date, DateTime(2026, 1, 15));
      expect(parsed.totalCents, 700);
      expect(parsed.subtotalCents, 648);
      expect(parsed.taxCents, 52);
    });

    test('total label wins over larger amounts elsewhere', () {
      const text = '''
SHOP
Item A 99.99
Item B 50.00
TOTAL 12.50
''';
      final parsed = parseReceiptText(text);
      // The labeled TOTAL line is authoritative even though 99.99 is larger.
      expect(parsed.totalCents, 1250);
    });

    test('falls back to largest amount when no total label', () {
      const text = '''
CORNER STORE
Apples 2.30
Cheese 11.20
''';
      final parsed = parseReceiptText(text);
      expect(parsed.totalCents, 1120);
      expect(parsed.store, 'CORNER STORE');
    });

    test('parses DD.MM.YYYY European dates', () {
      const text = 'REWE\n15.03.2026\nSumme 23,45 €';
      final parsed = parseReceiptText(text);
      expect(parsed.date, DateTime(2026, 3, 15));
      expect(parsed.totalCents, 2345);
    });

    test('parses YYYY-MM-DD dates', () {
      const text = 'STORE\n2026-02-28\nTotal 10.00';
      final parsed = parseReceiptText(text);
      expect(parsed.date, DateTime(2026, 2, 28));
    });

    test('parses MM-DD-YYYY dates', () {
      const text = 'STORE\n03-05-2026\nTotal 10.00';
      final parsed = parseReceiptText(text);
      expect(parsed.date, DateTime(2026, 3, 5));
    });

    test('rejects impossible dates', () {
      const text = 'STORE\n99/99/2026\nTotal 10.00';
      final parsed = parseReceiptText(text);
      expect(parsed.date, isNull);
    });

    test('skips phone-number-looking first lines for store name', () {
      const text = '(555) 123-4567\nACME MART\nTotal 5.00';
      final parsed = parseReceiptText(text);
      expect(parsed.store, 'ACME MART');
    });

    test('empty input yields an empty parse', () {
      final parsed = parseReceiptText('   \n\n  ');
      expect(parsed.isEmpty, isTrue);
      expect(parsed.store, isNull);
      expect(parsed.date, isNull);
      expect(parsed.totalCents, isNull);
    });

    test('garbage input yields an empty parse', () {
      final parsed = parseReceiptText('###\n***\n???');
      expect(parsed.isEmpty, isTrue);
    });

    test('amounts with thousands separators parse correctly', () {
      const text = 'STORE\nTotal \$1,234.56';
      final parsed = parseReceiptText(text);
      expect(parsed.totalCents, 123456);
    });

    test('vat label is treated as tax', () {
      const text = 'SHOP\nSubtotal 100.00\nVAT 20.00\nTotal 120.00';
      final parsed = parseReceiptText(text);
      expect(parsed.taxCents, 2000);
      expect(parsed.subtotalCents, 10000);
      expect(parsed.totalCents, 12000);
    });
  });
}
