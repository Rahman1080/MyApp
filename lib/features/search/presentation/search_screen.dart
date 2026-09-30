import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../shared/services/global_search.dart';
import '../../../shared/services/location_service.dart';
import '../../belongings/presentation/widgets/location_path.dart';

/// "Where is it?" — one search field across purchases, receipts, belongings,
/// locations, deadlines and documents. Results are grouped by type and each
/// row navigates to its detail screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.searchService,
    required this.locationRepository,
    required this.locationService,
    required this.placeRepository,
  });

  static const String routePath = '/search';

  final GlobalSearchService searchService;
  final LocationRepository locationRepository;
  final LocationService locationService;
  final PlaceRepository placeRepository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  GlobalSearchResults? _results;
  Map<String, String> _paths = const {};
  // Belonging id -> full "where is it?" path (place > locations > container).
  Map<String, String> _wherePaths = const {};
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final locations = await widget.locationRepository.getAll();
    final places = await widget.placeRepository.getAll();
    if (mounted) {
      setState(() => _paths = buildLocationPaths(locations, places: places));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
        _hasSearched = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await widget.searchService.search(query);
    final wherePaths = <String, String>{};
    for (final belonging in results.belongings) {
      final path =
          await widget.locationService.belongingWherePath(belonging);
      if (path.isNotEmpty) wherePaths[belonging.id] = path;
    }
    if (mounted) {
      setState(() {
        _results = results;
        _wherePaths = wherePaths;
        _searching = false;
        _hasSearched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search everything…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                          setState(() {});
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: _runSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_searching)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: results == null
                ? _EmptyHint(hasSearched: _hasSearched)
                : results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Nothing found for “${_controller.text.trim()}”.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          _Section<Purchase>(
                            title: 'Purchases',
                            items: results.purchases,
                            icon: Icons.shopping_bag_outlined,
                            titleOf: (p) => p.productName,
                            subtitleOf: (p) => p.store,
                            onTap: (p) =>
                                context.push('/purchases/${p.id}'),
                          ),
                          _Section<Receipt>(
                            title: 'Receipts',
                            items: results.receipts,
                            icon: Icons.receipt_outlined,
                            titleOf: (r) =>
                                r.store ?? 'Receipt',
                            subtitleOf: (r) => r.receiptDate == null
                                ? null
                                : DateFormat.yMMMd()
                                    .format(r.receiptDate!),
                            onTap: (r) => context
                                .push('/purchases/${r.purchaseId}'),
                          ),
                          _Section<Belonging>(
                            title: 'Belongings',
                            items: results.belongings,
                            icon: Icons.inventory_2_outlined,
                            titleOf: (b) => b.name,
                            subtitleOf: (b) => b.brand,
                            trailing: (b) {
                              final path = _wherePaths[b.id];
                              if (path == null || path.isEmpty) {
                                return LocationPathText(
                                  locationId: b.locationId,
                                  paths: _paths,
                                );
                              }
                              return Tooltip(
                                message: path,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (b.containerId != null)
                                      const Padding(
                                        padding:
                                            EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.inventory_outlined,
                                          size: 14,
                                        ),
                                      ),
                                    Flexible(
                                      child: Text(
                                        path,
                                        maxLines: 2,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onTap: (b) =>
                                context.push('/stuff/${b.id}'),
                          ),
                          _Section<Location>(
                            title: 'Locations',
                            items: results.locations,
                            icon: Icons.place_outlined,
                            titleOf: (l) => l.name,
                            trailing: (l) => LocationPathText(
                              locationId: l.id,
                              paths: _paths,
                            ),
                            onTap: (l) => context.push(
                              '/stuff/locations?focus=${Uri.encodeComponent(l.id)}',
                            ),
                          ),
                          _Section<Deadline>(
                            title: 'Deadlines',
                            items: results.deadlines,
                            icon: Icons.event_outlined,
                            titleOf: (d) => d.title,
                            subtitleOf: (d) => DateFormat.yMMMd()
                                .format(d.dueDate),
                            onTap: (d) =>
                                context.push('/deadlines/${d.id}'),
                          ),
                          _Section<Document>(
                            title: 'Documents',
                            items: results.documents,
                            icon: Icons.description_outlined,
                            titleOf: (d) => d.title,
                            subtitleOf: (d) => d.documentType,
                            onTap: (d) {
                              if (d.purchaseId != null) {
                                context.push(
                                    '/purchases/${d.purchaseId}');
                              } else if (d.belongingId != null) {
                                context
                                    .push('/stuff/${d.belongingId}');
                              }
                            },
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.hasSearched});

  final bool hasSearched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              hasSearched
                  ? 'Type to search again.'
                  : 'Where did you put it?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try “passport”, “warranty”, “kitchen”…\n'
              'Belongings show where they are kept, right in the results.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.icon,
    required this.titleOf,
    this.subtitleOf,
    this.trailing,
    required this.onTap,
  });

  final String title;
  final List<T> items;
  final IconData icon;
  final String Function(T) titleOf;
  final String? Function(T)? subtitleOf;
  final Widget? Function(T)? trailing;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            '$title (${items.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final item in items)
          Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(titleOf(item)),
              subtitle: subtitleOf == null
                  ? null
                  : () {
                      final s = subtitleOf!(item);
                      return s == null ? null : Text(s);
                    }(),
              trailing: trailing == null
                  ? null
                  : SizedBox(
                      width: 140,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing!(item),
                      ),
                    ),
              onTap: () => onTap(item),
            ),
          ),
      ],
    );
  }
}
