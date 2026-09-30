import 'reminder_scheduler.dart';

/// One reminder fire time derived from user-chosen offsets. Pure data: the
/// coordinator turns these into [Reminder] rows.
class PlannedReminder {
  PlannedReminder({
    required this.title,
    required this.remindAt,
    required this.entityType,
    this.entityId,
    this.notes,
  });

  final String title;
  final DateTime remindAt;
  final String entityType;
  final String? entityId;
  final String? notes;
}

/// Turns reminder offsets into concrete future fire times, reusing the shared
/// [ReminderScheduler] day arithmetic so DST edges behave identically
/// everywhere. Past fire times are dropped; results are sorted ascending.
List<PlannedReminder> planReminders({
  required String title,
  required DateTime dueDate,
  String? dueTime,
  required List<Duration> offsets,
  required String entityType,
  String? entityId,
  String? notes,
  DateTime? now,
}) {
  final fires = ReminderScheduler.computeFireTimes(
    dueDate: dueDate,
    dueTime: dueTime,
    offsets: offsets,
    now: now ?? DateTime.now(),
  );
  return [
    for (final fire in fires)
      PlannedReminder(
        title: title,
        remindAt: fire,
        entityType: entityType,
        entityId: entityId,
        notes: notes,
      ),
  ];
}

/// Derives offsets from an entity's existing reminder fire times relative to
/// [dueDate], so a repeating deadline can keep the user's reminder choices
/// when it rolls forward to its next occurrence. Offsets are deduplicated;
/// reminder times after the due date collapse to a zero offset.
List<Duration> offsetsFromReminders({
  required DateTime dueDate,
  required List<DateTime> remindAts,
}) {
  final offsets = <Duration>{};
  for (final remindAt in remindAts) {
    var offset = dueDate.difference(remindAt);
    if (offset.isNegative) offset = Duration.zero;
    offsets.add(offset);
  }
  return offsets.toList();
}
