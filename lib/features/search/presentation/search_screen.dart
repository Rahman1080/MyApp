import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/global_search.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/keepit_card.dart';
import '../../../shared/widgets/keepit_search_bar.dart';
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
          KeepitSearchBar(
            controller: _controller,
            autofocus: true,
            hintText: 'Search items, receipts, places...',
            onChanged: _onQueryChanged,
            onSubmitted: _runSearch,
          ),
          if (_searching)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: results == null
                ? _EmptyHint(hasSearched: _hasSearched)
                : results.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_outlined,
                        headline: 'No results found',
                        body:
                            'Nothing matched "${_controller.text.trim()}". Try searching with fewer characters or a broader term.',
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
    return EmptyState(
      icon: Icons.manage_search_outlined,
      headline: hasSearched ? 'Search again' : 'Where did you put it?',
      body: hasSearched
          ? 'Type a query to search across purchases, belongings, receipts, and locations.'
          : 'Try "passport", "warranty", "kitchen", or a product brand name.\n'
              'Belongings show where they are kept, right in the results.',
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
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.mintAccent.withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    color: AppColors.mintAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KeepitCard(
              onTap: () => onTap(item),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.mintAccent.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: AppColors.mintAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleOf(item),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitleOf != null) ...[
                          Builder(
                            builder: (context) {
                              final sub = subtitleOf!(item);
                              if (sub == null || sub.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  sub,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!(item) ?? const SizedBox.shrink(),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
