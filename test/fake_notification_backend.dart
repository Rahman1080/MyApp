import 'package:keepit/core/notifications/notification_backend.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Mirrors the real backend's contract: timezone data must be initialized
/// before anything is scheduled. Call once in setUp.
void initTestTimezones() {
  tzdata.initializeTimeZones();
}

/// In-memory stand-in for the OS notification plumbing, shared by tests.
class FakeNotificationBackend implements NotificationBackend {
  final scheduled = <int, FakeScheduledNotification>{};
  var initializeCalls = 0;
  var requestCalls = 0;
  var grantPermissions = true;
  String? launchPayloadValue;
  void Function(String? payload)? _onTap;

  /// Simulates the user tapping a notification.
  void tap(String? payload) => _onTap?.call(payload);

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    initializeCalls++;
    _onTap = onTap;
  }

  @override
  Future<bool> requestPermissions() async {
    requestCalls++;
    return grantPermissions;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    String? payload,
  }) async {
    scheduled[id] = FakeScheduledNotification(
      title: title,
      body: body,
      when: when,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();

  @override
  Future<String?> launchPayload() async => launchPayloadValue;
}

class FakeScheduledNotification {
  FakeScheduledNotification({
    required this.title,
    required this.body,
    required this.when,
    this.payload,
  });

  final String title;
  final String body;
  final tz.TZDateTime when;
  final String? payload;
}
