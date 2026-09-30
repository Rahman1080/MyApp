import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/shared/services/return_deadline_service.dart';

void main() {
  final now = DateTime(2026, 9, 29);

  group('returnDaysLeft', () {
    test('positive for a future deadline', () {
      expect(returnDaysLeft(DateTime(2026, 10, 29), now), 30);
    });

    test('zero on the last day (same-day edge case)', () {
      expect(
        returnDaysLeft(DateTime(2026, 9, 29, 23, 59), DateTime(2026, 9, 29)),
        0,
      );
    });

    test('negative when overdue (past edge case)', () {
      expect(returnDaysLeft(DateTime(2026, 9, 27), now), -2);
    });
  });

  group('isReturnOverdue', () {
    test('false for today and future', () {
      expect(isReturnOverdue(DateTime(2026, 9, 29), now), isFalse);
      expect(isReturnOverdue(DateTime(2026, 10, 1), now), isFalse);
    });

    test('true for yesterday', () {
      expect(isReturnOverdue(DateTime(2026, 9, 28), now), isTrue);
    });
  });

  group('returnWindowStatus', () {
    test('available when far out', () {
      expect(
        returnWindowStatus(deadline: DateTime(2026, 10, 20), now: now),
        ReturnWindowStatus.available,
      );
    });

    test('approaching within 7 days including today', () {
      expect(
        returnWindowStatus(deadline: DateTime(2026, 10, 6), now: now),
        ReturnWindowStatus.approaching,
      );
      expect(
        returnWindowStatus(deadline: DateTime(2026, 9, 29), now: now),
        ReturnWindowStatus.approaching,
      );
    });

    test('expired after the deadline', () {
      expect(
        returnWindowStatus(deadline: DateTime(2026, 9, 28), now: now),
        ReturnWindowStatus.expired,
      );
    });
  });

  group('returnDeadlineFromWindow', () {
    test('adds the return window to the purchase date', () {
      expect(
        returnDeadlineFromWindow(
          purchaseDate: DateTime(2026, 9, 1),
          returnPeriodDays: 30,
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('null when purchase date or window is missing', () {
      expect(
        returnDeadlineFromWindow(
            purchaseDate: null, returnPeriodDays: 30),
        isNull,
      );
      expect(
        returnDeadlineFromWindow(
            purchaseDate: DateTime(2026, 9, 1), returnPeriodDays: null),
        isNull,
      );
      expect(
        returnDeadlineFromWindow(
            purchaseDate: DateTime(2026, 9, 1), returnPeriodDays: 0),
        isNull,
      );
    });
  });
}
