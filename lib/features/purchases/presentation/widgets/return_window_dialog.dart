import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/keepit_database.dart';
import '../../../../core/database/repositories/return_deadline_repository.dart';
import '../../../../core/database/tables.dart' show newRecordId;
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/notifications/reminder_coordinator.dart';

/// Dialog to set (or edit) a purchase's return window: either a number of
/// days from the purchase date or an explicit return-by date.
///
/// Saving creates/updates the [ReturnDeadline] row and schedules expiry
/// reminders (7 days and 1 day before) via the permission-gated
/// [NotificationService] flow. Returns true when saved.
class ReturnWindowDialog extends StatefulWidget {
  const ReturnWindowDialog({
    super.key,
    required this.purchase,
    required this.existing,
    required this.returnDeadlineRepository,
    required this.reminderCoordinator,
    required this.notificationService,
  });

  final Purchase purchase;
  final ReturnDeadline? existing;
  final ReturnDeadlineRepository returnDeadlineRepository;
  final ReminderCoordinator reminderCoordinator;
  final NotificationService notificationService;

  static Future<bool?> show(
    BuildContext context, {
    required Purchase purchase,
    required ReturnDeadline? existing,
    required ReturnDeadlineRepository returnDeadlineRepository,
    required ReminderCoordinator reminderCoordinator,
    required NotificationService notificationService,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ReturnWindowDialog(
        purchase: purchase,
        existing: existing,
        returnDeadlineRepository: returnDeadlineRepository,
        reminderCoordinator: reminderCoordinator,
        notificationService: notificationService,
      ),
    );
  }

  @override
  State<ReturnWindowDialog> createState() => _ReturnWindowDialogState();
}

class _ReturnWindowDialogState extends State<ReturnWindowDialog> {
  static const List<int> _dayOptions = [14, 30, 60, 90];

  int? _selectedDays;
  DateTime? _customDate;
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _notesController.text = existing.notes ?? '';
      final base = _baseDate();
      if (existing.returnPeriodDays != null &&
          existing.returnPeriodDays! > 0 &&
          _dayOptions.contains(existing.returnPeriodDays)) {
        _selectedDays = existing.returnPeriodDays;
      } else {
        _customDate = existing.deadlineDate;
      }
      // Prefer the explicit date when the stored period doesn't match a chip.
      if (_selectedDays != null &&
          _addDays(base, _selectedDays!) !=
              _dateOnly(existing.deadlineDate)) {
        _selectedDays = null;
        _customDate = existing.deadlineDate;
      }
    } else {
      _selectedDays = 30;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DateTime _baseDate() {
    final purchaseDate = widget.purchase.purchaseDate;
    final now = DateTime.now();
    final base = purchaseDate ?? now;
    return DateTime(base.year, base.month, base.day);
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  DateTime? get _deadlineDate {
    if (_customDate != null) return _dateOnly(_customDate!);
    if (_selectedDays != null) return _addDays(_baseDate(), _selectedDays!);
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final deadlineDate = _deadlineDate;
    if (deadlineDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a return window or a date.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      const offsets = [Duration(days: 7), Duration(days: 1)];
      var schedule = false;
      if (deadlineDate.isAfter(_dateOnly(DateTime.now()))) {
        schedule =
            await widget.notificationService.requestPermissions(context);
      }

      final existing = widget.existing;
      final id = existing?.id ?? newRecordId();
      final companion = ReturnDeadlinesCompanion(
        id: existing == null
            ? drift.Value(id)
            : const drift.Value.absent(),
        purchaseId: drift.Value(widget.purchase.id),
        deadlineDate: drift.Value(deadlineDate),
        returnPeriodDays: drift.Value(_selectedDays),
        notes: drift.Value(
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      );
      if (existing == null) {
        await widget.returnDeadlineRepository.create(companion);
      } else {
        await widget.returnDeadlineRepository.update(existing.id, companion);
      }

      await widget.reminderCoordinator.resyncEntity(
        entityType: 'return_deadline',
        entityId: id,
        title: 'Return window closing: ${widget.purchase.productName}',
        dueDate: deadlineDate,
        offsets: schedule ? offsets : const [],
      );

      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deadlineDate = _deadlineDate;
    return AlertDialog(
      title: const Text('Return window'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From ${DateFormat.yMMMd().format(_baseDate())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in _dayOptions)
                  ChoiceChip(
                    label: Text('$days days'),
                    selected: _selectedDays == days && _customDate == null,
                    onSelected: (_) => setState(() {
                      _selectedDays = days;
                      _customDate = null;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Custom date'),
                  selected: _customDate != null,
                  onSelected: (_) async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _customDate = picked;
                        _selectedDays = null;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (deadlineDate != null)
              Text(
                'Return by ${DateFormat.yMMMd().format(deadlineDate)}',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
