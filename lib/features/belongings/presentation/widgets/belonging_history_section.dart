import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/belonging_meta.dart';
import '../../../../core/database/keepit_database.dart';
import '../../../../core/database/repositories/belonging_history_repository.dart';

/// "History" section for the item detail screen: a lightweight timeline of
/// what happened to the item, newest first, with an action for manual
/// entries (notes and lightweight maintenance records).
class BelongingHistorySection extends StatefulWidget {
  const BelongingHistorySection({
    super.key,
    required this.belongingId,
    required this.historyRepository,
  });

  final String belongingId;
  final BelongingHistoryRepository historyRepository;

  @override
  State<BelongingHistorySection> createState() =>
      _BelongingHistorySectionState();
}

class _BelongingHistorySectionState extends State<BelongingHistorySection> {
  Future<void> _addEntry() async {
    final controller = TextEditingController();
    var eventType = BelongingHistoryEvent.note;
    final result = await showDialog<({String text, String eventType})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add to history'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: BelongingHistoryEvent.note,
                    label: Text('Note'),
                    icon: Icon(Icons.note_outlined),
                  ),
                  ButtonSegment(
                    value: BelongingHistoryEvent.maintenance,
                    label: Text('Maintenance'),
                    icon: Icon(Icons.build_outlined),
                  ),
                ],
                selected: {eventType},
                onSelectionChanged: (selected) =>
                    setDialogState(() => eventType = selected.single),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: eventType == BelongingHistoryEvent.maintenance
                      ? 'e.g. Oiled the chain, replaced brake pads'
                      : 'e.g. Lent to Alex for the weekend',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop((
                text: controller.text.trim(),
                eventType: eventType,
              )),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.text.isEmpty || !mounted) return;
    await widget.historyRepository.log(
      belongingId: widget.belongingId,
      eventType: result.eventType,
      title: result.text,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('History', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.note_add_outlined),
              tooltip: 'Add a note or maintenance entry',
              onPressed: _addEntry,
            ),
          ],
        ),
        StreamBuilder<List<BelongingHistoryData>>(
          stream: widget.historyRepository.watchFor(widget.belongingId),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <BelongingHistoryData>[];
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Nothing recorded yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  _HistoryRow(
                    entry: entries[i],
                    isLast: i == entries.length - 1,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.isLast});

  final BelongingHistoryData entry;
  final bool isLast;

  IconData get _icon => switch (entry.eventType) {
        BelongingHistoryEvent.created => Icons.add_circle_outline,
        BelongingHistoryEvent.purchased => Icons.shopping_bag_outlined,
        BelongingHistoryEvent.moved => Icons.drive_file_move_outlined,
        BelongingHistoryEvent.warrantyAdded => Icons.verified_outlined,
        BelongingHistoryEvent.documentAdded => Icons.description_outlined,
        BelongingHistoryEvent.photoAdded => Icons.photo_outlined,
        BelongingHistoryEvent.archived => Icons.archive_outlined,
        BelongingHistoryEvent.unarchived => Icons.unarchive_outlined,
        BelongingHistoryEvent.sold => Icons.sell_outlined,
        BelongingHistoryEvent.donated => Icons.volunteer_activism_outlined,
        BelongingHistoryEvent.disposed => Icons.delete_outline,
        BelongingHistoryEvent.note => Icons.note_outlined,
        BelongingHistoryEvent.maintenance => Icons.build_outlined,
        _ => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(_icon,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 4 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: theme.textTheme.bodyMedium),
                  Text(
                    DateFormat.yMMMd().add_jm().format(
                        entry.occurredAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.details != null &&
                      entry.details!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.details!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
