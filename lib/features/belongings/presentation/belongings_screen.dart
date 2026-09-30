import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/belonging_meta.dart';
import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/widgets/empty_state.dart';
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
                  icon: const Icon(Icons.search),
                  tooltip: 'Search everything',
                  onPressed: () => context.push('/search'),
                ),
                IconButton(
                  icon: const Icon(Icons.account_tree_outlined),
                  tooltip: 'Browse locations',
                  onPressed: () => context.push('/stuff/locations'),
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search belongings…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
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
                                ? 'Try a different search, category or status.'
                                : 'Add belongings and where you keep them — '
                                    'like “Passport → Bedroom → Top drawer” — '
                                    'so you can always find them again.',
                            actionLabel: hasFilters ? null : 'Add belonging',
                            onAction: hasFilters
                                ? null
                                : () => context.push('/stuff/new'),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: belongings.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
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
        label: const Text('Belonging'),
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
        if (categories.isEmpty) return const SizedBox(height: 8);
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: selectedId == null,
                onSelected: (_) => onSelected(null),
              ),
              const SizedBox(width: 8),
              for (final category in categories) ...[
                ChoiceChip(
                  label: Text(category.name),
                  selected: selectedId == category.id,
                  onSelected: (_) => onSelected(category.id),
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

  final String? selected; // null = all states
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          ChoiceChip(
            label: const Text('All statuses'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          for (final state in BelongingArchiveState.all) ...[
            ChoiceChip(
              label: Text(BelongingArchiveState.labels[state]!),
              selected: selected == state,
              onSelected: (_) => onSelected(state),
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
    if (belonging.quantity != 1) {
      if (subtitle.isNotEmpty) subtitle.write(' · ');
      subtitle.write('×${belonging.quantity}');
    }
    final archived = belonging.archiveState != BelongingArchiveState.owned;

    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: selecting
            ? Checkbox(
                value: selected,
                onChanged: (_) => onTap?.call(),
              )
            : _PhotoThumb(photoPath: belonging.photoPath),
        title: Row(
          children: [
            Expanded(child: Text(belonging.name)),
            if (archived)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  BelongingArchiveState.labels[belonging.archiveState] ??
                      belonging.archiveState,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle.isNotEmpty) Text(subtitle.toString()),
            LocationPathText(
              locationId: belonging.locationId,
              paths: paths,
            ),
          ],
        ),
        trailing: belonging.locationId == null
            ? Icon(
                Icons.help_outline,
                color: theme.colorScheme.onSurfaceVariant,
                semanticLabel: 'No location set',
              )
            : null,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({this.photoPath});

  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: path == null || path.isEmpty
            ? Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.inventory_2_outlined),
              )
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}
