import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/shared/services/reminder_planner.dart';

void main() {
  group('planReminders', () {
    final now = DateTime(2026, 9, 29, 12);
    final due = DateTime(2026, 10, 10, 18, 30);

    test('turns offsets into sorted future fire times', () {
      final planned = planReminders(
        title: 'Pay rent',
        dueDate: due,
        offsets: const [Duration(days: 1), Duration(days: 7)],
        entityType: 'deadline',
        entityId: 'd1',
        now: now,
      );
      expect(
        [for (final p in planned) p.remindAt],
        [DateTime(2026, 10, 3, 18, 30), DateTime(2026, 10, 9, 18, 30)],
      );
      for (final p in planned) {
        expect(p.title, 'Pay rent');
        expect(p.entityType, 'deadline');
        expect(p.entityId, 'd1');
      }
    });

    test('honors dueTime and notes', () {
      final planned = planReminders(
        title: 'Dentist',
        dueDate: due,
        dueTime: '09:00',
        offsets: const [Duration.zero],
        entityType: 'deadline',
        notes: 'Bring card',
        now: now,
      );
      expect(planned, hasLength(1));
      expect(planned.single.remindAt, DateTime(2026, 10, 10, 9));
      expect(planned.single.notes, 'Bring card');
    });

    test('drops fire times that are already past', () {
      final planned = planReminders(
        title: 'Soon',
        dueDate: DateTime(2026, 9, 30, 18),
        offsets: const [Duration(days: 7), Duration(hours: 12)],
        entityType: 'deadline',
        now: now,
      );
      // 7 days before is in the past; 12 hours before (Sep 30 06:00) remains.
      expect(
        [for (final p in planned) p.remindAt],
        [DateTime(2026, 9, 30, 6)],
      );
    });

    test('empty offsets produce no reminders', () {
      expect(
        planReminders(
          title: 'X',
          dueDate: due,
          offsets: const [],
          entityType: 'deadline',
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('offsetsFromReminders', () {
    final due = DateTime(2026, 10, 10, 18, 30);

    test('derives offsets from existing fire times', () {
      final offsets = offsetsFromReminders(
        dueDate: due,
        remindAts: [
          DateTime(2026, 10, 3, 18, 30),
          DateTime(2026, 10, 9, 18, 30),
          DateTime(2026, 10, 10, 18, 30),
        ],
      );
      expect(
        offsets.toSet(),
        {
          const Duration(days: 7),
          const Duration(days: 1),
          Duration.zero,
        },
      );
    });

    test('clamps post-due fire times to a zero offset', () {
      final offsets = offsetsFromReminders(
        dueDate: due,
        remindAts: [DateTime(2026, 10, 11, 9)],
      );
      expect(offsets, [Duration.zero]);
    });

    test('deduplicates identical offsets', () {
      final offsets = offsetsFromReminders(
        dueDate: due,
        remindAts: [
          DateTime(2026, 10, 9, 18, 30),
          DateTime(2026, 10, 9, 18, 30),
        ],
      );
      expect(offsets, [const Duration(days: 1)]);
    });

    test('empty input produces no offsets', () {
      expect(
        offsetsFromReminders(dueDate: due, remindAts: const []),
        isEmpty,
      );
    });
  });
}
