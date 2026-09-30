import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/move_item_repository.dart';
import '../../../core/database/repositories/move_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../domain/move_service.dart';

/// Detail screen for one move: progress, items by status/box, and actions.
class MoveDetailScreen extends StatefulWidget {
  static const routePath = '/moves/:id';

  const MoveDetailScreen({
    super.key,
    required this.moveId,
    required this.moveRepository,
    required this.moveItemRepository,
    required this.belongingRepository,
    required this.locationRepository,
    required this.placeRepository,
    required this.moveService,
  });

  final String moveId;
  final MoveRepository moveRepository;
  final MoveItemRepository moveItemRepository;
  final BelongingRepository belongingRepository;
  final LocationRepository locationRepository;
  final PlaceRepository placeRepository;
  final MoveService moveService;

  @override
  State<MoveDetailScreen> createState() => _MoveDetailScreenState();
}

class _MoveDetailScreenState extends State<MoveDetailScreen> {
  final _dateFormat = DateFormat.yMMMd();
  bool _busy = false;

  Future<void> _withBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addItems() async {
    final belongings = await widget.belongingRepository.getAll();
    final moveItems = await widget.moveItemRepository.forMove(widget.moveId);
    final inMove = moveItems.map((i) => i.belongingId).toSet();
    final candidates = belongings.where((b) => !inMove.contains(b.id)).toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      _snack('Every item is already in this move.');
      return;
    }
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _PickItemsDialog(candidates: candidates),
    );
    if (selected == null || selected.isEmpty) return;
    await _withBusy(() async {
      final added = await widget.moveItemRepository.addAll(
        moveId: widget.moveId,
        belongingIds: selected.toList(),
      );
      _snack('Added $added item(s) to the move.');
    });
  }

  Future<void> _addFromPlace() async {
    final move = await widget.moveRepository.getById(widget.moveId);
    final fromPlaceId = move?.fromPlaceId;
    if (fromPlaceId == null) {
      _snack('This move has no "from" place set.');
      return;
    }
    await _withBusy(() async {
      final added = await widget.moveService.addPlaceContents(
        widget.moveId,
        fromPlaceId,
      );
      _snack('Added $added item(s) from the source place.');
    });
  }

  Future<void> _advanceMove() async {
    await _withBusy(() async {
      await widget.moveRepository.advanceStatus(widget.moveId);
    });
  }

  Future<void> _completeMove() async {
    final locations = await widget.locationRepository.getAll();
    if (!mounted) return;
    final destinationId = await showDialog<String>(
      context: context,
      builder: (context) => _PickDestinationDialog(locations: locations),
    );
    if (!mounted) return;
    // Null destination is allowed (user cancelled is also null — treat
    // "no selection + confirm" via the dialog's explicit button).
    await _withBusy(() async {
      await widget.moveService.completeMove(
        widget.moveId,
        destinationLocationId: destinationId,
      );
      _snack('Move completed.');
    });
  }

  Future<void> _cancelMove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel move?'),
        content: const Text(
          'The move will be marked cancelled. Your items stay exactly '
          'where they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel move'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _withBusy(() async {
        await widget.moveRepository.cancel(widget.moveId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Move?>(
      stream: widget.moveRepository.watchById(widget.moveId),
      builder: (context, snapshot) {
        final move = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (move == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Move not found.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(move.name),
            actions: [
              if (!MoveStatus.isTerminal(move.status))
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'advance':
                        _advanceMove();
                      case 'complete':
                        _completeMove();
                      case 'cancel':
                        _cancelMove();
                    }
                  },
                  itemBuilder: (context) => [
                    if (MoveStatus.next(move.status) != null)
                      PopupMenuItem(
                        value: 'advance',
                        child: Text(
                          'Advance to ${MoveStatus.label(MoveStatus.next(move.status)!)}',
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'complete',
                      child: Text('Complete move...'),
                    ),
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Cancel move'),
                    ),
                  ],
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoveHeader(move: move, dateFormat: _dateFormat),
                const SizedBox(height: 12),
                _ProgressCard(moveId: move.id, moveService: widget.moveService),
                const SizedBox(height: 12),
                if (!MoveStatus.isTerminal(move.status)) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _addItems,
                        icon: const Icon(Icons.add_outlined),
                        label: const Text('Add items'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _addFromPlace,
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('Add from source place'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _MoveItemsList(
                  moveId: move.id,
                  moveItemRepository: widget.moveItemRepository,
                  belongingRepository: widget.belongingRepository,
                  moveService: widget.moveService,
                  editable: !MoveStatus.isTerminal(move.status),
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoveHeader extends StatelessWidget {
  const _MoveHeader({required this.move, required this.dateFormat});

  final Move move;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    MoveStatus.label(move.status),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (move.moveDate != null)
                  Chip(
                    label: Text(dateFormat.format(move.moveDate!)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (move.notes != null && move.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(move.notes!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatefulWidget {
  const _ProgressCard({required this.moveId, required this.moveService});

  final String moveId;
  final MoveService moveService;

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MoveProgress>(
      future: widget.moveService.progress(widget.moveId),
      builder: (context, snapshot) {
        final progress = snapshot.data;
        if (progress == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${progress.total} item(s) · ${progress.boxCount} box(es)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _bar(context, 'Packed', progress.packedFraction),
                const SizedBox(height: 4),
                _bar(context, 'Unpacked', progress.unpackedFraction),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, String label, double fraction) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(child: LinearProgressIndicator(value: fraction)),
        const SizedBox(width: 8),
        Text('${(fraction * 100).round()}%'),
      ],
    );
  }
}

class _MoveItemsList extends StatelessWidget {
  const _MoveItemsList({
    required this.moveId,
    required this.moveItemRepository,
    required this.belongingRepository,
    required this.moveService,
    required this.editable,
    required this.onChanged,
  });

  final String moveId;
  final MoveItemRepository moveItemRepository;
  final BelongingRepository belongingRepository;
  final MoveService moveService;
  final bool editable;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MoveItem>>(
      stream: moveItemRepository.watchForMove(moveId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No items in this move yet. Add items to start.'),
            ),
          );
        }
        // Group by status.
        final byStatus = <String, List<MoveItem>>{};
        for (final item in items) {
          byStatus.putIfAbsent(item.status, () => []).add(item);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final status in MoveItemStatus.all)
              if (byStatus[status]?.isNotEmpty ?? false)
                _StatusGroup(
                  status: status,
                  items: byStatus[status]!,
                  moveItemRepository: moveItemRepository,
                  belongingRepository: belongingRepository,
                  moveService: moveService,
                  editable: editable,
                  onChanged: onChanged,
                ),
          ],
        );
      },
    );
  }
}

class _StatusGroup extends StatelessWidget {
  const _StatusGroup({
    required this.status,
    required this.items,
    required this.moveItemRepository,
    required this.belongingRepository,
    required this.moveService,
    required this.editable,
    required this.onChanged,
  });

  final String status;
  final List<MoveItem> items;
  final MoveItemRepository moveItemRepository;
  final BelongingRepository belongingRepository;
  final MoveService moveService;
  final bool editable;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final next = MoveItemStatus.next(status);
    return Card(
      child: ExpansionTile(
        title: Text('${MoveItemStatus.label(status)} (${items.length})'),
        initiallyExpanded: status == MoveItemStatus.toPack,
        children: [
          if (editable && next != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await moveItemRepository.setStatusBulk(
                      items.map((i) => i.id).toList(),
                      next,
                    );
                    onChanged();
                  },
                  icon: const Icon(Icons.done_all_outlined),
                  label: Text(
                    'Mark all as ${MoveItemStatus.label(next).toLowerCase()}',
                  ),
                ),
              ),
            ),
          for (final item in items)
            _MoveItemTile(
              item: item,
              moveItemRepository: moveItemRepository,
              belongingRepository: belongingRepository,
              editable: editable,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _MoveItemTile extends StatelessWidget {
  const _MoveItemTile({
    required this.item,
    required this.moveItemRepository,
    required this.belongingRepository,
    required this.editable,
    required this.onChanged,
  });

  final MoveItem item;
  final MoveItemRepository moveItemRepository;
  final BelongingRepository belongingRepository;
  final bool editable;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Belonging?>(
      future: belongingRepository.getById(item.belongingId),
      builder: (context, snapshot) {
        final belonging = snapshot.data;
        final next = MoveItemStatus.next(item.status);
        return ListTile(
          dense: true,
          title: Text(belonging?.name ?? 'Unknown item'),
          subtitle: item.boxLabel != null && item.boxLabel!.isNotEmpty
              ? Text('Box: ${item.boxLabel}')
              : null,
          trailing: editable && next != null
              ? IconButton(
                  icon: const Icon(Icons.check_outlined),
                  tooltip:
                      'Mark as ${MoveItemStatus.label(next).toLowerCase()}',
                  onPressed: () async {
                    await moveItemRepository.advance(item.id);
                    onChanged();
                  },
                )
              : editable
              ? IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove from move',
                  onPressed: () async {
                    await moveItemRepository.remove(item.id);
                    onChanged();
                  },
                )
              : null,
        );
      },
    );
  }
}

class _PickItemsDialog extends StatefulWidget {
  const _PickItemsDialog({required this.candidates});

  final List<Belonging> candidates;

  @override
  State<_PickItemsDialog> createState() => _PickItemsDialogState();
}

class _PickItemsDialogState extends State<_PickItemsDialog> {
  final _selected = <String>{};
  var _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.candidates
        .where((b) => b.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text('Add items to move'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search_outlined),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final belonging = filtered[index];
                  final selected = _selected.contains(belonging.id);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(belonging.name),
                    value: selected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(belonging.id);
                      } else {
                        _selected.remove(belonging.id);
                      }
                    }),
                  );
                },
              ),
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
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text('Add (${_selected.length})'),
        ),
      ],
    );
  }
}

class _PickDestinationDialog extends StatefulWidget {
  const _PickDestinationDialog({required this.locations});

  final List<Location> locations;

  @override
  State<_PickDestinationDialog> createState() => _PickDestinationDialogState();
}

class _PickDestinationDialogState extends State<_PickDestinationDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete move'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivered items will be marked unpacked. Optionally, re-home '
            'them to a destination location now:',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedId,
            decoration: const InputDecoration(
              labelText: 'Destination location',
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Keep current locations'),
              ),
              for (final location in widget.locations)
                DropdownMenuItem(
                  value: location.id,
                  child: Text(location.name),
                ),
            ],
            onChanged: (v) => setState(() => _selectedId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedId),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}
