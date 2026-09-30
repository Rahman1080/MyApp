/// Heuristic parsing of OCR text from a receipt into structured fields.
///
/// Pure Dart: takes the plain recognized text (not ML Kit types) so it is
/// fully unit-testable. All parsing runs on-device; nothing is logged or
/// uploaded. Every field is nullable — when the text is garbage or empty the
/// caller must let the user fill the form manually instead of inventing data.
class ParsedReceipt {
  const ParsedReceipt({
    this.store,
    this.date,
    this.totalCents,
    this.subtotalCents,
    this.taxCents,
  });

  /// Store name guess: first meaningful text line, or null.
  final String? store;

  /// Receipt date guess, or null.
  final DateTime? date;

  /// Total in minor currency units (cents), or null.
  final int? totalCents;

  /// Subtotal in cents, or null.
  final int? subtotalCents;

  /// Tax in cents, or null.
  final int? taxCents;

  bool get isEmpty =>
      store == null &&
      date == null &&
      totalCents == null &&
      subtotalCents == null &&
      taxCents == null;
}

/// Matches amounts like 12.34, 1,234.56, $12.34, € 1.234,56.
/// Group 1 captures the numeric part.
final RegExp _amountPattern = RegExp(
  r'''(?:[\$€£]\s*)?(\d{1,3}(?:[.,]\d{3})*[.,]\d{2}|\d+[.,]\d{2})''',
);

/// Parses the full OCR text of a receipt into [ParsedReceipt].
ParsedReceipt parseReceiptText(String rawText) {
  final lines = rawText
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const ParsedReceipt();

  return ParsedReceipt(
    store: _parseStore(lines),
    date: _parseDate(lines),
    totalCents: _parseLabeledAmount(lines, _totalLabels) ?? _parseLargestAmount(lines),
    subtotalCents: _parseLabeledAmount(lines, _subtotalLabels),
    taxCents: _parseLabeledAmount(lines, _taxLabels),
  );
}

const _totalLabels = ['total', 'amount due', 'balance due', 'grand total'];
const _subtotalLabels = ['subtotal', 'sub-total', 'sub total'];
const _taxLabels = ['tax', 'vat', 'gst', 'sales tax'];

/// First line that looks like a store name: at least 2 letters, not just an
/// amount/date/phone number.
String? _parseStore(List<String> lines) {
  for (final line in lines) {
    final cleaned = line.replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '').trim();
    if (cleaned.length < 2) continue;
    final letters = RegExp(r'[A-Za-z]').allMatches(cleaned).length;
    if (letters < 2) continue;
    if (_amountPattern.hasMatch(cleaned)) continue;
    if (_looksLikeDate(cleaned)) continue;
    if (RegExp(r'^[\d\s()+.-]{7,}$').hasMatch(cleaned)) continue; // phone-ish
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }
  return null;
}

bool _looksLikeDate(String line) => _findDate(line) != null;

/// First date-like value found while scanning lines top to bottom.
DateTime? _parseDate(List<String> lines) {
  for (final line in lines) {
    final date = _findDate(line);
    if (date != null) return date;
  }
  return null;
}

DateTime? _findDate(String line) {
  // YYYY-MM-DD or YYYY/MM/DD
  var match =
      RegExp(r'\b(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})\b').firstMatch(line);
  if (match != null) {
    return _validDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
  // MM/DD/YYYY or MM-DD-YYYY (slash/dash → month first, US receipt default)
  match = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b').firstMatch(line);
  if (match != null) {
    return _validDate(
      int.parse(match.group(3)!),
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }
  // DD.MM.YYYY (dots → day first, common on EU receipts)
  match = RegExp(r'\b(\d{1,2})[.](\d{1,2})[.](\d{4})\b').firstMatch(line);
  if (match != null) {
    return _validDate(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }
  return null;
}

DateTime? _validDate(int year, int month, int day) {
  if (year < 1990 || year > 2100) return null;
  if (month < 1 || month > 12) return null;
  final lastDay = DateTime(year, month + 1, 0).day;
  if (day < 1 || day > lastDay) return null;
  return DateTime(year, month, day);
}

/// Amount on a line containing one of [labels] (e.g. the "TOTAL" line).
/// Labels match on word boundaries so "subtotal" never matches "total".
/// Returns null when no labeled line carries an amount.
int? _parseLabeledAmount(List<String> lines, List<String> labels) {
  final patterns = [
    for (final label in labels)
      RegExp('\\b${RegExp.escape(label)}\\b', caseSensitive: false),
  ];
  for (final line in lines) {
    if (patterns.any((pattern) => pattern.hasMatch(line))) {
      final cents = _lastAmountOnLine(line);
      if (cents != null) return cents;
    }
  }
  return null;
}

/// Fallback total: the largest amount anywhere on the receipt.
int? _parseLargestAmount(List<String> lines) {
  var best = 0;
  var found = false;
  for (final line in lines) {
    for (final match in _amountPattern.allMatches(line)) {
      final cents = _toCents(match.group(1)!);
      if (cents != null && (!found || cents > best)) {
        best = cents;
        found = true;
      }
    }
  }
  return found ? best : null;
}

/// Last amount on a single line (the value usually sits at line end).
int? _lastAmountOnLine(String line) {
  int? result;
  for (final match in _amountPattern.allMatches(line)) {
    result = _toCents(match.group(1)!);
  }
  return result;
}

/// Converts a matched numeric string to minor units, tolerating both
/// 1,234.56 and 1.234,56 styles: the LAST separator is the decimal one.
int? _toCents(String raw) {
  var normalized = raw.trim();
  final lastComma = normalized.lastIndexOf(',');
  final lastDot = normalized.lastIndexOf('.');
  if (lastComma > lastDot) {
    // European style: 1.234,56 → 1234.56
    normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
  } else {
    normalized = normalized.replaceAll(',', '');
  }
  final value = double.tryParse(normalized);
  if (value == null || value < 0 || value > 99999999) return null;
  return (value * 100).round();
}
