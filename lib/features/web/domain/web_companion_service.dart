import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';

/// Web Companion service (Phase 20).
///
/// Generates a self-contained static HTML page from inventory data.
/// This provides a "web companion" experience — view your inventory
/// in any browser — without requiring a separate web codebase.
///
/// The HTML is fully offline-capable: all data is embedded, no
/// external requests. Users can save the file and open it anywhere,
/// or host it on any static file server.
///
/// This approach preserves the one-codebase requirement: the HTML
/// is generated from the existing Flutter/Dart codebase, not a
/// separate web app.
class WebCompanionService {
  WebCompanionService(KeepItDatabase db)
    : _belongings = BelongingRepository(db),
      _locations = LocationRepository(db);

  final BelongingRepository _belongings;
  final LocationRepository _locations;

  /// Generates a static HTML inventory page.
  ///
  /// [title] is the page title. If [locationId] is provided, only
  /// items in that location (and its subtree) are included.
  Future<String> generateHtml({
    String title = 'KEEPIT Inventory',
    String? locationId,
  }) async {
    final items = locationId == null
        ? await _belongings.getAll()
        : await _belongings.inLocations([locationId]);
    final locations = await _locations.getAll();
    final locationNames = {
      for (final loc in locations) loc.id: loc.name,
    };

    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<title>${_escape(title)}</title>');
    buffer.writeln('<style>');
    buffer.writeln(_css);
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<header>');
    buffer.writeln('<h1>${_escape(title)}</h1>');
    buffer.writeln(
        '<p class="meta">Generated ${_formatDate(DateTime.now())} • '
        '${items.length} item(s)</p>');
    buffer.writeln('</header>');

    // Search box (client-side filtering).
    buffer.writeln('<div class="search-box">');
    buffer.writeln(
        '<input type="text" id="search" placeholder="Search items..." '
        'oninput="filterItems()">');
    buffer.writeln('</div>');

    buffer.writeln('<main id="inventory">');
    for (final item in items) {
      final locationName = item.locationId != null
          ? locationNames[item.locationId] ?? 'Unknown'
          : 'No location';
      final value = item.valueCents != null && !item.valueUnknown
          ? '${(item.valueCents! / 100).toStringAsFixed(2)} '
              '${item.currencyCode ?? 'USD'}'
          : 'No value';

      buffer.writeln('<article class="item" '
          'data-name="${_escape(item.name.toLowerCase())}">');
      buffer.writeln('<h2>${_escape(item.name)}</h2>');
      buffer.writeln('<dl>');
      buffer.writeln(
          '<dt>Location</dt><dd>${_escape(locationName)}</dd>');
      if (item.brand != null) {
        buffer.writeln('<dt>Brand</dt><dd>${_escape(item.brand!)}</dd>');
      }
      if (item.model != null) {
        buffer.writeln('<dt>Model</dt><dd>${_escape(item.model!)}</dd>');
      }
      if (item.serialNumber != null) {
        buffer.writeln(
            '<dt>Serial</dt><dd>${_escape(item.serialNumber!)}</dd>');
      }
      buffer.writeln('<dt>Value</dt><dd>${_escape(value)}</dd>');
      if (item.notes != null && item.notes!.isNotEmpty) {
        buffer.writeln('<dt>Notes</dt><dd>${_escape(item.notes!)}</dd>');
      }
      buffer.writeln('</dl>');
      buffer.writeln('</article>');
    }
    buffer.writeln('</main>');

    buffer.writeln('<script>');
    buffer.writeln(_js);
    buffer.writeln('</script>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  String _escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static const _css = '''
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, -apple-system, sans-serif; max-width: 900px;
  margin: 0 auto; padding: 20px; background: #f5f5f5; color: #333; }
header { margin-bottom: 20px; }
header h1 { font-size: 2em; margin-bottom: 5px; }
.meta { color: #666; font-size: 0.9em; }
.search-box { margin-bottom: 20px; }
.search-box input { width: 100%; padding: 12px; font-size: 1em;
  border: 1px solid #ddd; border-radius: 8px; }
#inventory { display: grid; gap: 15px; }
.item { background: white; padding: 20px; border-radius: 8px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.item h2 { margin-bottom: 10px; font-size: 1.3em; }
.item dl { display: grid; grid-template-columns: 100px 1fr; gap: 5px 10px; }
.item dt { font-weight: 600; color: #666; }
.item dd { margin: 0; }
.item.hidden { display: none; }
@media (max-width: 600px) {
  body { padding: 10px; }
  .item dl { grid-template-columns: 1fr; }
  .item dt { margin-top: 8px; }
}
''';

  static const _js = '''
function filterItems() {
  const query = document.getElementById('search').value.toLowerCase();
  const items = document.querySelectorAll('.item');
  items.forEach(item => {
    const name = item.getAttribute('data-name');
    if (name.includes(query)) {
      item.classList.remove('hidden');
    } else {
      item.classList.add('hidden');
    }
  });
}
''';
}
