import 'package:timezone/timezone.dart' as tz;

/// Platform notification operations, behind an interface so scheduling logic
/// stays unit-testable without the real plugin or a device.
///
/// All KeepIt notifications are reminder-style: local, on-device, scheduled
/// with inexact timing (no exact-alarm permission is requested).
abstract class NotificationBackend {
  /// Initializes timezone data, the plugin, the reminder channel, and the
  /// tap callback. Safe to call once; implementations should tolerate
  /// timezone lookup failure by falling back gracefully.
  Future<void> initialize({required void Function(String? payload) onTap});

  /// Requests the OS notification permission (Android 13+ POST_NOTIFICATIONS,
  /// iOS alert/badge/sound). Returns true when notifications may be posted.
  /// Returns true on platforms with no runtime notification permission.
  Future<bool> requestPermissions();

  /// Schedules one notification for an exact local wall-clock time.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    String? payload,
  });

  /// Displays an immediate notification. Used for testing and alerts.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Cancels one scheduled notification by id. No-op when absent.
  Future<void> cancel(int id);

  /// Ids of notifications currently scheduled with the OS.
  Future<Set<int>> pendingIds();

  /// Payload of the notification that launched the app, if the app was
  /// cold-started from a notification tap.
  Future<String?> launchPayload();
}
