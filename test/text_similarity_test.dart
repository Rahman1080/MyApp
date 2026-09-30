import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/shared/services/text_similarity.dart';

void main() {
  group('normalizeText', () {
    test('lowercases, trims and collapses whitespace', () {
      expect(normalizeText('  Sony   WH-1000XM5 '), 'sony wh1000xm5');
    });

    test('drops punctuation', () {
      expect(normalizeText("Men's Shoes (Red)!"), 'mens shoes red');
    });

    test('empty stays empty', () {
      expect(normalizeText('   '), isEmpty);
    });
  });

  group('levenshtein', () {
    test('identical strings have distance 0', () {
      expect(levenshtein('abc', 'abc'), 0);
    });

    test('known distances', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('abc', ''), 3);
    });

    test('similarity is 1 for identical, 0 for empty vs non-empty', () {
      expect(levenshteinSimilarity('Air Fryer', 'air fryer'), 1);
      expect(levenshteinSimilarity('', 'abc'), 0);
      expect(levenshteinSimilarity('', ''), 1);
    });
  });

  group('tokenSetSimilarity', () {
    test('order-insensitive match scores high', () {
      final score = tokenSetSimilarity('Sony WH-1000XM5', 'WH-1000XM5 Sony');
      expect(score, greaterThanOrEqualTo(0.9));
    });

    test('extra words still score above threshold', () {
      final score =
          tokenSetSimilarity('Sony WH-1000XM5 Headphones', 'Sony WH-1000XM5');
      expect(score, greaterThanOrEqualTo(0.8));
    });

    test('different products score low', () {
      final score = tokenSetSimilarity('Air Fryer', 'Running Shoes');
      expect(score, lessThan(0.5));
    });

    test('both empty scores 1, one empty scores 0', () {
      expect(tokenSetSimilarity('', ''), 1);
      expect(tokenSetSimilarity('abc', ''), 0);
    });
  });
}
