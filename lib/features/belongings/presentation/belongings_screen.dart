import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import 'widgets/location_path.dart';

/// My Stuff tab: every belonging, filterable by category and searchable.
/// "Where did I put it?" — each row shows its location breadcrumb.
class BelongingsScreen extends StatefulWidget {
  const BelongingsScreen({
    super.key,
    required this.belongingRepository,
    required this.locationRepository,
    required this.categoryRepository,
  });

  static const String routePath = '/stuff';

  final BelongingRepository belongingRepository;
  final LocationRepository locationRepository;
  final CategoryRepository categoryRepository;

  @override
  State<BelongingsScreen> createState() => _BelongingsScreenState();
}

class _BelongingsScreenState extends State<BelongingsScreen> {
  String _query = '';
  String? _categoryId; // null = all categories

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Stuff'),
        actions: [
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
          Expanded(
            child: StreamBuilder<List<Belonging>>(
              stream: widget.belongingRepository.watchAll(),
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
                          (b.brand?.toLowerCase().contains(_query) ?? false);
                    })
                    .toList();
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
                            headline: _query.isEmpty && _categoryId == null
                                ? 'Nothing stored yet'
                                : 'No matches',
                            body: _query.isEmpty && _categoryId == null
                                ? 'Add belongings and where you keep them — '
                                    'like “Passport → Bedroom → Top drawer” — '
                                    'so you can always find them again.'
                                : 'Try a different search or category.',
                            actionLabel: _query.isEmpty && _categoryId == null
                                ? 'Add belonging'
                                : null,
                            onAction: _query.isEmpty && _categoryId == null
                                ? () => context.push('/stuff/new')
                                : null,
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
                              onTap: () =>
                                  context.push('/stuff/${belonging.id}'),
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

class _BelongingTile extends StatelessWidget {
  const _BelongingTile({
    required this.belonging,
    required this.paths,
    this.categoryName,
    this.onTap,
  });

  final Belonging belonging;
  final Map<String, String> paths;
  final String? categoryName;
  final VoidCallback? onTap;

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

    return Card(
      child: ListTile(
        leading: _PhotoThumb(photoPath: belonging.photoPath),
        title: Text(belonging.name),
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
