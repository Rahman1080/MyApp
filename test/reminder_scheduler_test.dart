import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/shared/services/reminder_scheduler.dart';

void main() {
  group('computeFireTimes', () {
    final now = DateTime(2026, 9, 29, 12);
    final due = DateTime(2026, 10, 10, 18, 30);

    test('offsets before the due date, sorted ascending', () {
      final fires = ReminderScheduler.computeFireTimes(
        dueDate: due,
        offsets: const [Duration(days: 1), Duration(days: 7)],
        now: now,
      );
      expect(fires, [
        DateTime(2026, 10, 3, 18, 30),
        DateTime(2026, 10, 9, 18, 30),
      ]);
    });

    test('dueTime overrides the time of day', () {
      final fires = ReminderScheduler.computeFireTimes(
        dueDate: due,
        dueTime: '09:00',
        offsets: const [Duration(days: 7), Duration(days: 1)],
        now: now,
      );
      expect(fires, [
        DateTime(2026, 10, 3, 9),
        DateTime(2026, 10, 9, 9),
      ]);
    });

    test('past fire times are skipped', () {
      final fires = ReminderScheduler.computeFireTimes(
        dueDate: DateTime(2026, 9, 30, 18),
        dueTime: '09:00',
        offsets: const [Duration(days: 7), Duration(hours: 12)],
        now: now,
      );
      // 7-day offset -> 2026-09-23 09:00 (past, skipped);
      // 12h offset -> 2026-09-30 09:00 (future, kept).
      expect(fires, [DateTime(2026, 9, 30, 9)]);
    });

    test('fire time exactly at now is skipped', () {
      final fires = ReminderScheduler.computeFireTimes(
        dueDate: now.add(const Duration(days: 1)),
        offsets: const [Duration(days: 1)],
        now: now,
      );
      expect(fires, isEmpty);
    });

    test('invalid dueTime is ignored', () {
      final fires = ReminderScheduler.computeFireTimes(
        dueDate: due,
        dueTime: 'not-a-time',
        offsets: const [Duration(days: 1)],
        now: now,
      );
      expect(fires, [DateTime(2026, 10, 9, 18, 30)]);
    });

    test('duplicate offsets are deduplicated', () {
      final fires = ReminderScheduler.computeFireTimes(
        dueDate: due,
        offsets: const [Duration(days: 1), Duration(days: 1)],
        now: now,
      );
      expect(fires, [DateTime(2026, 10, 9, 18, 30)]);
    });

    test('empty offsets yield no fire times', () {
      expect(
        ReminderScheduler.computeFireTimes(
            dueDate: due, offsets: const [], now: now),
        isEmpty,
      );
    });
  });

  group('nextOccurrence', () {
    final from = DateTime(2026, 9, 29);

    test('daily steps forward past from', () {
      expect(
        ReminderScheduler.nextOccurrence(
          dueDate: DateTime(2026, 9, 20),
          repeatRule: 'daily',
          from: from,
        ),
        DateTime(2026, 9, 29),
      );
    });

    test('weekly keeps the weekday', () {
      expect(
        ReminderScheduler.nextOccurrence(
          dueDate: DateTime(2026, 9, 22), // a Tuesday
          repeatRule: 'weekly',
          from: from, // also a Tuesday
        ),
        DateTime(2026, 9, 29),
      );
    });

    test('monthly clamps month-end', () {
      expect(
        ReminderScheduler.nextOccurrence(
          dueDate: DateTime(2026, 1, 31),
          repeatRule: 'monthly',
          from: DateTime(2026, 3, 1),
        ),
        DateTime(2026, 3, 28),
      );
    });

    test('yearly', () {
      expect(
        ReminderScheduler.nextOccurrence(
          dueDate: DateTime(2025, 5, 10),
          repeatRule: 'yearly',
          from: from,
        ),
        DateTime(2027, 5, 10),
      );
    });

    test('none and custom return null', () {
      for (final rule in ['none', 'custom', 'bogus']) {
        expect(
          ReminderScheduler.nextOccurrence(
            dueDate: DateTime(2026, 9, 20),
            repeatRule: rule,
            from: from,
          ),
          isNull,
        );
      }
    });

    test('future due date is returned as-is', () {
      final due = DateTime(2026, 12, 25);
      expect(
        ReminderScheduler.nextOccurrence(
            dueDate: due, repeatRule: 'yearly', from: from),
        due,
      );
    });
  });
}
