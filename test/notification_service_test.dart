import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/reminder_repository.dart';
import 'package:keepit/core/database/tables.dart' show newRecordId;
import 'package:keepit/core/notifications/notification_id.dart';
import 'package:keepit/core/notifications/notification_service.dart';
import 'package:keepit/core/notifications/reminder_coordinator.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fake_notification_backend.dart';

void main() {
  late KeepItDatabase db;
  late ReminderRepository reminders;
  late FakeNotificationBackend backend;
  late NotificationService service;
  late ReminderCoordinator coordinator;

  final now = DateTime(2026, 9, 29, 12);

  setUp(() {
    initTestTimezones();
    db = openInMemoryDatabase();
    reminders = ReminderRepository(db);
    backend = FakeNotificationBackend();
    service = NotificationService(backend: backend, reminders: reminders);
    coordinator = ReminderCoordinator(
      reminders: reminders,
      notifications: service,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> insertReminder({
    required String entityType,
    required String entityId,
    required DateTime remindAt,
    String title = 'Reminder',
    bool isDone = false,
  }) async {
    final id = newRecordId();
    await reminders.create(
      RemindersCompanion(
        id: Value(id),
        title: Value(title),
        remindAt: Value(remindAt),
        entityType: Value(entityType),
        entityId: Value(entityId),
        isDone: Value(isDone),
      ),
    );
    return id;
  }

  group('NotificationService.syncReminders', () {
    test('schedules future reminders with stable ids and payloads', () async {
      final id = await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.add(const Duration(days: 2)),
        title: 'Pay rent',
      );

      final report = await service.syncReminders(now: now);

      expect(report.scheduled, 1);
      expect(report.markedDone, 0);
      expect(report.cancelled, 0);
      final notificationId = notificationIdFor(id);
      final scheduled = backend.scheduled[notificationId];
      expect(scheduled, isNotNull);
      expect(scheduled!.title, 'Pay rent');
      expect(scheduled.payload, 'deadline:d1');
    });

    test('marks past-due pending reminders done instead of scheduling',
        () async {
      final id = await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.subtract(const Duration(hours: 1)),
      );

      final report = await service.syncReminders(now: now);

      expect(report.markedDone, 1);
      expect(report.scheduled, 0);
      expect((await reminders.getById(id))!.isDone, isTrue);
      expect(backend.scheduled, isEmpty);
    });

    test('ignores reminders already marked done', () async {
      await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.add(const Duration(days: 1)),
        isDone: true,
      );

      final report = await service.syncReminders(now: now);

      expect(report.scheduled, 0);
      expect(backend.scheduled, isEmpty);
    });

    test('cancels orphaned OS notifications with no matching reminder',
        () async {
      await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.add(const Duration(days: 1)),
      );
      // A stale OS notification, e.g. left behind by a database restore.
      backend.scheduled[424242] = FakeScheduledNotification(
        title: 'stale',
        body: 'stale',
        when: tz.TZDateTime.from(now, tz.local),
      );

      final report = await service.syncReminders(now: now);

      expect(report.cancelled, 1);
      expect(backend.scheduled.keys, hasLength(1));
      expect(backend.scheduled.containsKey(424242), isFalse);
    });

    test('is idempotent: running twice schedules nothing new', () async {
      await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.add(const Duration(days: 1)),
      );

      await service.syncReminders(now: now);
      final firstRun = backend.scheduled.keys.toSet();
      final report = await service.syncReminders(now: now);

      expect(backend.scheduled.keys.toSet(), firstRun);
      expect(report.scheduled, 1);
      expect(report.cancelled, 0);
    });
  });

  group('ReminderCoordinator', () {
    test('resyncEntity creates reminder rows and schedules them', () async {
      await coordinator.resyncEntity(
        entityType: 'deadline',
        entityId: 'd1',
        title: 'Pay rent',
        dueDate: DateTime(2026, 10, 10),
        offsets: const [Duration(days: 1), Duration(days: 7)],
        now: now,
      );

      final rows = await reminders.forEntity('deadline', 'd1');
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.remindAt).toSet(),
        {DateTime(2026, 10, 3), DateTime(2026, 10, 9)},
      );
      expect(
        backend.scheduled.keys.toSet(),
        {for (final r in rows) notificationIdFor(r.id)},
      );
    });

    test('resyncEntity replaces old reminders instead of duplicating',
        () async {
      final oldId = await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.add(const Duration(days: 5)),
        title: 'old',
      );
      // Pretend the old reminder was already scheduled with the OS.
      await backend.schedule(
        id: notificationIdFor(oldId),
        title: 'old',
        body: 'old',
        when: tz.TZDateTime.from(now.add(const Duration(days: 5)), tz.local),
      );

      await coordinator.resyncEntity(
        entityType: 'deadline',
        entityId: 'd1',
        title: 'Pay rent',
        dueDate: DateTime(2026, 10, 10),
        offsets: const [Duration(days: 1)],
        now: now,
      );

      final rows = await reminders.forEntity('deadline', 'd1');
      expect(rows, hasLength(1));
      expect(rows.single.title, 'Pay rent');
      expect(
        backend.scheduled.keys,
        unorderedEquals([notificationIdFor(rows.single.id)]),
      );
    });

    test('resyncEntity with empty offsets clears old reminders', () async {
      await insertReminder(
        entityType: 'warranty',
        entityId: 'w1',
        remindAt: now.add(const Duration(days: 5)),
      );

      await coordinator.resyncEntity(
        entityType: 'warranty',
        entityId: 'w1',
        title: 'Warranty',
        dueDate: DateTime(2026, 10, 10),
        offsets: const [],
        now: now,
      );

      expect(await reminders.forEntity('warranty', 'w1'), isEmpty);
      expect(backend.scheduled, isEmpty);
    });

    test('clearEntity removes rows and cancels notifications', () async {
      final id = await insertReminder(
        entityType: 'return_deadline',
        entityId: 'r1',
        remindAt: now.add(const Duration(days: 5)),
      );
      await backend.schedule(
        id: notificationIdFor(id),
        title: 't',
        body: 'b',
        when: tz.TZDateTime.from(now.add(const Duration(days: 5)), tz.local),
      );

      await coordinator.clearEntity(
        entityType: 'return_deadline',
        entityId: 'r1',
      );

      expect(await reminders.forEntity('return_deadline', 'r1'), isEmpty);
      expect(backend.scheduled, isEmpty);
    });
  });

  group('NotificationService tap handling', () {
    test('taps before a handler is set are delivered once set', () async {
      await service.ensureInitialized();
      String? received;
      backend.tap('deadline:abc');
      service.onNotificationTap = (payload) => received = payload;
      expect(received, 'deadline:abc');
    });

    test('taps after a handler is set are delivered immediately', () async {
      await service.ensureInitialized();
      String? received;
      service.onNotificationTap = (payload) => received = payload;
      backend.tap('warranty:xyz');
      expect(received, 'warranty:xyz');
    });
  });

  group('NotificationService testing & diagnostics', () {
    test('showTestNotification dispatches immediate notification with id 999999', () async {
      await service.showTestNotification();
      expect(backend.scheduled.containsKey(999999), isTrue);
      expect(backend.scheduled[999999]!.payload, 'test:immediate');
    });

    test('scheduleTestReminder schedules reminder with id 999998', () async {
      await service.scheduleTestReminder(secondsFromNow: 15);
      expect(backend.scheduled.containsKey(999998), isTrue);
      expect(backend.scheduled[999998]!.payload, 'test:scheduled');
    });

    test('pendingNotificationCount reflects backend scheduled notifications', () async {
      expect(await service.pendingNotificationCount(), 0);
      await service.showTestNotification();
      expect(await service.pendingNotificationCount(), 1);
    });

    test('getNextUpcomingReminder returns next future reminder', () async {
      expect(await service.getNextUpcomingReminder(now: now), isNull);

      await insertReminder(
        entityType: 'deadline',
        entityId: 'd1',
        remindAt: now.add(const Duration(days: 3)),
        title: 'Later',
      );
      await insertReminder(
        entityType: 'warranty',
        entityId: 'w1',
        remindAt: now.add(const Duration(days: 1)),
        title: 'Sooner',
      );

      final next = await service.getNextUpcomingReminder(now: now);
      expect(next, isNotNull);
      expect(next!.title, 'Sooner');
    });
  });
}
