import '../../core/database/keepit_database.dart';
import 'text_similarity.dart';

/// One possible duplicate of a purchase, with a confidence score in [0, 1].
class DuplicateCandidate {
  DuplicateCandidate({required this.purchase, required this.score});

  final Purchase purchase;
  final double score;
}

/// Finds likely-duplicate purchases. Detection only — the app never merges or
/// deletes automatically; the UI shows "View existing" / "Create anyway".
///
/// A purchase counts as a candidate when ALL of these hold:
/// - name similarity (token-set) >= [nameThreshold] (default 0.8)
/// - store matches after normalization (both blank counts as a match)
/// - price within 1% or $1 (either price missing counts as a match)
/// - purchase dates within [dateToleranceDays] (default 7; either missing
///   counts as a match)
class DuplicateDetector {
  DuplicateDetector(this._db);

  final KeepItDatabase _db;

  Future<List<DuplicateCandidate>> findCandidates(
    Purchase purchase, {
    double nameThreshold = 0.8,
    int dateToleranceDays = 7,
    double minScore = 0.5,
  }) async {
    final others = await (_db.select(_db.purchases)
          ..where((t) => t.id.isNotValue(purchase.id)))
        .get();

    final candidates = <DuplicateCandidate>[];
    for (final other in others) {
      final nameSim = tokenSetSimilarity(purchase.productName, other.productName);
      if (nameSim < nameThreshold) continue;
      if (!_storesMatch(purchase.store, other.store)) continue;
      if (!_pricesMatch(purchase.priceCents, other.priceCents)) continue;
      if (!_datesMatch(
          purchase.purchaseDate, other.purchaseDate, dateToleranceDays)) {
        continue;
      }

      final score = 0.5 * nameSim +
          0.2 * _storeScore(purchase.store, other.store) +
          0.15 * _priceScore(purchase.priceCents, other.priceCents) +
          0.15 *
              _dateScore(
                  purchase.purchaseDate, other.purchaseDate, dateToleranceDays);
      if (score >= minScore) {
        candidates.add(DuplicateCandidate(purchase: other, score: score));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  bool _storesMatch(String? a, String? b) {
    final na = normalizeText(a ?? '');
    final nb = normalizeText(b ?? '');
    if (na.isEmpty && nb.isEmpty) return true;
    return na == nb;
  }

  double _storeScore(String? a, String? b) => _storesMatch(a, b) ? 1 : 0;

  bool _pricesMatch(int? aCents, int? bCents) {
    if (aCents == null || bCents == null) return true;
    final diff = (aCents - bCents).abs();
    final tolerance = (aCents.abs() * 0.01).ceil() + 100;
    return diff <= tolerance;
  }

  double _priceScore(int? aCents, int? bCents) {
    if (aCents == null || bCents == null) return 0.5;
    if (!_pricesMatch(aCents, bCents)) return 0;
    final diff = (aCents - bCents).abs();
    final tolerance = (aCents.abs() * 0.01).ceil() + 100;
    if (tolerance == 0) return 1;
    return 1 - (diff / tolerance) * 0.5;
  }

  bool _datesMatch(DateTime? a, DateTime? b, int toleranceDays) {
    if (a == null || b == null) return true;
    return _dateScore(a, b, toleranceDays) > 0;
  }

  double _dateScore(DateTime? a, DateTime? b, int toleranceDays) {
    if (a == null || b == null) return 0.5;
    final diffDays = a.difference(b).inDays.abs();
    if (diffDays > toleranceDays) return 0;
    if (toleranceDays == 0) return 1;
    return 1 - (diffDays / toleranceDays) * 0.5;
  }
}
