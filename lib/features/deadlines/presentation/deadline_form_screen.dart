import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/tables.dart' show newRecordId;
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/deadline_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/reminder_repository.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reminder_coordinator.dart';
import '../../../shared/services/reminder_planner.dart';

/// Repeat rules stored on [Deadline.repeatRule].
const List<String> kRepeatRules = ['none', 'daily', 'weekly', 'monthly', 'yearly'];

String repeatLabel(String rule) {
  switch (rule) {
    case 'daily':
      return 'Daily';
    case 'weekly':
      return 'Weekly';
    case 'monthly':
      return 'Monthly';
    case 'yearly':
      return 'Yearly';
    default:
      return 'Does not repeat';
  }
}

/// Add/edit form for a deadline. When reminders are enabled, the notification
/// permission is requested with KeepIt's own rationale first, and only then
/// is the OS prompt shown.
class DeadlineFormScreen extends StatefulWidget {
  const DeadlineFormScreen({
    super.key,
    required this.deadlineRepository,
    required this.categoryRepository,
    required this.purchaseRepository,
    required this.reminderRepository,
    required this.reminderCoordinator,
    required this.notificationService,
    this.deadlineId,
  });

  final DeadlineRepository deadlineRepository;
  final CategoryRepository categoryRepository;
  final PurchaseRepository purchaseRepository;
  final ReminderRepository reminderRepository;
  final ReminderCoordinator reminderCoordinator;
  final NotificationService notificationService;

  /// Null for a new deadline, set when editing.
  final String? deadlineId;

  @override
  State<DeadlineFormScreen> createState() => _DeadlineFormScreenState();
}

class _DeadlineFormScreenState extends State<DeadlineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _repeatRule = 'none';
  String? _categoryId;
  String? _purchaseId;
  bool _remindWeek = false;
  bool _remindDay = false;
  bool _remindOnDay = true;

  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.deadlineId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_isEditing) {
      final deadline = await widget.deadlineRepository.getById(widget.deadlineId!);
      if (deadline != null) {
        _titleController.text = deadline.title;
        _notesController.text = deadline.notes ?? '';
        _dueDate = deadline.dueDate;
        _dueTime = _parseTime(deadline.dueTime);
        _repeatRule = deadline.repeatRule;
        _categoryId = deadline.categoryId;
        _purchaseId = deadline.relatedPurchaseId;
        final reminders = await widget.reminderRepository.forEntity(
          'deadline',
          deadline.id,
        );
        final offsets = offsetsFromReminders(
          dueDate: deadline.dueDate,
          remindAts: [for (final r in reminders) r.remindAt],
        );
        _remindWeek = offsets.any((o) => o >= const Duration(days: 7));
        _remindDay = offsets.any(
          (o) => o >= const Duration(days: 1) && o < const Duration(days: 7),
        );
        _remindOnDay = offsets.any((o) => o < const Duration(days: 1));
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String? _formatTime(TimeOfDay? time) {
    if (time == null) return null;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<Duration> get _offsets {
    final offsets = <Duration>[];
    if (_remindWeek) offsets.add(const Duration(days: 7));
    if (_remindDay) offsets.add(const Duration(days: 1));
    if (_remindOnDay) offsets.add(Duration.zero);
    return offsets;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a due date.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final dueDate = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
      final dueTime = _formatTime(_dueTime);
      final offsets = _offsets;

      // Only ask for the notification permission when the user actually wants
      // reminders. The rationale dialog comes first; the OS prompt follows an
      // explicit "Allow".
      var scheduleReminders = offsets.isNotEmpty;
      if (scheduleReminders) {
        scheduleReminders =
            await widget.notificationService.requestPermissions(context);
      }

      final deadlineId = _isEditing ? widget.deadlineId! : _newId();
      final companion = DeadlinesCompanion(
        id: _isEditing ? const drift.Value.absent() : drift.Value(deadlineId),
        title: drift.Value(_titleController.text.trim()),
        dueDate: drift.Value(dueDate),
        dueTime: drift.Value(dueTime),
        repeatRule: drift.Value(_repeatRule),
        categoryId: drift.Value(_categoryId),
        notes: drift.Value(
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
        relatedPurchaseId: drift.Value(_purchaseId),
      );
      if (_isEditing) {
        await widget.deadlineRepository.update(widget.deadlineId!, companion);
      } else {
        await widget.deadlineRepository.create(companion);
      }

      await widget.reminderCoordinator.resyncEntity(
        entityType: 'deadline',
        entityId: deadlineId,
        title: _titleController.text.trim(),
        dueDate: dueDate,
        dueTime: dueTime,
        offsets: scheduleReminders ? offsets : const [],
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _newId() => newRecordId();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit deadline' : 'New deadline'),
        actions: [
          if (_loaded)
            TextButton(
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
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    key: const Key('deadline-title'),
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Give the deadline a title.'
                        : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  _DateRow(
                    label: 'Due date',
                    value: _dueDate == null
                        ? 'Pick a date'
                        : DateFormat.yMMMd().format(_dueDate!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dueDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _dueDate = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  _DateRow(
                    label: 'Time (optional)',
                    value: _dueTime == null
                        ? 'No time'
                        : _dueTime!.format(context),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _dueTime ?? TimeOfDay.now(),
                      );
                      if (picked != null) setState(() => _dueTime = picked);
                    },
                    onClear: _dueTime == null
                        ? null
                        : () => setState(() => _dueTime = null),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _repeatRule,
                    decoration: const InputDecoration(
                      labelText: 'Repeats',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final rule in kRepeatRules)
                        DropdownMenuItem(
                          value: rule,
                          child: Text(repeatLabel(rule)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _repeatRule = value ?? 'none'),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Category>>(
                    future: widget.categoryRepository.getAll(),
                    builder: (context, snapshot) {
                      final categories = snapshot.data ?? const <Category>[];
                      return DropdownButtonFormField<String?>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          for (final category in categories)
                            DropdownMenuItem<String?>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Purchase>>(
                    future: widget.purchaseRepository.getAll(),
                    builder: (context, snapshot) {
                      final purchases = snapshot.data ?? const <Purchase>[];
                      return DropdownButtonFormField<String?>(
                        initialValue: _purchaseId,
                        decoration: const InputDecoration(
                          labelText: 'Linked purchase (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No purchase'),
                          ),
                          for (final purchase in purchases)
                            DropdownMenuItem<String?>(
                              value: purchase.id,
                              child: Text(
                                purchase.productName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _purchaseId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Reminders',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SwitchListTile(
                    title: const Text('A week before'),
                    value: _remindWeek,
                    onChanged: (value) =>
                        setState(() => _remindWeek = value),
                  ),
                  SwitchListTile(
                    title: const Text('A day before'),
                    value: _remindDay,
                    onChanged: (value) =>
                        setState(() => _remindDay = value),
                  ),
                  SwitchListTile(
                    title: const Text('On the day'),
                    value: _remindOnDay,
                    onChanged: (value) =>
                        setState(() => _remindOnDay = value),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reminders are scheduled on this device only. '
                    'Notification permission is asked when you save with '
                    'reminders turned on.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear == null
              ? const Icon(Icons.calendar_today)
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                  tooltip: 'Clear',
                ),
        ),
        child: Text(value),
      ),
    );
  }
}
