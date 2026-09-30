import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/utilities/money.dart';

void main() {
  test('parseMoneyToCents parses decimals into minor units', () {
    expect(parseMoneyToCents('49.99'), 4999);
    expect(parseMoneyToCents('100'), 10000);
    expect(parseMoneyToCents(' 12.5 '), 1250);
    expect(parseMoneyToCents('1,234.56'), 123456);
    expect(parseMoneyToCents(''), isNull);
    expect(parseMoneyToCents('   '), isNull);
  });

  test('parseMoneyToCents throws on garbage', () {
    expect(() => parseMoneyToCents('abc'), throwsFormatException);
  });

  test('centsToDecimalString round-trips through parseMoneyToCents', () {
    expect(centsToDecimalString(4999), '49.99');
    expect(centsToDecimalString(null), '');
    expect(parseMoneyToCents(centsToDecimalString(24999)), 24999);
  });

  test('formatMoney renders null as an em dash, never a fake zero', () {
    expect(formatMoney(null, 'USD'), '—');
    expect(formatMoney(4999, 'USD'), contains('49.99'));
  });

  test('defaultCurrencyCode returns a non-empty ISO code', () {
    final code = defaultCurrencyCode();
    expect(code, isNotEmpty);
    expect(code.length, 3);
  });
}
