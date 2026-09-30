import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';

/// Hierarchical location browser: drill down Home → Bedroom → Drawer,
/// breadcrumbs to climb back up. Each level shows its sub-locations and the
/// belongings stored directly in it.
///
/// [initialLocationId] opens the browser at a specific level (used by "where
/// is it?" search results); null starts at the top level.
class LocationsScreen extends StatefulWidget {
  const LocationsScreen({
    super.key,
    required this.locationRepository,
    required this.belongingRepository,
    this.initialLocationId,
  });

  static const String routePath = '/stuff/locations';

  final LocationRepository locationRepository;
  final BelongingRepository belongingRepository;
  final String? initialLocationId;

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  String? _currentId;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Add location',
            onPressed: () => context.push(
              '/stuff/locations/new'
              '${_currentId == null ? '' : '?parentId=${Uri.encodeComponent(_currentId!)}'}',
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Location>>(
        stream: widget.locationRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load locations.'));
          }
          final locations = snapshot.data ?? const <Location>[];
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
          }
          if (_currentId != null && !byId.containsKey(_currentId)) {
            _currentId = null;
          }

          final current = _currentId == null ? null : byId[_currentId];
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
              Expanded(
                child: StreamBuilder<List<Belonging>>(
                  stream: _currentId == null
                      ? widget.belongingRepository.watchAll()
                      : widget.belongingRepository
                          .watchByLocation(_currentId!),
                  builder: (context, belongingSnapshot) {
                    final belongings = (belongingSnapshot.data ??
                            const <Belonging>[])
                        .where((b) => _currentId != null
                            ? true
                            : b.locationId == null)
                        .toList();
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
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (children.isNotEmpty) ...[
                          _SectionHeader(
                              title:
                                  'Inside ${current?.name ?? 'everywhere'}'),
                          for (final child in children)
                            _LocationTile(
                              location: child,
                              allLocations: locations,
                              belongingRepository: widget.belongingRepository,
                              onOpen: () =>
                                  setState(() => _currentId = child.id),
                              onEdit: () => context.push(
                                  '/stuff/locations/${child.id}/edit'),
                              onDelete: () =>
                                  _deleteLocation(context, child, locations),
                            ),
                        ],
                        if (belongings.isNotEmpty) ...[
                          _SectionHeader(
                              title: _currentId == null
                                  ? 'Not put away'
                                  : 'Belongings here'),
                          for (final belonging in belongings)
                            Card(
                              child: ListTile(
                                leading:
                                    const Icon(Icons.inventory_2_outlined),
                                title: Text(belonging.name),
                                subtitle: belonging.brand == null
                                    ? null
                                    : Text(belonging.brand!),
                                onTap: () =>
                                    context.push('/stuff/${belonging.id}'),
                              ),
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(
          '/stuff/locations/new'
          '${_currentId == null ? '' : '?parentId=${Uri.encodeComponent(_currentId!)}'}',
        ),
        icon: const Icon(Icons.add),
        label: Text(_currentId == null ? 'Location' : 'Sub-location'),
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
    required this.belongingRepository,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Location location;
  final List<Location> allLocations;
  final BelongingRepository belongingRepository;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subCount =
        allLocations.where((l) => l.parentLocationId == location.id).length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(location.name),
        subtitle: subCount == 0
            ? null
            : Text(
                '$subCount sub-location${subCount == 1 ? '' : 's'}'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Location actions',
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: Text('Rename / move'),
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
