import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/belonging_meta.dart';
import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/keepit_card.dart';
import '../../../shared/widgets/keepit_chip.dart';
import '../../../shared/widgets/keepit_search_bar.dart';
import '../../locations/presentation/move_destination_sheet.dart';
import 'widgets/location_path.dart';

/// My Stuff tab: belongings filterable by archive state, category and
/// searchable across name/brand/model/serial number/notes. Defaults to
/// owned items; archived/sold/donated/disposed stay reachable via the
/// status chips.
class BelongingsScreen extends StatefulWidget {
  const BelongingsScreen({
    super.key,
    required this.belongingRepository,
    required this.locationRepository,
    required this.categoryRepository,
    required this.locationService,
    required this.placeRepository,
  });

  static const String routePath = '/stuff';

  final BelongingRepository belongingRepository;
  final LocationRepository locationRepository;
  final CategoryRepository categoryRepository;
  final LocationService locationService;
  final PlaceRepository placeRepository;

  @override
  State<BelongingsScreen> createState() => _BelongingsScreenState();
}

class _BelongingsScreenState extends State<BelongingsScreen> {
  String _query = '';
  String? _categoryId; // null = all categories
  String? _archiveState = BelongingArchiveState.owned; // null = all states
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} selected' : 'My Stuff'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: _cancelSelection,
              )
            : null,
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outlined),
                  tooltip: 'Move selected',
                  onPressed:
                      _selected.isEmpty ? null : () => _moveSelected(context),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.account_tree_outlined),
                  tooltip: 'Browse locations',
                  onPressed: () => context.push('/stuff/locations'),
                ),
              ],
      ),
      body: Column(
        children: [
          KeepitSearchBar(
            hintText: 'Search belongings by name, brand, model...',
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          _CategoryChips(
            categoryRepository: widget.categoryRepository,
            selectedId: _categoryId,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          _ArchiveStateChips(
            selected: _archiveState,
            onSelected: (state) => setState(() => _archiveState = state),
          ),
          Expanded(
            child: StreamBuilder<List<Belonging>>(
              stream: _archiveState == null
                  ? widget.belongingRepository.watchAll()
                  : widget.belongingRepository
                      .watchByArchiveStates([_archiveState!]),
              builder: (context, belongingSnapshot) {
                if (belongingSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (belongingSnapshot.hasError) {
                  return const Center(
                    child: Text('Could not load your stuff.'),
                  );
                }
                final belongings = (belongingSnapshot.data ?? const [])
                    .where((b) {
                      if (_categoryId != null &&
                          b.categoryId != _categoryId) {
                        return false;
                      }
                      if (_query.isEmpty) return true;
                      return b.name.toLowerCase().contains(_query) ||
                          (b.brand?.toLowerCase().contains(_query) ?? false) ||
                          (b.model?.toLowerCase().contains(_query) ?? false) ||
                          (b.serialNumber?.toLowerCase().contains(_query) ??
                              false) ||
                          (b.notes?.toLowerCase().contains(_query) ?? false);
                    })
                    .toList();
                final hasFilters = _query.isNotEmpty ||
                    _categoryId != null ||
                    _archiveState != BelongingArchiveState.owned;
                return StreamBuilder<List<Location>>(
                  stream: widget.locationRepository.watchAll(),
                  builder: (context, locationSnapshot) {
                    final paths = buildLocationPaths(
                      locationSnapshot.data ?? const [],
                    );
                    return FutureBuilder<Map<String, String>>(
                      future: _categoryNames(),
                      builder: (context, categorySnapshot) {
                        final categoryNames =
                            categorySnapshot.data ?? const <String, String>{};
                        if (belongings.isEmpty) {
                          return EmptyState(
                            icon: Icons.inventory_2_outlined,
                            headline: hasFilters ? 'No matches' : 'Nothing stored yet',
                            body: hasFilters
                                ? 'Try a different search, category or status filter.'
                                : 'Keep track of the things you own, where they are, and their history.',
                            actionLabel: hasFilters ? null : 'Add belonging',
                            onAction: hasFilters
                                ? null
                                : () => context.push('/stuff/new'),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 80),
                          itemCount: belongings.length,
                          itemBuilder: (context, index) {
                            final belonging = belongings[index];
                            return _BelongingTile(
                              belonging: belonging,
                              paths: paths,
                              categoryName: belonging.categoryId == null
                                  ? null
                                  : categoryNames[belonging.categoryId],
                              selected: _selected.contains(belonging.id),
                              selecting: _selecting,
                              onTap: () {
                                if (_selecting) {
                                  _toggleSelected(belonging.id);
                                } else {
                                  context
                                      .push('/stuff/${belonging.id}');
                                }
                              },
                              onLongPress: () =>
                                  _toggleSelected(belonging.id),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/stuff/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add belonging'),
      ),
    );
  }

  Future<Map<String, String>> _categoryNames() async {
    final categories = await widget.categoryRepository.getAll();
    return {for (final c in categories) c.id: c.name};
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.remove(id)) {
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
        _selecting = true;
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _moveSelected(BuildContext context) async {
    final ids = Set<String>.from(_selected);
    final excluded =
        await containerMoveExclusions(widget.locationService, ids);
    if (!context.mounted) return;
    final destination = await showMoveDestinationSheet(
      context: context,
      locationRepository: widget.locationRepository,
      belongingRepository: widget.belongingRepository,
      locationService: widget.locationService,
      placeRepository: widget.placeRepository,
      excludeContainerIds: excluded,
      title: 'Move ${ids.length} item${ids.length == 1 ? '' : 's'} to…',
    );
    if (destination == null || !context.mounted) return;
    try {
      switch (destination) {
        case MoveToLocation(:final locationId):
          await widget.belongingRepository
              .moveItemsToLocation(ids, locationId);
        case MoveToContainer(:final containerId):
          await widget.belongingRepository
              .moveItemsToContainer(ids, containerId);
      }
      _cancelSelection();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not move items: $e')),
        );
      }
    }
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categoryRepository,
    required this.selectedId,
    required this.onSelected,
  });

  final CategoryRepository categoryRepository;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Category>>(
      future: categoryRepository.getAll(),
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <Category>[];
        if (categories.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              KeepitFilterChip(
                label: 'All',
                selected: selectedId == null,
                onSelected: (_) => onSelected(null),
              ),
              const SizedBox(width: 8),
              for (final category in categories) ...[
                KeepitFilterChip(
                  label: category.name,
                  selected: selectedId == category.id,
                  onSelected: (selected) =>
                      onSelected(selected ? category.id : null),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ArchiveStateChips extends StatelessWidget {
  const _ArchiveStateChips({
    required this.selected,
    required this.onSelected,
  });

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          KeepitFilterChip(
            label: 'All states',
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          for (final state in BelongingArchiveState.all) ...[
            KeepitFilterChip(
              label: BelongingArchiveState.labels[state]!,
              selected: selected == state,
              onSelected: (isSelected) => onSelected(isSelected ? state : null),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _BelongingTile extends StatelessWidget {
  const _BelongingTile({
    required this.belonging,
    required this.paths,
    this.categoryName,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
  });

  final Belonging belonging;
  final Map<String, String> paths;
  final String? categoryName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = StringBuffer();
    if (categoryName != null) subtitle.write(categoryName);
    if (belonging.brand != null && belonging.brand!.isNotEmpty) {
      if (subtitle.isNotEmpty) subtitle.write(' · ');
      subtitle.write(belonging.brand);
    }
    if (belonging.model != null && belonging.model!.isNotEmpty) {
      if (subtitle.isNotEmpty) subtitle.write(' ');
      subtitle.write(belonging.model);
    }
    if (belonging.quantity > 1) {
      if (subtitle.isNotEmpty) subtitle.write(' · ');
      subtitle.write('×${belonging.quantity}');
    }
    final archived = belonging.archiveState != BelongingArchiveState.owned;

    return KeepitCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      borderRadius: 14,
      color: selected
          ? theme.colorScheme.primaryContainer.withAlpha(80)
          : null,
      borderColor: selected
          ? theme.colorScheme.primary
          : null,
      onTap: onTap,
      child: Row(
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Checkbox(
                value: selected,
                onChanged: (_) => onTap?.call(),
              ),
            )
          else
            _PhotoThumb(photoPath: belonging.photoPath),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        belonging.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (belonging.valueCents != null)
                      Text(
                        formatMoney(belonging.valueCents!, belonging.currencyCode ?? 'USD'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 13,
                      color: belonging.locationId == null
                          ? theme.colorScheme.onSurfaceVariant.withAlpha(140)
                          : AppColors.mintAccent,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: LocationPathText(
                        locationId: belonging.locationId,
                        paths: paths,
                      ),
                    ),
                    if (archived)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          BelongingArchiveState.labels[belonging.archiveState] ??
                              belonging.archiveState,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({this.photoPath});

  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = photoPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 46,
        height: 46,
        child: path == null || path.isEmpty
            ? Container(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}
