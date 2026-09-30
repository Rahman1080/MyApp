import 'dart:math';

/// Normalizes free text for comparison: lowercase, trim, collapse whitespace,
/// drop punctuation. Used by duplicate detection and search ranking.
String normalizeText(String input) {
  final lower = input.toLowerCase().trim();
  final collapsed = lower.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '');
}

/// Splits normalized text into tokens.
List<String> tokenize(String input) {
  final normalized = normalizeText(input);
  if (normalized.isEmpty) return const [];
  return normalized.split(' ');
}

/// Classic Levenshtein edit distance.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = min(
        min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    final temp = previous;
    previous = current;
    current = temp;
  }
  return previous[b.length];
}

/// Similarity in [0, 1] from Levenshtein distance: 1 = identical.
double levenshteinSimilarity(String a, String b) {
  final x = normalizeText(a);
  final y = normalizeText(b);
  final maxLen = max(x.length, y.length);
  if (maxLen == 0) return 1;
  return 1 - levenshtein(x, y) / maxLen;
}

/// Token-set similarity: order-insensitive, tolerant of extra words
/// ("Sony WH-1000XM5" vs "WH-1000XM5 Sony headphones" score high).
/// Returns a value in [0, 1].
double tokenSetSimilarity(String a, String b) {
  final tokensA = tokenize(a).toSet();
  final tokensB = tokenize(b).toSet();
  if (tokensA.isEmpty && tokensB.isEmpty) return 1;
  if (tokensA.isEmpty || tokensB.isEmpty) return 0;

  final intersection = tokensA.intersection(tokensB).toList()..sort();
  final sortedA = tokensA.toList()..sort();
  final sortedB = tokensB.toList()..sort();

  final inter = intersection.join(' ');
  final strA = sortedA.join(' ');
  final strB = sortedB.join(' ');

  return max(
    levenshteinSimilarity(inter, strA),
    max(
      levenshteinSimilarity(inter, strB),
      levenshteinSimilarity(strA, strB),
    ),
  );
}
