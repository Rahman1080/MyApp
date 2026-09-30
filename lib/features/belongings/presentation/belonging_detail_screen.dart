import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/services/file_storage.dart';
import '../../documents/domain/document_service.dart';
import '../../documents/presentation/widgets/documents_section.dart';
import 'widgets/location_path.dart';

/// Detail screen for a belonging: photo, facts, tappable location
/// breadcrumb, documents, move / edit / delete actions.
class BelongingDetailScreen extends StatefulWidget {
  const BelongingDetailScreen({
    super.key,
    required this.belongingId,
    required this.belongingRepository,
    required this.locationRepository,
    required this.categoryRepository,
    required this.documentService,
    this.fileStorage,
  });

  final String belongingId;
  final BelongingRepository belongingRepository;
  final LocationRepository locationRepository;
  final CategoryRepository categoryRepository;
  final DocumentService documentService;
  final FileStorage? fileStorage;

  @override
  State<BelongingDetailScreen> createState() => _BelongingDetailScreenState();
}

class _BelongingDetailScreenState extends State<BelongingDetailScreen> {
  Belonging? _belonging;
  bool _deleting = false;

  FileStorage get _fileStorage => widget.fileStorage ?? FileStorage();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final belonging =
        await widget.belongingRepository.getById(widget.belongingId);
    if (mounted) setState(() => _belonging = belonging);
  }

  Future<void> _move() async {
    final belonging = _belonging;
    if (belonging == null) return;
    final locations = await widget.locationRepository.getAll();
    if (!mounted) return;
    final flat = flattenLocationTree(locations);
    // Empty string = "clear the location"; null = sheet dismissed.
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Move to…',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('No location'),
                    selected: belonging.locationId == null,
                    onTap: () => Navigator.of(sheetContext).pop(''),
                  ),
                  for (final entry in flat)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        '${'  ' * entry.depth}${entry.location.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: belonging.locationId == entry.location.id,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(entry.location.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return; // dismissed — leave unchanged
    final newLocationId = selected.isEmpty ? null : selected;
    if (newLocationId != belonging.locationId) {
      final companion =
          BelongingsCompanion(locationId: drift.Value(newLocationId));
      await widget.belongingRepository.update(belonging.id, companion);
      await _load();
    }
  }

  Future<void> _delete() async {
    final belonging = _belonging;
    if (belonging == null || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete belonging?'),
        content: Text(
          '“${belonging.name}” and its photo and documents will be removed. '
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
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      // Remove attached files first: documents cascade at the row level,
      // but their stored files need explicit cleanup.
      final documents =
          await widget.documentService.documentsForBelonging(belonging.id);
      for (final document in documents) {
        await widget.documentService.deleteDocument(document.id);
      }
      await _fileStorage.deleteFile(belonging.photoPath);
      await widget.belongingRepository.delete(belonging.id);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final belonging = _belonging;
    return Scaffold(
      appBar: AppBar(
        title: Text(belonging?.name ?? 'Belonging'),
        actions: [
          if (belonging != null) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: 'Move to another location',
              onPressed: _move,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit belonging',
              onPressed: () async {
                final changed =
                    await context.push('/stuff/${belonging.id}/edit');
                if (changed == true) _load();
              },
            ),
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Delete belonging',
              onPressed: _deleting ? null : _delete,
            ),
          ],
        ],
      ),
      body: belonging == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Location>>(
              stream: widget.locationRepository.watchAll(),
              builder: (context, snapshot) {
                final paths = buildLocationPaths(
                  snapshot.data ?? const [],
                );
                return FutureBuilder<String?>(
                  future: _categoryName(belonging.categoryId),
                  builder: (context, categorySnapshot) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (belonging.photoPath != null &&
                            belonging.photoPath!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(belonging.photoPath!),
                              height: 220,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                height: 120,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      size: 48),
                                ),
                              ),
                            ),
                          ),
                        if (belonging.photoPath != null &&
                            belonging.photoPath!.isNotEmpty)
                          const SizedBox(height: 16),
                        _FactRow(
                          label: 'Name',
                          value: belonging.name,
                        ),
                        if (belonging.brand != null &&
                            belonging.brand!.isNotEmpty)
                          _FactRow(
                            label: 'Brand',
                            value: belonging.brand!,
                          ),
                        if (categorySnapshot.data != null)
                          _FactRow(
                            label: 'Category',
                            value: categorySnapshot.data!,
                          ),
                        _FactRow(
                          label: 'Quantity',
                          value: '${belonging.quantity}',
                        ),
                        if (belonging.valueCents != null)
                          _FactRow(
                            label: 'Value',
                            value: formatMoney(
                              belonging.valueCents,
                              belonging.currencyCode ??
                                  defaultCurrencyCode(),
                            ),
                          ),
                        _FactRow(
                          label: 'Kept at',
                          child: belonging.locationId == null
                              ? Text(
                                  'No location set',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                )
                              : LocationPathText(
                                  locationId: belonging.locationId,
                                  paths: paths,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                  onTap: () => context.push(
                                    '/stuff/locations?focus=${Uri.encodeComponent(belonging.locationId!)}',
                                  ),
                                ),
                        ),
                        if (belonging.notes != null &&
                            belonging.notes!.isNotEmpty)
                          _FactRow(
                            label: 'Notes',
                            value: belonging.notes!,
                          ),
                        const SizedBox(height: 8),
                        DocumentsSection(
                          belongingId: belonging.id,
                          documentService: widget.documentService,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  Future<String?> _categoryName(String? categoryId) async {
    if (categoryId == null) return null;
    final category = await widget.categoryRepository.getById(categoryId);
    return category?.name;
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({this.label = '', this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: child ?? Text(value ?? '', style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
