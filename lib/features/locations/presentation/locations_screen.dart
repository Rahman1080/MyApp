import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../shared/services/location_service.dart';

/// Household browser: places → hierarchical locations → belongings.
/// Drill down Home → Bedroom → Drawer, breadcrumbs to climb back up.
/// Each level shows its sub-locations and the belongings stored directly
/// in it, plus a simple household dashboard at the top level.
///
/// [initialLocationId] opens the browser at a specific level (used by
/// "where is it?" search results); null starts at the top level.
class LocationsScreen extends StatefulWidget {
  const LocationsScreen({
    super.key,
    required this.locationRepository,
    required this.belongingRepository,
    required this.locationService,
    required this.placeRepository,
    this.initialLocationId,
  });

  static const String routePath = '/stuff/locations';

  final LocationRepository locationRepository;
  final BelongingRepository belongingRepository;
  final LocationService locationService;
  final PlaceRepository placeRepository;
  final String? initialLocationId;

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  String? _currentId;
  String? _placeId; // null = all places
  bool _initialized = false;
  bool _showDashboard = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Places & locations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_home_outlined),
            tooltip: 'Manage places',
            onPressed: () => _managePlaces(context),
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Add location',
            onPressed: () => context.push(
              '/stuff/locations/new'
              '${_currentId == null ? '' : '?parentId=${Uri.encodeComponent(_currentId!)}'}'
              '${_placeId == null ? '' : '&placeId=${Uri.encodeComponent(_placeId!)}'}',
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Place>>(
        stream: widget.placeRepository.watchAll(),
        builder: (context, placeSnapshot) {
          final places = placeSnapshot.data ?? const <Place>[];
          return StreamBuilder<List<Location>>(
            stream: widget.locationRepository.watchAll(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Could not load locations.'));
              }
              var locations = snapshot.data ?? const <Location>[];
              final byId = <String, Location>{
                for (final l in locations) l.id: l
              };
              if (!_initialized) {
                _initialized = true;
                // Guard against a stale focus id (location deleted elsewhere).
                _currentId = widget.initialLocationId != null &&
                        byId.containsKey(widget.initialLocationId)
                    ? widget.initialLocationId
                    : null;
                final focus =
                    _currentId == null ? null : byId[_currentId];
                _placeId = focus?.placeId;
              }
              if (_currentId != null && !byId.containsKey(_currentId)) {
                _currentId = null;
              }

              final current = _currentId == null ? null : byId[_currentId];
              // When a place is selected, only show its tree. Drilling down
              // stays inside the place because children inherit the place.
              final effectivePlaceId = current?.placeId ?? _placeId;
              if (effectivePlaceId != null) {
                locations = locations
                    .where((l) => l.placeId == effectivePlaceId)
                    .toList();
              }
              final children = locations
                  .where((l) => l.parentLocationId == _currentId)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              final crumbs = _ancestors(current, byId);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Breadcrumbs(
                    crumbs: crumbs,
                    current: current,
                    onCrumb: (id) => setState(() => _currentId = id),
                  ),
                  _PlaceChips(
                    places: places,
                    selectedPlaceId: effectivePlaceId,
                    onSelected: (id) => setState(() {
                      _placeId = id;
                      _currentId = null;
                    }),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Belonging>>(
                      stream: _currentId == null
                          ? widget.belongingRepository.watchAll()
                          : widget.belongingRepository
                              .watchByLocation(_currentId!),
                      builder: (context, belongingSnapshot) {
                        final belongings = (belongingSnapshot.data ??
                                const <Belonging>[])
                            .where((b) =>
                                _currentId != null || b.locationId == null)
                            .toList()
                          ..sort((a, b) => a.name.compareTo(b.name));
                        if (children.isEmpty && belongings.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                current == null
                                    ? 'No locations yet. Add one — like “Home” — '
                                        'then nest rooms, drawers and folders '
                                        'inside it.'
                                    : '“${current.name}” is empty. Add a '
                                        'sub-location or move a belonging here.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          );
                        }
                        final containerCount = belongings
                            .where((b) => b.isContainer)
                            .length;
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_currentId == null && _showDashboard)
                              _DashboardCard(
                                belongingRepository:
                                    widget.belongingRepository,
                                onHide: () => setState(
                                    () => _showDashboard = false),
                              ),
                            if (children.isNotEmpty) ...[
                              _SectionHeader(
                                title:
                                    'Inside ${current?.name ?? 'everywhere'} (${children.length})',
                              ),
                              for (final child in children)
                                _LocationTile(
                                  location: child,
                                  allLocations: locations,
                                  locationService: widget.locationService,
                                  onOpen: () =>
                                      setState(() => _currentId = child.id),
                                  onEdit: () => context.push(
                                      '/stuff/locations/${child.id}/edit'),
                                  onMoveToPlace: () => _moveLocationToPlace(
                                      context, child, places),
                                  onDelete: () => _deleteLocation(
                                      context, child, locations),
                                ),
                            ],
                            if (belongings.isNotEmpty) ...[
                              _SectionHeader(
                                title: _currentId == null
                                    ? 'Not put away (${belongings.length})'
                                    : 'Belongings here (${belongings.length}'
                                        '${containerCount > 0 ? ', $containerCount ${containerCount == 1 ? 'box' : 'boxes'}' : ''})',
                              ),
                              for (final belonging in belongings)
                                _BelongingTile(
                                  belonging: belonging,
                                  belongingRepository:
                                      widget.belongingRepository,
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'add_box',
            tooltip: 'Add box',
            onPressed: () => context.push(
              '/stuff/new?isContainer=true'
              '${_currentId == null ? '' : '&locationId=${Uri.encodeComponent(_currentId!)}'}',
            ),
            child: const Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'add_location',
            onPressed: () => context.push(
              '/stuff/locations/new'
              '${_currentId == null ? '' : '?parentId=${Uri.encodeComponent(_currentId!)}'}'
              '${_placeId == null ? '' : '&placeId=${Uri.encodeComponent(_placeId!)}'}',
            ),
            icon: const Icon(Icons.add),
            label: Text(_currentId == null ? 'Location' : 'Sub-location'),
          ),
        ],
      ),
    );
  }

  /// Ancestor chain from the root down to (but excluding) [current].
  List<Location> _ancestors(Location? current, Map<String, Location> byId) {
    final chain = <Location>[];
    final visited = <String>{};
    var id = current?.parentLocationId;
    while (id != null && visited.add(id)) {
      final location = byId[id];
      if (location == null) break;
      chain.insert(0, location);
      id = location.parentLocationId;
    }
    return chain;
  }

  Future<void> _managePlaces(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ManagePlacesDialog(
        placeRepository: widget.placeRepository,
      ),
    );
  }

  Future<void> _moveLocationToPlace(
    BuildContext context,
    Location location,
    List<Place> places,
  ) async {
    if (places.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add another place first.')),
      );
      return;
    }
    final target = await showDialog<Place>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Move “${location.name}” to…'),
        children: [
          for (final place in places)
            if (place.id != location.placeId)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(place),
                child: Text(place.name),
              ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    await widget.locationRepository.setPlace(location.id, target.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '“${location.name}” and everything inside moved to ${target.name}.')),
      );
    }
  }

  Future<void> _deleteLocation(
    BuildContext context,
    Location location,
    List<Location> all,
  ) async {
    final childCount =
        all.where((l) => l.parentLocationId == location.id).length;
    final belongingCount =
        await widget.belongingRepository.watchByLocation(location.id).first;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${location.name}”?'),
        content: Text(
          childCount == 0
              ? 'This can\'t be undone.'
              : '$childCount sub-location${childCount == 1 ? '' : 's'} will move to the top level. '
                  'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.locationRepository.delete(location.id);
    // ignore: use_build_context_synchronously
    if (belongingCount.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${belongingCount.length} belonging${belongingCount.length == 1 ? '' : 's'} in “${location.name}” now ${belongingCount.length == 1 ? 'has' : 'have'} no location.',
          ),
        ),
      );
    }
    if (_currentId == location.id) {
      setState(() => _currentId = location.parentLocationId);
    }
  }
}

class _PlaceChips extends StatelessWidget {
  const _PlaceChips({
    required this.places,
    required this.selectedPlaceId,
    required this.onSelected,
  });

  final List<Place> places;
  final String? selectedPlaceId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (places.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              label: const Text('All places'),
              selected: selectedPlaceId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final place in places)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text(place.name),
                selected: selectedPlaceId == place.id,
                onSelected: (_) => onSelected(place.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple household dashboard: totals across the whole household.
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.belongingRepository,
    required this.onHide,
  });

  final BelongingRepository belongingRepository;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<int>>(
      future: Future.wait([
        belongingRepository.countItems(),
        belongingRepository.countContainers(),
        belongingRepository.countWithoutLocation(),
        belongingRepository.countUnknownValue(),
      ]),
      builder: (context, snapshot) {
        final values = snapshot.data ?? const [0, 0, 0, 0];
        final stats = [
          (Icons.inventory_outlined, 'Items', values[0]),
          (Icons.inventory_2_outlined, 'Boxes', values[1]),
          (Icons.location_off_outlined, 'Not put away', values[2]),
          (Icons.help_outline, 'Value unknown', values[3]),
        ];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Household',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Hide dashboard',
                      onPressed: onHide,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (final (icon, label, value) in stats)
                      Expanded(
                        child: Column(
                          children: [
                            Icon(icon, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              '$value',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ManagePlacesDialog extends StatefulWidget {
  const _ManagePlacesDialog({required this.placeRepository});

  final PlaceRepository placeRepository;

  @override
  State<_ManagePlacesDialog> createState() => _ManagePlacesDialogState();
}

class _ManagePlacesDialogState extends State<_ManagePlacesDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Places'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<List<Place>>(
          stream: widget.placeRepository.watchAll(),
          builder: (context, snapshot) {
            final places = snapshot.data ?? const <Place>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final place in places)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_outlined),
                    title: Text(place.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Rename',
                          onPressed: () => _renamePlace(context, place),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => _deletePlace(context, place),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _addPlace(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add place'),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Future<void> _addPlace(BuildContext context) async {
    final name = await _askName(context, 'New place', '');
    if (name == null || name.trim().isEmpty) return;
    await widget.placeRepository.createNamed(name.trim());
  }

  Future<void> _renamePlace(BuildContext context, Place place) async {
    final name = await _askName(context, 'Rename place', place.name);
    if (name == null || name.trim().isEmpty) return;
    try {
      await widget.placeRepository.rename(place.id, name.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not rename: $e')),
        );
      }
    }
  }

  Future<void> _deletePlace(BuildContext context, Place place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${place.name}”?'),
        content: const Text('Its locations must be moved elsewhere first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.placeRepository.delete(place.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  Future<String?> _askName(
      BuildContext context, String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Cabin, Office, Storage unit',
          ),
          onSubmitted: (_) =>
              Navigator.of(dialogContext).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.crumbs,
    required this.current,
    required this.onCrumb,
  });

  final List<Location> crumbs;
  final Location? current;
  final ValueChanged<String?> onCrumb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _Crumb(
            label: 'All locations',
            selected: current == null,
            onTap: () => onCrumb(null),
          ),
          for (final crumb in crumbs) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            _Crumb(
              label: crumb.name,
              selected: false,
              onTap: () => onCrumb(crumb.id),
            ),
          ],
          if (current != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            _Crumb(label: current!.name, selected: true, onTap: null),
          ],
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Chip(
      label: Text(label),
      backgroundColor:
          selected ? theme.colorScheme.primaryContainer : null,
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: chip,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.location,
    required this.allLocations,
    required this.locationService,
    required this.onOpen,
    required this.onEdit,
    required this.onMoveToPlace,
    required this.onDelete,
  });

  final Location location;
  final List<Location> allLocations;
  final LocationService locationService;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onMoveToPlace;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(location.name),
        // "What is here?" summary: direct sub-locations, items and boxes.
        subtitle: FutureBuilder<LocationContents>(
          future: locationService.locationContents(location.id),
          builder: (context, snapshot) {
            final summary = snapshot.data;
            final parts = <String>[];
            if (summary != null) {
              if (summary.subLocationCount > 0) {
                parts.add(
                    '${summary.subLocationCount} sub-location${summary.subLocationCount == 1 ? '' : 's'}');
              }
              if (summary.itemCount > 0) {
                parts.add(
                    '${summary.itemCount} item${summary.itemCount == 1 ? '' : 's'}');
              }
              if (summary.containerCount > 0) {
                parts.add(
                    '${summary.containerCount} box${summary.containerCount == 1 ? '' : 'es'}');
              }
            }
            if (parts.isEmpty) return const SizedBox.shrink();
            return Text(
              parts.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          },
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Location actions',
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'move_place') onMoveToPlace();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: Text('Rename / move'),
            ),
            PopupMenuItem(
              value: 'move_place',
              child: Text('Move to another place…'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _BelongingTile extends StatelessWidget {
  const _BelongingTile({
    required this.belonging,
    required this.belongingRepository,
  });

  final Belonging belonging;
  final BelongingRepository belongingRepository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(belonging.isContainer
            ? Icons.inventory_2_outlined
            : Icons.inventory_outlined),
        title: Text(belonging.name),
        subtitle: belonging.isContainer
            ? FutureBuilder<List<Belonging>>(
                future: belongingRepository.contentsOf(belonging.id),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return Text(
                    'Box · $count item${count == 1 ? '' : 's'} inside',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              )
            : (belonging.brand == null ? null : Text(belonging.brand!)),
        onTap: () => context.push('/stuff/${belonging.id}'),
      ),
    );
  }
}
