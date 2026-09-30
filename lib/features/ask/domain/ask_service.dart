import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../shared/services/global_search.dart';

/// Types of questions Ask KEEPIT can answer.
enum AskIntent {
  /// "where is X" — find the location of an item.
  whereIs,

  /// "what is in Y" — list items in a location.
  whatIsIn,

  /// "warranty for X" — warranty status for an item.
  warrantyFor,

  /// "when did I buy X" — purchase date for an item.
  whenBought,

  /// "how much is X worth" — value of an item.
  howMuchWorth,

  /// "show me X" / general search — keyword search.
  search,

  /// Could not determine intent.
  unknown,
}

/// A parsed natural language query.
class ParsedQuery {
  const ParsedQuery({
    required this.intent,
    required this.subject,
    required this.original,
  });

  final AskIntent intent;
  final String subject;
  final String original;
}

/// An answer from Ask KEEPIT, grounded in local data.
class AskAnswer {
  const AskAnswer({
    required this.query,
    required this.answerText,
    this.belongings = const [],
    this.locations = const [],
    this.purchases = const [],
    this.warranties = const [],
  });

  final ParsedQuery query;
  final String answerText;
  final List<Belonging> belongings;
  final List<Location> locations;
  final List<Purchase> purchases;
  final List<Warranty> warranties;

  bool get hasResults =>
      belongings.isNotEmpty ||
      locations.isNotEmpty ||
      purchases.isNotEmpty ||
      warranties.isNotEmpty;
}

/// Ask KEEPIT: grounded natural-language search over local data (Phase 16).
///
/// Deterministic pattern matching — no LLM, no network. Every answer is
/// grounded in actual database records. Never fabricates data; if nothing
/// is found, the answer says so explicitly.
class AskKeepitService {
  AskKeepitService(KeepItDatabase db)
    : _belongings = BelongingRepository(db),
      _locations = LocationRepository(db),
      _purchases = PurchaseRepository(db),
      _warranties = WarrantyRepository(db),
      _search = GlobalSearchService(db);

  final BelongingRepository _belongings;
  final LocationRepository _locations;
  final PurchaseRepository _purchases;
  final WarrantyRepository _warranties;
  final GlobalSearchService _search;

  String _cleanSubject(String s) {
    var cleaned = s.trim();
    while (cleaned.endsWith('?') || cleaned.endsWith('.')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    if (cleaned.toLowerCase().startsWith('my ')) {
      cleaned = cleaned.substring(3).trim();
    } else if (cleaned.toLowerCase().startsWith('the ')) {
      cleaned = cleaned.substring(4).trim();
    } else if (cleaned.toLowerCase().startsWith('a ')) {
      cleaned = cleaned.substring(2).trim();
    }
    return cleaned;
  }

  /// Parses a natural language query into a structured intent.
  ParsedQuery parseQuery(String input) {
    final normalized = input.trim().toLowerCase();
    final original = input.trim();

    // "where is X" / "where's X"
    final whereIs = RegExp(r"where(?:'s| is) (.+)").firstMatch(normalized);
    if (whereIs != null) {
      return ParsedQuery(
        intent: AskIntent.whereIs,
        subject: _cleanSubject(whereIs.group(1)!),
        original: original,
      );
    }

    // "what is in Y" / "what's in Y" / "whats in Y"
    final whatIn = RegExp(r"what(?:'s| is|s)? in (.+)").firstMatch(normalized);
    if (whatIn != null) {
      return ParsedQuery(
        intent: AskIntent.whatIsIn,
        subject: _cleanSubject(whatIn.group(1)!),
        original: original,
      );
    }

    // "warranty for X" / "warranty on X" / "is the X under warranty"
    final warrantyMatch1 = RegExp(r"warranty (?:for|on|of) (.+)").firstMatch(normalized);
    final warrantyMatch2 = RegExp(r"(?:is|does) (?:the |my )?(.+?) (?:have a warranty|under warranty|covered by warranty)\??$").firstMatch(normalized);
    final warrantyMatch3 = RegExp(r"do i have a warranty (?:for|on) (.+)\??$").firstMatch(normalized);
    final warrantySubject = warrantyMatch1?.group(1) ?? warrantyMatch2?.group(1) ?? warrantyMatch3?.group(1);
    if (warrantySubject != null) {
      return ParsedQuery(
        intent: AskIntent.warrantyFor,
        subject: _cleanSubject(warrantySubject),
        original: original,
      );
    }

    // "when did I buy X"
    final whenBought =
        RegExp(r"when did i buy (.+)").firstMatch(normalized);
    if (whenBought != null) {
      return ParsedQuery(
        intent: AskIntent.whenBought,
        subject: _cleanSubject(whenBought.group(1)!),
        original: original,
      );
    }

    // "how much is X worth"
    final worth = RegExp(r"how much is (.+) worth").firstMatch(normalized);
    if (worth != null) {
      return ParsedQuery(
        intent: AskIntent.howMuchWorth,
        subject: _cleanSubject(worth.group(1)!),
        original: original,
      );
    }

    // "show me X" / "find X" / "search for X"
    final show = RegExp(r"(?:show me|find|search for) (.+)").firstMatch(normalized);
    if (show != null) {
      return ParsedQuery(
        intent: AskIntent.search,
        subject: _cleanSubject(show.group(1)!),
        original: original,
      );
    }

    // Fallback: treat the whole input as a search query.
    if (normalized.isNotEmpty) {
      return ParsedQuery(
        intent: AskIntent.search,
        subject: _cleanSubject(original),
        original: original,
      );
    }

    return ParsedQuery(
      intent: AskIntent.unknown,
      subject: '',
      original: original,
    );
  }

  /// Answers a natural language question using local data.
  Future<AskAnswer> ask(String input) async {
    final query = parseQuery(input);

    switch (query.intent) {
      case AskIntent.whereIs:
        return _answerWhereIs(query);
      case AskIntent.whatIsIn:
        return _answerWhatIsIn(query);
      case AskIntent.warrantyFor:
        return _answerWarrantyFor(query);
      case AskIntent.whenBought:
        return _answerWhenBought(query);
      case AskIntent.howMuchWorth:
        return _answerHowMuchWorth(query);
      case AskIntent.search:
        return _answerSearch(query);
      case AskIntent.unknown:
        return AskAnswer(
          query: query,
          answerText: 'I didn\'t understand that. Try "where is X" or "show me X".',
        );
    }
  }

  Future<AskAnswer> _answerWhereIs(ParsedQuery query) async {
    final results = await _search.search(query.subject);
    if (results.belongings.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: 'I couldn\'t find "${query.subject}" in your inventory.',
      );
    }

    final item = results.belongings.first;
    if (item.locationId == null) {
      return AskAnswer(
        query: query,
        answerText: '"${item.name}" doesn\'t have a location set.',
        belongings: [item],
      );
    }

    final location = await _locations.getById(item.locationId!);
    final locationName = location?.name ?? 'Unknown location';
    return AskAnswer(
      query: query,
      answerText: '"${item.name}" is in $locationName.',
      belongings: [item],
      locations: location == null ? [] : [location],
    );
  }

  Future<AskAnswer> _answerWhatIsIn(ParsedQuery query) async {
    final results = await _search.search(query.subject);
    // Find locations matching the subject.
    final matchingLocations = results.locations;
    if (matchingLocations.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: 'I couldn\'t find a location called "${query.subject}".',
      );
    }

    final location = matchingLocations.first;
    final items = await _belongings.inLocations([location.id]);
    if (items.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: '"${location.name}" is empty.',
        locations: [location],
      );
    }

    final names = items.map((i) => '"${i.name}"').join(', ');
    return AskAnswer(
      query: query,
      answerText: '"${location.name}" contains: $names.',
      belongings: items,
      locations: [location],
    );
  }

  Future<AskAnswer> _answerWarrantyFor(ParsedQuery query) async {
    final results = await _search.search(query.subject);
    if (results.belongings.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: 'I couldn\'t find "${query.subject}" in your inventory.',
      );
    }

    final item = results.belongings.first;
    final warranties = await _warranties.forBelonging(item.id);
    if (warranties.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: '"${item.name}" has no warranty on file.',
        belongings: [item],
      );
    }

    final warranty = warranties.first;
    final provider = warranty.provider ?? 'Unknown provider';
    return AskAnswer(
      query: query,
      answerText:
          '"${item.name}" has a warranty from $provider.',
      belongings: [item],
      warranties: warranties,
    );
  }

  Future<AskAnswer> _answerWhenBought(ParsedQuery query) async {
    final results = await _search.search(query.subject);
    if (results.belongings.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: 'I couldn\'t find "${query.subject}" in your inventory.',
      );
    }

    final item = results.belongings.first;
    if (item.purchaseId == null) {
      return AskAnswer(
        query: query,
        answerText: '"${item.name}" has no purchase record.',
        belongings: [item],
      );
    }

    final purchase = await _purchases.getById(item.purchaseId!);
    if (purchase == null || purchase.purchaseDate == null) {
      return AskAnswer(
        query: query,
        answerText: '"${item.name}" has no purchase date on file.',
        belongings: [item],
      );
    }

    final date = purchase.purchaseDate!;
    final formatted = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return AskAnswer(
      query: query,
      answerText: 'You bought "${item.name}" on $formatted.',
      belongings: [item],
      purchases: [purchase],
    );
  }

  Future<AskAnswer> _answerHowMuchWorth(ParsedQuery query) async {
    final results = await _search.search(query.subject);
    if (results.belongings.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: 'I couldn\'t find "${query.subject}" in your inventory.',
      );
    }

    final item = results.belongings.first;
    if (item.valueUnknown || item.valueCents == null) {
      return AskAnswer(
        query: query,
        answerText: '"${item.name}" has no value recorded.',
        belongings: [item],
      );
    }

    final dollars = (item.valueCents! / 100).toStringAsFixed(2);
    final currency = item.currencyCode ?? 'USD';
    return AskAnswer(
      query: query,
      answerText: '"${item.name}" is worth $dollars $currency.',
      belongings: [item],
    );
  }

  Future<AskAnswer> _answerSearch(ParsedQuery query) async {
    final results = await _search.search(query.subject);
    if (results.isEmpty) {
      return AskAnswer(
        query: query,
        answerText: 'No results for "${query.subject}".',
      );
    }

    final parts = <String>[];
    if (results.belongings.isNotEmpty) {
      parts.add('${results.belongings.length} item(s)');
    }
    if (results.locations.isNotEmpty) {
      parts.add('${results.locations.length} location(s)');
    }
    if (results.purchases.isNotEmpty) {
      parts.add('${results.purchases.length} purchase(s)');
    }
    if (results.documents.isNotEmpty) {
      parts.add('${results.documents.length} document(s)');
    }

    return AskAnswer(
      query: query,
      answerText: 'Found ${parts.join(', ')} for "${query.subject}".',
      belongings: results.belongings,
      locations: results.locations,
      purchases: results.purchases,
    );
  }
}
