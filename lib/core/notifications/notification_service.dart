import 'package:flutter/material.dart';

import '../database/keepit_database.dart';
import '../database/repositories/reminder_repository.dart';
import '../permissions/permission_service.dart';
import 'notification_backend.dart';
import 'notification_id.dart';
import 'package:timezone/timezone.dart' as tz;

/// Result of a [NotificationService.syncReminders] pass.
class ReminderSyncReport {
  const ReminderSyncReport({
    required this.scheduled,
    required this.cancelled,
    required this.markedDone,
  });

  final int scheduled;
  final int cancelled;
  final int markedDone;

  @override
  String toString() =>
      'ReminderSyncReport(scheduled: $scheduled, cancelled: $cancelled, markedDone: $markedDone)';
}

/// Owns the notification backend and keeps OS-scheduled notifications in sync
/// with the [Reminder] rows in the local database.
///
/// Notifications are a best-effort convenience layer: the database is the
/// source of truth. Reconciliation is idempotent and safe to run on every
/// app start.
class NotificationService {
  NotificationService({
    required NotificationBackend backend,
    required ReminderRepository reminders,
  })  : _backend = backend,
        _reminders = reminders;

  final NotificationBackend _backend;
  final ReminderRepository _reminders;

  bool _initialized = false;
  void Function(String? payload)? _tapHandler;
  String? _pendingPayload;

  /// Initializes the backend once (timezone data, plugin, channel, tap
  /// callback) and drains any tap that arrived during initialization.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await _backend.initialize(onTap: _onTap);
    _initialized = true;
    _drainPendingTap();
  }

  void _onTap(String? payload) {
    if (_tapHandler != null) {
      _tapHandler!(payload);
    } else {
      _pendingPayload = payload;
    }
  }

  void _drainPendingTap() {
    if (_pendingPayload != null && _tapHandler != null) {
      final payload = _pendingPayload;
      _pendingPayload = null;
      _tapHandler!(payload);
    }
  }

  /// Sets the handler invoked when a notification is tapped. A tap that
  /// arrived before the handler was set is delivered immediately.
  set onNotificationTap(void Function(String? payload) handler) {
    _tapHandler = handler;
    _drainPendingTap();
  }

  /// Payload of the notification that cold-launched the app, if any.
  Future<String?> launchPayload() => _backend.launchPayload();

  /// Requests the OS notification permission. Shows KeepIt's own rationale
  /// first, as required; the OS prompt only follows an explicit "Allow".
  Future<bool> requestPermissions(BuildContext context) {
    return PermissionService().ensureNotifications(
      context,
      request: _backend.requestPermissions,
    );
  }

  /// Reconciles OS-scheduled notifications with pending reminder rows:
  /// - schedules every pending reminder whose fire time is still future;
  /// - marks pending reminders whose fire time already passed as done;
  /// - cancels OS notifications that have no matching pending reminder
  ///   (e.g. deleted rows, database restore, manual clear).
  Future<ReminderSyncReport> syncReminders({DateTime? now}) async {
    await ensureInitialized();
    final current = now ?? DateTime.now();
    final pending = await _reminders.getPending();

    final expectedIds = <int>{};
    var scheduled = 0;
    var markedDone = 0;
    for (final reminder in pending) {
      final notificationId = notificationIdFor(reminder.id);
      expectedIds.add(notificationId);
      if (reminder.remindAt.isAfter(current)) {
        await _backend.schedule(
          id: notificationId,
          title: reminder.title,
          body: reminder.notes?.isNotEmpty == true
              ? reminder.notes!
              : 'Tap to open in KeepIt.',
          when: tz.TZDateTime.from(reminder.remindAt, tz.local),
          payload: '${reminder.entityType}:${reminder.entityId ?? ''}',
        );
        scheduled++;
      } else {
        await _reminders.markDone(reminder.id, done: true);
        markedDone++;
      }
    }

    var cancelled = 0;
    for (final id in await _backend.pendingIds()) {
      if (!expectedIds.contains(id)) {
        await _backend.cancel(id);
        cancelled++;
      }
    }
    return ReminderSyncReport(
      scheduled: scheduled,
      cancelled: cancelled,
      markedDone: markedDone,
    );
  }

  /// Cancels the OS notification for a single reminder id.
  Future<void> cancelNotification(int notificationId) =>
      _backend.cancel(notificationId);

  /// Cancels every OS notification this app scheduled. Used by the
  /// reminders master switch in Settings; the reminder rows in the database
  /// are left untouched so re-enabling re-syncs them.
  Future<void> cancelAllNotifications() async {
    await ensureInitialized();
    for (final id in await _backend.pendingIds()) {
      await _backend.cancel(id);
    }
  }

  /// Displays an immediate notification. Used for testing and instant alerts.
  Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await ensureInitialized();
    await _backend.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Posts an immediate test notification to verify OS notification delivery.
  Future<void> showTestNotification() async {
    await showImmediate(
      id: 999999,
      title: 'KeepIt Reminders',
      body: 'Notifications are working properly on your device!',
      payload: 'test:immediate',
    );
  }

  /// Schedules a test reminder for [secondsFromNow] seconds in the future (default 10s).
  Future<void> scheduleTestReminder({int secondsFromNow = 10}) async {
    await ensureInitialized();
    final fireTime = DateTime.now().add(Duration(seconds: secondsFromNow));
    await _backend.schedule(
      id: 999998,
      title: 'KeepIt Scheduled Reminder',
      body: 'Scheduled background reminder test successful!',
      when: tz.TZDateTime.from(fireTime, tz.local),
      payload: 'test:scheduled',
    );
  }

  /// Returns the IDs of all notifications currently scheduled with the OS.
  Future<Set<int>> pendingNotificationIds() async {
    await ensureInitialized();
    return _backend.pendingIds();
  }

  /// Returns the count of all notifications currently scheduled with the OS.
  Future<int> pendingNotificationCount() async {
    final ids = await pendingNotificationIds();
    return ids.length;
  }

  /// Returns the next pending reminder row from the database (if any) that is scheduled in the future.
  Future<Reminder?> getNextUpcomingReminder({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final pending = await _reminders.getPending();
    for (final reminder in pending) {
      if (reminder.remindAt.isAfter(current)) {
        return reminder;
      }
    }
    return null;
  }
}
