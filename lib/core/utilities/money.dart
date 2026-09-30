import 'dart:ui';

import 'package:intl/intl.dart';

/// Formats integer minor units (cents) as a localized money string.
///
/// Returns an em dash when [cents] is null (price unknown), never a fake
/// zero. Uses the ISO currency code for the symbol; falls back to the raw
/// code prefix when intl doesn't know the currency.
String formatMoney(int? cents, String currencyCode) {
  if (cents == null) return '—';
  try {
    return NumberFormat.simpleCurrency(name: currencyCode)
        .format(cents / 100);
  } catch (_) {
    return '$currencyCode ${(cents / 100).toStringAsFixed(2)}';
  }
}

/// Parses a user-typed decimal amount ("49.99") into minor units (4999).
/// Returns null for empty input; throws [FormatException] for garbage.
int? parseMoneyToCents(String text) {
  final trimmed = text.trim().replaceAll(',', '');
  if (trimmed.isEmpty) return null;
  final value = double.parse(trimmed);
  return (value * 100).round();
}

/// Formats minor units back to an editable decimal string ("49.99").
String centsToDecimalString(int? cents) {
  if (cents == null) return '';
  return (cents / 100).toStringAsFixed(2);
}

/// Short list of currencies for the purchase form. ISO 4217 codes.
const List<String> commonCurrencies = [
  'USD',
  'EUR',
  'GBP',
  'CAD',
  'AUD',
  'JPY',
  'INR',
  'PKR',
  'AED',
  'SAR',
  'BRL',
  'MXN',
  'CHF',
];

/// Best-effort ISO 4217 currency code for the device's current locale.
/// Falls back to 'USD' when intl cannot determine one. Pure read — no
/// permissions, no network.
String defaultCurrencyCode() {
  try {
    final locale = PlatformDispatcher.instance.locale.toString();
    final code = NumberFormat.simpleCurrency(locale: locale).currencyName;
    if (code != null && code.isNotEmpty) return code;
  } catch (_) {
    // Fall through to USD.
  }
  return 'USD';
}
