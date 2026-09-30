import 'package:flutter/material.dart';

import '../../../../core/database/keepit_database.dart';

/// Builds id → "My Home > Bedroom > Drawer" display strings from a flat list
/// of [Location]s. When [places] is given, each path is prefixed with its
/// place name. Cycle-safe: a location that loops back on itself is rendered
/// with the names collected before the repeat.
Map<String, String> buildLocationPaths(List<Location> locations,
    {List<Place> places = const [], String separator = ' > '}) {
  final byId = <String, Location>{for (final l in locations) l.id: l};
  final placeNames = <String, String>{for (final p in places) p.id: p.name};
  final paths = <String, String>{};
  for (final location in locations) {
    final names = <String>[];
    final visited = <String>{};
    Location? current = location;
    while (current != null && visited.add(current.id)) {
      names.insert(0, current.name);
      final parentId = current.parentLocationId;
      current = parentId == null ? null : byId[parentId];
    }
    final placeName = placeNames[location.placeId];
    if (placeName != null) names.insert(0, placeName);
    paths[location.id] = names.join(separator);
  }
  return paths;
}

/// Returns the locations of [locations] ordered as a flattened tree:
/// each entry carries its depth so a picker can indent it.
List<({Location location, int depth})> flattenLocationTree(
    List<Location> locations) {
  final byParent = <String?, List<Location>>{};
  for (final location in locations) {
    byParent.putIfAbsent(location.parentLocationId, () => []).add(location);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.name.compareTo(b.name));
  }
  final result = <({Location location, int depth})>[];
  void visit(String? parentId, int depth, Set<String> visiting) {
    for (final child in byParent[parentId] ?? const <Location>[]) {
      // Cycle-safe: never descend into a location already on this path.
      if (!visiting.add(child.id)) continue;
      result.add((location: child, depth: depth));
      visit(child.id, depth + 1, visiting);
      visiting.remove(child.id);
    }
  }

  visit(null, 0, <String>{});
  return result;
}

/// Small one-line breadcrumb ("Home > Bedroom > Drawer") for a location,
/// resolved from a precomputed [paths] map. Renders nothing when the location
/// is unknown or unset.
class LocationPathText extends StatelessWidget {
  const LocationPathText({
    super.key,
    required this.locationId,
    required this.paths,
    this.onTap,
    this.style,
    this.maxLines = 1,
  });

  final String? locationId;
  final Map<String, String> paths;
  final VoidCallback? onTap;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final id = locationId;
    final path = id == null ? null : paths[id];
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    final text = Text(
      path,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style ??
          Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
    );
    if (onTap == null) return text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined, size: 14),
          const SizedBox(width: 4),
          Flexible(child: text),
        ],
      ),
    );
  }
}
