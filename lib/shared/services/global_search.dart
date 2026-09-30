import 'package:drift/drift.dart';

import '../../core/database/keepit_database.dart';
import '../../core/database/repositories/tag_repository.dart';
import 'text_similarity.dart';

/// Ranked global search across purchases, receipts, belongings, locations,
/// deadlines and documents. Case-insensitive; exact > prefix > substring.
///
/// Phase 9: belongings also match on model, serial number, category name,
/// location name and tags. Exact matches rank first.
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
  GlobalSearchService(this._db) : _tags = TagRepository(_db);

  final KeepItDatabase _db;
  final TagRepository _tags;

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
      belongings: await _searchBelongings(query, q, limitPerEntity),
      locations: _rank(locations, q, (l) => [l.name], limitPerEntity),
      deadlines:
          _rank(deadlines, q, (d) => [d.title, d.notes], limitPerEntity),
      documents:
          _rank(documents, q, (d) => [d.title, d.notes], limitPerEntity),
    );
  }

  /// Belongings matching the query in name, brand, model, serial number,
  /// notes, category name, location name or tags. Ranked exact > prefix >
  /// substring across the best-matching field.
  Future<List<Belonging>> _searchBelongings(
      String query, String normalizedQuery, int limit) async {
    // Direct field matches.
    final direct = await (_db.select(_db.belongings)
          ..where(
            (t) =>
                t.name.contains(query) |
                t.brand.contains(query) |
                t.notes.contains(query) |
                t.model.contains(query) |
                t.serialNumber.contains(query),
          )
          ..limit(100))
        .get();

    final candidates = <String, Belonging>{
      for (final b in direct) b.id: b,
    };
    // Extra searchable text per belonging: category, location, tag names.
    final extraFields = <String, List<String>>{};

    // Tag matches: tags whose name matches -> their belongings.
    final matchingTags = await (_db.select(_db.tags)
          ..where((t) => t.name.contains(query))
          ..limit(20))
        .get();
    for (final tag in matchingTags) {
      final ids = await _tags.entityIdsForTag(tag.id, 'belonging');
      for (final id in ids) {
        (extraFields[id] ??= []).add(tag.name);
        if (!candidates.containsKey(id)) {
          final b = await (_db.select(_db.belongings)
                ..where((t) => t.id.equals(id)))
              .getSingleOrNull();
          if (b != null) candidates[id] = b;
        }
      }
    }

    // Category name matches.
    final matchingCategories = await (_db.select(_db.categories)
          ..where((t) => t.name.contains(query))
          ..limit(20))
        .get();
    if (matchingCategories.isNotEmpty) {
      final catIds = matchingCategories.map((c) => c.id).toList();
      final catNameById = {
        for (final c in matchingCategories) c.id: c.name,
      };
      final inCats = await (_db.select(_db.belongings)
            ..where((t) => t.categoryId.isIn(catIds))
            ..limit(100))
          .get();
      for (final b in inCats) {
        candidates[b.id] = b;
        final catName = catNameById[b.categoryId];
        if (catName != null) (extraFields[b.id] ??= []).add(catName);
      }
    }

    // Location name matches (the location itself, not its descendants —
    // the location's own result row covers the subtree).
    final matchingLocations = await (_db.select(_db.locations)
          ..where((t) => t.name.contains(query))
          ..limit(20))
        .get();
    if (matchingLocations.isNotEmpty) {
      final locIds = matchingLocations.map((l) => l.id).toList();
      final locNameById = {
        for (final l in matchingLocations) l.id: l.name,
      };
      final inLocs = await (_db.select(_db.belongings)
            ..where((t) => t.locationId.isIn(locIds))
            ..limit(100))
          .get();
      for (final b in inLocs) {
        candidates[b.id] = b;
        final locName = locNameById[b.locationId];
        if (locName != null) (extraFields[b.id] ??= []).add(locName);
      }
    }

    // Category/location names for the directly matched belongings, so an
    // exact category or location name still outranks a substring hit.
    if (candidates.isNotEmpty) {
      final catIds = {
        for (final b in candidates.values)
          if (b.categoryId != null) b.categoryId!,
      };
      final locIds = {
        for (final b in candidates.values)
          if (b.locationId != null) b.locationId!,
      };
      final catNames = <String, String>{};
      final locNames = <String, String>{};
      if (catIds.isNotEmpty) {
        final cats = await (_db.select(_db.categories)
              ..where((t) => t.id.isIn(catIds.toList())))
            .get();
        for (final c in cats) {
          catNames[c.id] = c.name;
        }
      }
      if (locIds.isNotEmpty) {
        final locs = await (_db.select(_db.locations)
              ..where((t) => t.id.isIn(locIds.toList())))
            .get();
        for (final l in locs) {
          locNames[l.id] = l.name;
        }
      }
      for (final b in candidates.values) {
        final catName =
            b.categoryId == null ? null : catNames[b.categoryId!];
        if (catName != null) (extraFields[b.id] ??= []).add(catName);
        final locName =
            b.locationId == null ? null : locNames[b.locationId!];
        if (locName != null) (extraFields[b.id] ??= []).add(locName);
      }
    }

    return _rank(
      candidates.values.toList(),
      normalizedQuery,
      (b) => [
        b.name,
        b.brand,
        b.model,
        b.serialNumber,
        b.notes,
        ...?extraFields[b.id],
      ],
      limit,
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
