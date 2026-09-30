import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/reminder_repository.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reminder_coordinator.dart';
import '../../../shared/services/reminder_planner.dart';
import '../../../shared/services/reminder_scheduler.dart';
import 'deadline_form_screen.dart';

/// Detail view for one deadline: date/time, repeat, category, notes, linked
/// purchase, scheduled reminders, and mark-done/reopen/edit/delete actions.
///
/// Completing a repeating deadline rolls it forward to its next occurrence
/// and keeps the existing reminder offsets; a non-repeating deadline is
/// simply marked done and its reminders cleared.
class DeadlineDetailScreen extends StatefulWidget {
  const DeadlineDetailScreen({
    super.key,
    required this.deadlineId,
    required this.deadlineRepository,
    required this.categoryRepository,
    required this.purchaseRepository,
    required this.reminderRepository,
    required this.reminderCoordinator,
    required this.notificationService,
  });

  final String deadlineId;
  final DeadlineRepository deadlineRepository;
  final CategoryRepository categoryRepository;
  final PurchaseRepository purchaseRepository;
  final ReminderRepository reminderRepository;
  final ReminderCoordinator reminderCoordinator;
  final NotificationService notificationService;

  @override
  State<DeadlineDetailScreen> createState() => _DeadlineDetailScreenState();
}

class _DeadlineDetailScreenState extends State<DeadlineDetailScreen> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final deadline = await widget.deadlineRepository.requireById(
      widget.deadlineId,
    );
    Category? category;
    if (deadline.categoryId != null) {
      category =
          await widget.categoryRepository.getById(deadline.categoryId!);
    }
    Purchase? purchase;
    if (deadline.relatedPurchaseId != null) {
      purchase =
          await widget.purchaseRepository.getById(deadline.relatedPurchaseId!);
    }
    final reminders = await widget.reminderRepository.forEntity(
      'deadline',
      deadline.id,
    );
    reminders.sort((a, b) => a.remindAt.compareTo(b.remindAt));
    return _DetailData(
      deadline: deadline,
      category: category,
      purchase: purchase,
      reminders: reminders,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _toggleDone(_DetailData data) async {
    final deadline = data.deadline;
    if (deadline.isDone) {
      await widget.deadlineRepository.markDone(deadline.id, done: false);
      _refresh();
      return;
    }

    if (deadline.repeatRule != 'none') {
      final next = ReminderScheduler.nextOccurrence(
        dueDate: deadline.dueDate,
        repeatRule: deadline.repeatRule,
        from: DateTime.now(),
      );
      if (next != null) {
        // Keep the user's reminder offsets on the rolled-forward deadline.
        final offsets = offsetsFromReminders(
          dueDate: deadline.dueDate,
          remindAts: [for (final r in data.reminders) r.remindAt],
        );
        await widget.deadlineRepository.update(
          deadline.id,
          DeadlinesCompanion(
            dueDate: drift.Value(next),
            isDone: const drift.Value(false),
          ),
        );
        await widget.reminderCoordinator.resyncEntity(
          entityType: 'deadline',
          entityId: deadline.id,
          title: deadline.title,
          dueDate: next,
          dueTime: deadline.dueTime,
          offsets: offsets,
          notes: deadline.notes,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Rolled forward to ${DateFormat.yMMMd().format(next)}.',
              ),
            ),
          );
        }
        _refresh();
        return;
      }
    }

    await widget.deadlineRepository.markDone(deadline.id, done: true);
    await widget.reminderCoordinator.clearEntity(
      entityType: 'deadline',
      entityId: deadline.id,
    );
    _refresh();
  }

  Future<void> _delete(_DetailData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete deadline?'),
        content: Text(
          '"${data.deadline.title}" and its reminders will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.reminderCoordinator.clearEntity(
      entityType: 'deadline',
      entityId: data.deadline.id,
    );
    await widget.deadlineRepository.delete(data.deadline.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deadline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () async {
              final changed = await context.push<bool>(
                '/deadlines/${widget.deadlineId}/edit',
              );
              if (changed == true) _refresh();
            },
          ),
        ],
      ),
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                snapshot.hasError
                    ? 'Could not load this deadline.'
                    : 'Deadline not found.',
              ),
            );
          }
          final data = snapshot.data!;
          final deadline = data.deadline;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                deadline.title,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              _Row(
                icon: Icons.event,
                child: Text(
                  DateFormat.yMMMd().format(deadline.dueDate) +
                      (deadline.dueTime != null ? ' · ${deadline.dueTime}' : ''),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              _Row(
                icon: Icons.repeat,
                child: Text(repeatLabel(deadline.repeatRule)),
              ),
              if (data.category != null) ...[
                const SizedBox(height: 8),
                _Row(
                  icon: Icons.label_outline,
                  child: Chip(label: Text(data.category!.name)),
                ),
              ],
              if (deadline.notes?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text('Notes', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(deadline.notes!),
              ],
              if (data.purchase != null) ...[
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(data.purchase!.productName),
                  subtitle: const Text('Linked purchase'),
                  trailing: const Icon(Icons.chevron_right),
                  contentPadding: EdgeInsets.zero,
                  onTap: () =>
                      context.push('/purchases/${data.purchase!.id}'),
                ),
              ],
              const SizedBox(height: 16),
              Text('Reminders', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (data.reminders.isEmpty)
                const Text('No reminders scheduled.')
              else
                for (final reminder in data.reminders)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      reminder.isDone
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_outlined,
                    ),
                    title: Text(
                      DateFormat.yMMMd().add_jm().format(reminder.remindAt),
                    ),
                  ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _toggleDone(data),
                icon: Icon(
                  deadline.isDone ? Icons.replay : Icons.check,
                ),
                label: Text(deadline.isDone ? 'Reopen' : 'Mark done'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _delete(data),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailData {
  _DetailData({
    required this.deadline,
    this.category,
    this.purchase,
    required this.reminders,
  });

  final Deadline deadline;
  final Category? category;
  final Purchase? purchase;
  final List<Reminder> reminders;
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}
