import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/belonging_meta.dart';
import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_history_repository.dart';
import '../../../core/database/repositories/belonging_photo_repository.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/receipt_repository.dart';
import '../../../core/database/repositories/tag_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../shared/services/location_service.dart';
import '../../../core/utilities/money.dart';
import '../../belongings/domain/lifecycle_service.dart';
import 'widgets/belonging_lifecycle_section.dart';
import 'lifetime_record_screen.dart';
import '../../../shared/services/file_storage.dart';
import '../../../shared/widgets/tag_editor.dart';
import '../../documents/domain/document_service.dart';
import '../../documents/presentation/widgets/documents_section.dart';
import '../../locations/presentation/move_destination_sheet.dart';
import 'widgets/belonging_history_section.dart';
import 'widgets/belonging_photos_section.dart';
import 'widgets/location_path.dart';

/// Detail screen for a belonging, redesigned in Phase 9 as the item's home:
/// cover photo, identity (name, brand/model), key facts (location,
/// purchased, value, condition), then one section per linked record —
/// purchase, receipt, warranty, documents, photos, notes, history.
/// Sections with no data are hidden; tags and history are always available.
class BelongingDetailScreen extends StatefulWidget {
  const BelongingDetailScreen({
    super.key,
    required this.belongingId,
    required this.belongingRepository,
    required this.locationRepository,
    required this.categoryRepository,
    required this.documentService,
    required this.purchaseRepository,
    required this.receiptRepository,
    required this.warrantyRepository,
    required this.tagRepository,
    required this.photoRepository,
    required this.historyRepository,
    required this.locationService,
    required this.placeRepository,
    required this.lifecycleService,
    this.fileStorage,
  });

  final String belongingId;
  final BelongingRepository belongingRepository;
  final LocationRepository locationRepository;
  final CategoryRepository categoryRepository;
  final DocumentService documentService;
  final PurchaseRepository purchaseRepository;
  final ReceiptRepository receiptRepository;
  final WarrantyRepository warrantyRepository;
  final TagRepository tagRepository;
  final BelongingPhotoRepository photoRepository;
  final BelongingHistoryRepository historyRepository;
  final LocationService locationService;
  final PlaceRepository placeRepository;
  final LifecycleService lifecycleService;
  final FileStorage? fileStorage;

  @override
  State<BelongingDetailScreen> createState() => _BelongingDetailScreenState();
}

/// Purchase + its receipt/warranty resolved through the item's purchase link.
class _LinkedRecords {
  const _LinkedRecords({this.purchase, this.receipt, this.warranty});

  final Purchase? purchase;
  final Receipt? receipt;
  final Warranty? warranty;

  bool get hasPurchase => purchase != null;
}

class _BelongingDetailScreenState extends State<BelongingDetailScreen> {
  Belonging? _belonging;
  _LinkedRecords? _linked;
  String _wherePath = '';
  String? _containerName;
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
    _LinkedRecords? linked;
    final purchaseId = belonging?.purchaseId;
    if (purchaseId != null) {
      final results = await Future.wait([
        widget.purchaseRepository.getById(purchaseId),
        widget.receiptRepository.getByPurchaseId(purchaseId),
        widget.warrantyRepository.getByPurchaseId(purchaseId),
      ]);
      linked = _LinkedRecords(
        purchase: results[0] as Purchase?,
        receipt: results[1] as Receipt?,
        warranty: results[2] as Warranty?,
      );
    }
    String wherePath = '';
    String? containerName;
    if (belonging != null) {
      wherePath =
          await widget.belongingRepository.wherePath(belonging.id);
      final containerId = belonging.containerId;
      if (containerId != null) {
        containerName =
            (await widget.belongingRepository.getById(containerId))?.name;
      }
    }
    if (mounted) {
      setState(() {
        _belonging = belonging;
        _linked = linked;
        _wherePath = wherePath;
        _containerName = containerName;
      });
    }
  }

  Future<void> _move() async {
    final belonging = _belonging;
    if (belonging == null) return;
    final excluded = await containerMoveExclusions(
      widget.locationService,
      {belonging.id},
    );
    if (!mounted) return;
    final destination = await showMoveDestinationSheet(
      context: context,
      locationRepository: widget.locationRepository,
      belongingRepository: widget.belongingRepository,
      locationService: widget.locationService,
      placeRepository: widget.placeRepository,
      excludeContainerIds: excluded,
      title: 'Move "${belonging.name}" to…',
    );
    if (destination == null || !mounted) return;
    try {
      switch (destination) {
        case MoveToLocation(:final locationId):
          await widget.belongingRepository.moveItemsToLocation(
            {belonging.id},
            locationId,
          );
        case MoveToContainer(:final containerId):
          await widget.belongingRepository.moveItemsToContainer(
            {belonging.id},
            containerId,
          );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not move item: $e')),
        );
      }
    }
  }

  Future<void> _changeArchiveState() async {
    final belonging = _belonging;
    if (belonging == null) return;
    final isOwned =
        belonging.archiveState == BelongingArchiveState.owned;
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
                'Item status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (isOwned) ...[
              for (final state in [
                BelongingArchiveState.archived,
                BelongingArchiveState.sold,
                BelongingArchiveState.donated,
                BelongingArchiveState.disposed,
              ])
                ListTile(
                  leading: Icon(_archiveIcon(state)),
                  title: Text(_archiveActionLabel(state)),
                  onTap: () => Navigator.of(sheetContext).pop(state),
                ),
            ] else
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Restore to owned'),
                subtitle: Text(
                  'Currently: ${BelongingArchiveState.labelOf(belonging.archiveState)}',
                ),
                onTap: () => Navigator.of(sheetContext)
                    .pop(BelongingArchiveState.owned),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    if (selected == BelongingArchiveState.sold) {
      final details = await _showSoldDialog();
      if (details == null) return;
      await widget.lifecycleService.markSold(belongingId: belonging.id, details: details);
    } else if (selected == BelongingArchiveState.donated) {
      final details = await _showDonatedDialog();
      if (details == null) return;
      await widget.lifecycleService.markDonated(belongingId: belonging.id, details: details);
    } else if (selected == BelongingArchiveState.disposed) {
      final details = await _showDisposedDialog();
      if (details == null) return;
      await widget.lifecycleService.markDisposed(belongingId: belonging.id, details: details);
    } else {
      await widget.belongingRepository.setArchiveState(belonging.id, selected);
    }

    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selected == BelongingArchiveState.owned
                ? '“${belonging.name}” is owned again.'
                : '“${belonging.name}” marked as ${BelongingArchiveState.labelOf(selected).toLowerCase()}.',
          ),
        ),
      );
    }
  }

  Future<DispositionDetails?> _showSoldDialog() async {
    final priceController = TextEditingController();
    final currencyController = TextEditingController(text: 'USD');
    final recipientController = TextEditingController();
    final notesController = TextEditingController();

    return showDialog<DispositionDetails>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as sold'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Sale price (optional)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: currencyController,
                decoration: const InputDecoration(labelText: 'Currency'),
              ),
              TextField(
                controller: recipientController,
                decoration: const InputDecoration(labelText: 'Buyer (optional)'),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final priceText = priceController.text;
              int? priceCents;
              if (priceText.isNotEmpty) {
                final val = double.tryParse(priceText);
                if (val != null) priceCents = (val * 100).toInt();
              }
              Navigator.of(context).pop(DispositionDetails(
                priceCents: priceCents,
                currencyCode: currencyController.text,
                recipient: recipientController.text,
                notes: notesController.text,
                date: DateTime.now(),
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<DispositionDetails?> _showDonatedDialog() async {
    final valueController = TextEditingController();
    final recipientController = TextEditingController();
    final notesController = TextEditingController();

    return showDialog<DispositionDetails>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as donated'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: recipientController,
                decoration: const InputDecoration(labelText: 'Organization/Recipient (optional)'),
              ),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(labelText: 'Estimated value (optional)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final priceText = valueController.text;
              int? priceCents;
              if (priceText.isNotEmpty) {
                final val = double.tryParse(priceText);
                if (val != null) priceCents = (val * 100).toInt();
              }
              Navigator.of(context).pop(DispositionDetails(
                priceCents: priceCents,
                currencyCode: 'USD',
                recipient: recipientController.text,
                notes: notesController.text,
                date: DateTime.now(),
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<DispositionDetails?> _showDisposedDialog() async {
    final notesController = TextEditingController();
    String method = BelongingDispositionMethod.trashed;

    return showDialog<DispositionDetails>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Mark as disposed'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(labelText: 'Method'),
                      items: [
                        BelongingDispositionMethod.recycled,
                        BelongingDispositionMethod.trashed,
                        BelongingDispositionMethod.lost,
                        BelongingDispositionMethod.other,
                      ].map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(BelongingDispositionMethod.labelOf(m)),
                          )).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => method = val);
                      },
                    ),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'Reason/Notes'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(DispositionDetails(
                      method: method,
                      notes: notesController.text,
                      date: DateTime.now(),
                    ));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _delete() async {
    final belonging = _belonging;
    if (belonging == null || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete belonging?'),
        content: Text(
          '“${belonging.name}”, its photos, documents and history will be '
          'permanently removed. This can\'t be undone. '
          'Consider archiving instead if you might want it back.',
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
      // Remove attached files first: documents/photos cascade at the row
      // level, but their stored files need explicit cleanup.
      final documents =
          await widget.documentService.documentsForBelonging(belonging.id);
      for (final document in documents) {
        await widget.documentService.deleteDocument(document.id);
      }
      final photos =
          await widget.photoRepository.photosFor(belonging.id);
      for (final photo in photos) {
        await _fileStorage.deleteFile(photo.filePath);
      }
      await _fileStorage.deleteFile(belonging.photoPath);
      await widget.belongingRepository.delete(belonging.id);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _logDocumentAttached() {
    return widget.historyRepository.log(
      belongingId: widget.belongingId,
      eventType: BelongingHistoryEvent.documentAdded,
      title: 'Document added',
    );
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Change item status',
              onSelected: (_) => _changeArchiveState(),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'change',
                  child: Text('Archive / mark as sold…'),
                ),
              ],
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
                    return _body(
                      context,
                      belonging,
                      paths,
                      categorySnapshot.data,
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _body(
    BuildContext context,
    Belonging belonging,
    Map<String, String> paths,
    String? categoryName,
  ) {
    final theme = Theme.of(context);
    final linked = _linked;
    final purchase = linked?.purchase;
    final brandModel = [
      if (belonging.brand != null && belonging.brand!.isNotEmpty)
        belonging.brand!,
      if (belonging.model != null && belonging.model!.isNotEmpty)
        belonging.model!,
    ].join(' · ');
    final isOwned =
        belonging.archiveState == BelongingArchiveState.owned;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (belonging.photoPath != null &&
            belonging.photoPath!.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(belonging.photoPath!),
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!isOwned)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: Icon(
                _archiveIcon(belonging.archiveState),
                size: 16,
              ),
              label: Text(
                BelongingArchiveState.labelOf(belonging.archiveState),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        Text(belonging.name, style: theme.textTheme.headlineSmall),
        if (brandModel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            brandModel,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (belonging.serialNumber != null &&
            belonging.serialNumber!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'S/N ${belonging.serialNumber!}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 8),
        TagEditor(
          tagRepository: widget.tagRepository,
          entityType: 'belonging',
          entityId: belonging.id,
          suggestions: const [
            'Important',
            'Expensive',
            'Family',
            'Work',
            'School',
            'Travel',
            'Storage',
          ],
        ),
        const SizedBox(height: 8),
        const Divider(),
        _FactRow(
          label: 'Location',
          child: belonging.containerId != null
              ? InkWell(
                  onTap: () => context.push(
                    '/stuff/${belonging.containerId!}',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Inside ${_containerName ?? 'container'}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      if (_wherePath.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 2),
                          child: Text(
                            _wherePath,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(
                              color: theme.colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : belonging.locationId == null
                  ? Text(
                      'No location set',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : LocationPathText(
                      locationId: belonging.locationId,
                      paths: paths,
                      style: theme.textTheme.bodyMedium,
                      onTap: () => context.push(
                        '/stuff/locations?focus=${Uri.encodeComponent(belonging.locationId!)}',
                      ),
                    ),
        ),
        if (purchase?.purchaseDate != null)
          _FactRow(
            label: 'Purchased',
            value: DateFormat.yMMMd().format(purchase!.purchaseDate!),
          ),
        _FactRow(
          label: 'Quantity',
          value: '${belonging.quantity}',
        ),
        _FactRow(
          label: 'Value',
          value: _valueLabel(belonging),
        ),
        if (belonging.condition != null)
          _FactRow(
            label: 'Condition',
            value: BelongingCondition.labelOf(belonging.condition),
          ),
        if (categoryName != null)
          _FactRow(label: 'Category', value: categoryName),
        const SizedBox(height: 8),
        // ---- Linked records: only sections with data are shown. ----
        if (linked?.hasPurchase ?? false) ...[
          _SectionCard(
            icon: Icons.shopping_bag_outlined,
            title: 'Purchase',
            subtitle: purchase!.productName,
            detail: [
              if (purchase.store != null) purchase.store!,
              if (purchase.purchaseDate != null)
                DateFormat.yMMMd().format(purchase.purchaseDate!),
            ].join(' · '),
            onTap: () => context.push('/purchases/${purchase.id}'),
          ),
        ],
        if (linked?.receipt != null)
          _SectionCard(
            icon: Icons.receipt_outlined,
            title: 'Receipt',
            subtitle: linked!.receipt!.store ?? 'Receipt',
            detail: [
              if (linked.receipt!.receiptDate != null)
                DateFormat.yMMMd()
                    .format(linked.receipt!.receiptDate!),
              if (linked.receipt!.totalCents != null)
                formatMoney(
                  linked.receipt!.totalCents,
                  defaultCurrencyCode(),
                ),
            ].join(' · '),
            onTap: () =>
                context.push('/purchases/${linked.receipt!.purchaseId}'),
          ),
        if (linked?.warranty != null)
          _SectionCard(
            icon: Icons.verified_outlined,
            title: 'Warranty',
            subtitle: linked!.warranty!.provider ?? 'Warranty',
            detail: [
              if (linked.warranty!.expirationDate != null)
                'Expires ${DateFormat.yMMMd().format(linked.warranty!.expirationDate!)}',
            ].join(' · '),
            onTap: () =>
                context.push('/purchases/${linked.warranty!.purchaseId}'),
          ),
        const SizedBox(height: 8),
        DocumentsSection(
          belongingId: belonging.id,
          documentService: widget.documentService,
          onDocumentAttached: _logDocumentAttached,
        ),
        if (belonging.isContainer) ...[
          const SizedBox(height: 8),
          _ContainerContentsSection(
            belonging: belonging,
            belongingRepository: widget.belongingRepository,
            onChanged: _load,
          ),
        ],
        const SizedBox(height: 8),
        BelongingPhotosSection(
          belongingId: belonging.id,
          photoRepository: widget.photoRepository,
        ),
        if (belonging.notes != null && belonging.notes!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Notes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(belonging.notes!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 8),
        BelongingLifecycleSection(
          belonging: belonging,
          lifecycleService: widget.lifecycleService,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        BelongingHistorySection(
          belongingId: belonging.id,
          historyRepository: widget.historyRepository,
        ),
        const SizedBox(height: 8),
        // Phase 22 — full lifetime record viewer.
        Card(
          child: ListTile(
            leading: const Icon(Icons.timeline_outlined),
            title: const Text('Lifetime Record'),
            subtitle: const Text(
              'Complete record: details, history, warranties, service, documents.',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => context.push(
              LifetimeRecordScreen.routePathFor(belonging.id),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _valueLabel(Belonging belonging) {
    if (belonging.valueCents != null) {
      return formatMoney(
        belonging.valueCents,
        belonging.currencyCode ?? defaultCurrencyCode(),
      );
    }
    if (belonging.valueUnknown) return 'Unknown';
    return '—';
  }

  Future<String?> _categoryName(String? categoryId) async {
    if (categoryId == null) return null;
    final category = await widget.categoryRepository.getById(categoryId);
    return category?.name;
  }
}

IconData _archiveIcon(String state) => switch (state) {
      BelongingArchiveState.sold => Icons.sell_outlined,
      BelongingArchiveState.donated => Icons.volunteer_activism_outlined,
      BelongingArchiveState.disposed => Icons.delete_outline,
      _ => Icons.archive_outlined,
    };

String _archiveActionLabel(String state) => switch (state) {
      BelongingArchiveState.archived => 'Archive',
      BelongingArchiveState.sold => 'Mark as sold',
      BelongingArchiveState.donated => 'Mark as donated',
      BelongingArchiveState.disposed => 'Mark as disposed',
      _ => BelongingArchiveState.labelOf(state),
    };

/// Tappable summary card for a linked record (purchase / receipt / warranty).
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: theme.textTheme.titleSmall),
            if (detail.isNotEmpty)
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// "What's in the box?" — contents of a container with add / remove /
/// empty actions. Used only when [belonging.isContainer] is true.
class _ContainerContentsSection extends StatelessWidget {
  const _ContainerContentsSection({
    required this.belonging,
    required this.belongingRepository,
    required this.onChanged,
  });

  final Belonging belonging;
  final BelongingRepository belongingRepository;
  final Future<void> Function() onChanged;

  Future<void> _addItems(BuildContext context) async {
    // The box itself and its current contents can never be picked (that
    // would create a cycle); deeper cycles are rejected by the repository.
    final currentContents =
        await belongingRepository.contentsOf(belonging.id);
    if (!context.mounted) return;
    final picked = await showItemPickerSheet(
      context: context,
      belongingRepository: belongingRepository,
      excludeIds: {
        belonging.id,
        for (final b in currentContents) b.id,
      },
      title: 'Add items to ${belonging.name}',
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    try {
      await belongingRepository.moveItemsToContainer(picked, belonging.id);
      await onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add items: $e')),
        );
      }
    }
  }

  Future<void> _removeItem(BuildContext context, Belonging item) async {
    await belongingRepository.removeFromContainer({item.id});
    await onChanged();
  }

  Future<void> _empty(BuildContext context, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty container?'),
        content: Text(
          'Take all $count item${count == 1 ? '' : 's'} out of '
          '"${belonging.name}"? They will be moved to the '
          "container's location.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await belongingRepository.emptyContainer(belonging.id);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<Belonging>>(
      stream: belongingRepository.watchContentsOf(belonging.id),
      builder: (context, snapshot) {
        final contents = snapshot.data ?? const <Belonging>[];
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Contents (${contents.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add items',
                      onPressed: () => _addItems(context),
                    ),
                    if (contents.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.logout_outlined),
                        tooltip: 'Empty container',
                        onPressed: () => _empty(context, contents.length),
                      ),
                  ],
                ),
                if (contents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Empty — tap + to put items in this box.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final item in contents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: item.isContainer
                        ? const Icon(Icons.inventory_2_outlined)
                        : const Icon(Icons.inventory_outlined),
                    title: Text(item.name),
                    subtitle: item.brand == null
                        ? null
                        : Text(item.brand!),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Take out of ${belonging.name}',
                      onPressed: () => _removeItem(context, item),
                    ),
                    onTap: () => context.push('/stuff/${item.id}'),
                  ),
              ],
            ),
          ),
        );
      },
    );
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
