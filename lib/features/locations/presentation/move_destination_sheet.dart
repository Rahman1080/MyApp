import 'package:flutter/material.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../shared/services/location_service.dart';
import '../../belongings/presentation/widgets/location_path.dart';

/// Where a move should go: a location (null = no location) or a container.
sealed class MoveDestination {
  const MoveDestination();
}

class MoveToLocation extends MoveDestination {
  const MoveToLocation(this.locationId);
  final String? locationId;
}

class MoveToContainer extends MoveDestination {
  const MoveToContainer(this.containerId);
  final String containerId;
}

/// Ids that must not be offered as a container target when moving [ids]:
/// the items themselves plus everything nested inside them (picking any of
/// those would create a container cycle).
Future<Set<String>> containerMoveExclusions(
  LocationService locationService,
  Set<String> ids,
) async {
  final excluded = <String>{...ids};
  for (final id in ids) {
    for (final descendant in await locationService.containerDescendants(id)) {
      excluded.add(descendant.id);
    }
  }
  return excluded;
}

/// Bottom sheet to pick a move destination: a location in the place tree,
/// a container, or (optionally) "no location".
///
/// [excludeContainerIds] hides containers that would create a cycle.
/// [allowContainers] and [allowClear] toggle the containers section and the
/// "no location" row.
Future<MoveDestination?> showMoveDestinationSheet({
  required BuildContext context,
  required LocationRepository locationRepository,
  required BelongingRepository belongingRepository,
  required LocationService locationService,
  required PlaceRepository placeRepository,
  Set<String> excludeContainerIds = const {},
  bool allowContainers = true,
  bool allowClear = true,
  String title = 'Move to…',
}) {
  return showModalBottomSheet<MoveDestination>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _MoveDestinationSheet(
        title: title,
        scrollController: scrollController,
        locationRepository: locationRepository,
        belongingRepository: belongingRepository,
        locationService: locationService,
        placeRepository: placeRepository,
        excludeContainerIds: excludeContainerIds,
        allowContainers: allowContainers,
        allowClear: allowClear,
      ),
    ),
  );
}

class _MoveDestinationSheet extends StatefulWidget {
  const _MoveDestinationSheet({
    required this.title,
    required this.scrollController,
    required this.locationRepository,
    required this.belongingRepository,
    required this.locationService,
    required this.placeRepository,
    required this.excludeContainerIds,
    required this.allowContainers,
    required this.allowClear,
  });

  final String title;
  final ScrollController scrollController;
  final LocationRepository locationRepository;
  final BelongingRepository belongingRepository;
  final LocationService locationService;
  final PlaceRepository placeRepository;
  final Set<String> excludeContainerIds;
  final bool allowContainers;
  final bool allowClear;

  @override
  State<_MoveDestinationSheet> createState() => _MoveDestinationSheetState();
}

class _MoveDestinationSheetState extends State<_MoveDestinationSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _placeId; // null = all places
  List<Place> _places = const [];
  List<Location> _locations = const [];
  List<Belonging> _containers = const [];
  Map<String, String> _paths = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final places = await widget.placeRepository.getAll();
    final locations = await widget.locationRepository.getAll();
    final containers = await widget.belongingRepository.containers();
    final paths = buildLocationPaths(locations, places: places);
    // Pre-resolve container paths for subtitles.
    final containerPaths = <String, String>{};
    for (final container in containers) {
      containerPaths[container.id] =
          await widget.locationService.belongingWherePath(container);
    }
    if (mounted) {
      setState(() {
        _places = places;
        _locations = locations;
        _containers = containers;
        _paths = {...paths, ...containerPaths};
        _loaded = true;
      });
    }
  }

  List<Location> get _filteredLocations {
    var list = _placeId == null
        ? _locations
        : _locations.where((l) => l.placeId == _placeId).toList();
    if (_query.isNotEmpty) {
      list = list.where((l) => l.name.toLowerCase().contains(_query)).toList();
    }
    return list;
  }

  List<Belonging> get _filteredContainers {
    var list = _containers
        .where((c) => !widget.excludeContainerIds.contains(c.id))
        .toList();
    if (_placeId != null) {
      // Keep containers that live in the selected place, or that have no
      // location yet (their place is undecided).
      final placeId = _placeId!;
      final locationPlace = <String, String>{
        for (final l in _locations) l.id: l.placeId,
      };
      list = list.where((c) {
        final locationId = c.locationId;
        if (locationId == null) return true;
        return locationPlace[locationId] == placeId;
      }).toList();
    }
    if (_query.isNotEmpty) {
      list = list
          .where((c) => c.name.toLowerCase().contains(_query))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              widget.title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search locations or boxes…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_places.length > 1)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  ChoiceChip(
                    label: const Text('All places'),
                    selected: _placeId == null,
                    onSelected: (_) =>
                        setState(() => _placeId = null),
                  ),
                  const SizedBox(width: 8),
                  for (final place in _places) ...[
                    ChoiceChip(
                      label: Text(place.name),
                      selected: _placeId == place.id,
                      onSelected: (_) =>
                          setState(() => _placeId = place.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          if (!_loaded)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                children: [
                  if (widget.allowClear && _query.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.location_off_outlined),
                      title: const Text('No location'),
                      subtitle: const Text(
                          'Remove from any location or container'),
                      onTap: () => Navigator.of(context)
                          .pop(const MoveToLocation(null)),
                    ),
                  if (_filteredLocations.isNotEmpty) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Locations',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (final entry
                        in flattenLocationTree(_filteredLocations))
                      ListTile(
                        leading: Icon(
                          entry.depth == 0
                              ? Icons.home_outlined
                              : Icons.subdirectory_arrow_right,
                        ),
                        title: Padding(
                          padding: EdgeInsets.only(
                              left: entry.depth * 16.0),
                          child: Text(entry.location.name),
                        ),
                        subtitle: _paths[entry.location.id] != null &&
                                _paths[entry.location.id] !=
                                    entry.location.name
                            ? Padding(
                                padding: EdgeInsets.only(
                                    left: entry.depth * 16.0),
                                child: Text(
                                  _paths[entry.location.id]!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(
                          MoveToLocation(entry.location.id),
                        ),
                      ),
                  ],
                  if (widget.allowContainers) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Boxes & containers',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (_filteredContainers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text('No boxes available.'),
                      ),
                    for (final container in _filteredContainers)
                      ListTile(
                        leading:
                            const Icon(Icons.inventory_2_outlined),
                        title: Text(container.name),
                        subtitle: (_paths[container.id] ?? '').isEmpty
                            ? null
                            : Text(
                                _paths[container.id]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                        onTap: () => Navigator.of(context).pop(
                          MoveToContainer(container.id),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet to pick one or more belongings (e.g. to put into a box).
/// Items already in [excludeIds] are hidden. Returns the picked ids.
Future<Set<String>?> showItemPickerSheet({
  required BuildContext context,
  required BelongingRepository belongingRepository,
  Set<String> excludeIds = const {},
  bool excludeContainers = false,
  String title = 'Add items',
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _ItemPickerSheet(
        title: title,
        scrollController: scrollController,
        belongingRepository: belongingRepository,
        excludeIds: excludeIds,
        excludeContainers: excludeContainers,
      ),
    ),
  );
}

class _ItemPickerSheet extends StatefulWidget {
  const _ItemPickerSheet({
    required this.title,
    required this.scrollController,
    required this.belongingRepository,
    required this.excludeIds,
    required this.excludeContainers,
  });

  final String title;
  final ScrollController scrollController;
  final BelongingRepository belongingRepository;
  final Set<String> excludeIds;
  final bool excludeContainers;

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  final _searchController = TextEditingController();
  final _picked = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              widget.title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search items…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Belonging>>(
              stream: widget.belongingRepository.watchAll(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                var items = snapshot.data!
                    .where((b) =>
                        !widget.excludeIds.contains(b.id) &&
                        !(widget.excludeContainers &&
                            b.isContainer))
                    .toList();
                if (_query.isNotEmpty) {
                  items = items
                      .where((b) =>
                          b.name.toLowerCase().contains(_query) ||
                          (b.brand
                                  ?.toLowerCase()
                                  .contains(_query) ??
                              false))
                      .toList();
                }
                if (items.isEmpty) {
                  return const Center(
                      child: Text('No items to pick.'));
                }
                return ListView.builder(
                  controller: widget.scrollController,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final picked = _picked.contains(item.id);
                    return CheckboxListTile(
                      value: picked,
                      onChanged: (_) => setState(() {
                        if (picked) {
                          _picked.remove(item.id);
                        } else {
                          _picked.add(item.id);
                        }
                      }),
                      secondary: Icon(item.isContainer
                          ? Icons.inventory_2_outlined
                          : Icons.inventory_outlined),
                      title: Text(item.name),
                      subtitle: item.brand == null
                          ? null
                          : Text(item.brand!),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_picked),
              child: Text('Add ${_picked.length} item'
                  '${_picked.length == 1 ? '' : 's'}'),
            ),
          ),
        ],
      ),
    );
  }
}
