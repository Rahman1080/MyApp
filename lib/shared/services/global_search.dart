import 'package:drift/drift.dart';

import '../../core/database/keepit_database.dart';
import 'text_similarity.dart';

/// Ranked global search across purchases, receipts, belongings, locations,
/// deadlines and documents. Case-insensitive; exact > prefix > substring.
class GlobalSearchResults {
  const GlobalSearchResults({
    this.purchases = const [],
    this.receipts = const [],
    this.belongings = const [],
    this.locations = const [],
    this.deadlines = const [],
    this.documents = const [],
  });

  final List<Purchase> purchases;
  final List<Receipt> receipts;
  final List<Belonging> belongings;
  final List<Location> locations;
  final List<Deadline> deadlines;
  final List<Document> documents;

  bool get isEmpty =>
      purchases.isEmpty &&
      receipts.isEmpty &&
      belongings.isEmpty &&
      locations.isEmpty &&
      deadlines.isEmpty &&
      documents.isEmpty;

  int get totalCount =>
      purchases.length +
      receipts.length +
      belongings.length +
      locations.length +
      deadlines.length +
      documents.length;
}

class GlobalSearchService {
  GlobalSearchService(this._db);

  final KeepItDatabase _db;

  Future<GlobalSearchResults> search(String query,
      {int limitPerEntity = 5}) async {
    final q = normalizeText(query);
    if (q.isEmpty) return const GlobalSearchResults();

    final purchases = await (_db.select(_db.purchases)
          ..where(
            (t) =>
                t.productName.contains(query) |
                t.store.contains(query) |
                t.notes.contains(query),
          )
          ..limit(50))
        .get();
    final receipts = await (_db.select(_db.receipts)
          ..where((t) => t.store.contains(query))
          ..limit(50))
        .get();
    final belongings = await (_db.select(_db.belongings)
          ..where(
            (t) =>
                t.name.contains(query) |
                t.brand.contains(query) |
                t.notes.contains(query),
          )
          ..limit(50))
        .get();
    final locations = await (_db.select(_db.locations)
          ..where((t) => t.name.contains(query))
          ..limit(50))
        .get();
    final deadlines = await (_db.select(_db.deadlines)
          ..where(
            (t) => t.title.contains(query) | t.notes.contains(query),
          )
          ..limit(50))
        .get();
    final documents = await (_db.select(_db.documents)
          ..where(
            (t) => t.title.contains(query) | t.notes.contains(query),
          )
          ..limit(50))
        .get();

    return GlobalSearchResults(
      purchases: _rank(
          purchases, q, (p) => [p.productName, p.store, p.notes], limitPerEntity),
      receipts:
          _rank(receipts, q, (r) => [r.store], limitPerEntity),
      belongings: _rank(
          belongings, q, (b) => [b.name, b.brand, b.notes], limitPerEntity),
      locations: _rank(locations, q, (l) => [l.name], limitPerEntity),
      deadlines:
          _rank(deadlines, q, (d) => [d.title, d.notes], limitPerEntity),
      documents:
          _rank(documents, q, (d) => [d.title, d.notes], limitPerEntity),
    );
  }

  /// Scores 3 for exact match, 2 for prefix, 1 for substring on the best
  /// matching field; sorts descending and caps at [limit].
  List<T> _rank<T>(
    List<T> rows,
    String query,
    List<String?> Function(T) fields,
    int limit,
  ) {
    final scored = <({T row, int score})>[];
    for (final row in rows) {
      var best = 0;
      for (final field in fields(row)) {
        final n = normalizeText(field ?? '');
        if (n.isEmpty) continue;
        if (n == query) {
          best = 3;
          break;
        } else if (n.startsWith(query)) {
          if (best < 2) best = 2;
        } else if (n.contains(query)) {
          if (best < 1) best = 1;
        }
      }
      if (best > 0) scored.add((row: row, score: best));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.row).toList();
  }
}
