import 'package:drift/drift.dart';

import '../../shared/services/reminder_planner.dart';
import '../database/keepit_database.dart';
import '../database/repositories/reminder_repository.dart';
import 'notification_id.dart';
import 'notification_service.dart';

/// Glue between entity CRUD and the reminder subsystem.
///
/// UI code calls this after creating, updating, or deleting a deadline,
/// warranty, or return deadline. It keeps [Reminder] rows and OS-scheduled
/// notifications in sync, so every screen uses the same path and there is no
/// drift between the database and what the OS will fire.
class ReminderCoordinator {
  ReminderCoordinator({
    required ReminderRepository reminders,
    required NotificationService notifications,
  })  : _reminders = reminders,
        _notifications = notifications;

  final ReminderRepository _reminders;
  final NotificationService _notifications;

  /// Deletes this entity's existing reminders, then creates fresh reminder
  /// rows from [offsets] and schedules them.
  ///
  /// When [offsets] is empty any previous reminders are still cleared, so the
  /// entity ends up with no reminders at all.
  Future<void> resyncEntity({
    required String entityType,
    required String entityId,
    required String title,
    required DateTime dueDate,
    String? dueTime,
    required List<Duration> offsets,
    String? notes,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();

    final existing = await _reminders.forEntity(entityType, entityId);
    for (final reminder in existing) {
      await _notifications.cancelNotification(notificationIdFor(reminder.id));
    }
    await _reminders.deleteForEntity(entityType, entityId);

    for (final planned in planReminders(
      title: title,
      dueDate: dueDate,
      dueTime: dueTime,
      offsets: offsets,
      entityType: entityType,
      entityId: entityId,
      notes: notes,
      now: current,
    )) {
      await _reminders.create(
        RemindersCompanion(
          title: Value(planned.title),
          remindAt: Value(planned.remindAt),
          entityType: Value(planned.entityType),
          entityId: Value(planned.entityId),
          notes: Value(planned.notes),
        ),
      );
    }

    await _notifications.syncReminders(now: current);
  }

  /// Removes all reminders for an entity and cancels their OS notifications.
  Future<void> clearEntity({
    required String entityType,
    required String entityId,
  }) async {
    final existing = await _reminders.forEntity(entityType, entityId);
    for (final reminder in existing) {
      await _notifications.cancelNotification(notificationIdFor(reminder.id));
    }
    await _reminders.deleteForEntity(entityType, entityId);
  }
}
