import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/shared/services/warranty_service.dart';

void main() {
  group('addWarrantyDuration', () {
    test('adds months', () {
      expect(
        addWarrantyDuration(
            DateTime(2026, 1, 15), const WarrantyDuration.months(12)),
        DateTime(2027, 1, 15),
      );
    });

    test('adds years', () {
      expect(
        addWarrantyDuration(
            DateTime(2026, 3, 10), const WarrantyDuration.years(2)),
        DateTime(2028, 3, 10),
      );
    });

    test('adds days', () {
      expect(
        addWarrantyDuration(
            DateTime(2026, 1, 1), const WarrantyDuration.days(90)),
        DateTime(2026, 4, 1),
      );
    });

    test('clamps month-end overflow (Jan 31 + 1 month)', () {
      // 2027 is not a leap year: Feb has 28 days.
      expect(
        addWarrantyDuration(
            DateTime(2027, 1, 31), const WarrantyDuration.months(1)),
        DateTime(2027, 2, 28),
      );
    });

    test('clamps month-end overflow in a leap year', () {
      // 2028 is a leap year: Feb has 29 days.
      expect(
        addWarrantyDuration(
            DateTime(2028, 1, 31), const WarrantyDuration.months(1)),
        DateTime(2028, 2, 29),
      );
    });

    test('combines years, months and days', () {
      expect(
        addWarrantyDuration(DateTime(2026, 1, 15),
            const WarrantyDuration(days: 5, months: 1, years: 1)),
        DateTime(2027, 2, 20),
      );
    });
  });

  group('warrantyExpiryDate', () {
    test('explicit expiration date wins', () {
      final explicit = DateTime(2028, 5, 1);
      expect(
        warrantyExpiryDate(
          startDate: DateTime(2026, 1, 1),
          durationMonths: 12,
          expirationDate: explicit,
        ),
        explicit,
      );
    });

    test('derives expiry from start date + duration months', () {
      expect(
        warrantyExpiryDate(
          startDate: DateTime(2026, 6, 15),
          durationMonths: 24,
        ),
        DateTime(2028, 6, 15),
      );
    });

    test('returns null without enough information', () {
      expect(warrantyExpiryDate(), isNull);
      expect(
          warrantyExpiryDate(startDate: DateTime(2026, 1, 1)), isNull);
      expect(warrantyExpiryDate(durationMonths: 12), isNull);
    });
  });

  group('warrantyDaysRemaining', () {
    test('positive for future expiry', () {
      expect(
        warrantyDaysRemaining(DateTime(2026, 10, 9), DateTime(2026, 9, 29)),
        10,
      );
    });

    test('zero when expiring today', () {
      expect(
        warrantyDaysRemaining(
            DateTime(2026, 9, 29, 23, 59), DateTime(2026, 9, 29, 0, 1)),
        0,
      );
    });

    test('negative when expired', () {
      expect(
        warrantyDaysRemaining(DateTime(2026, 9, 20), DateTime(2026, 9, 29)),
        -9,
      );
    });
  });

  group('warrantyStatus', () {
    final now = DateTime(2026, 9, 29);

    test('active when expiry is far out', () {
      expect(
        warrantyStatus(expiry: DateTime(2027, 9, 29), now: now),
        WarrantyStatus.active,
      );
    });

    test('expiringSoon within 30 days', () {
      expect(
        warrantyStatus(expiry: DateTime(2026, 10, 29), now: now),
        WarrantyStatus.expiringSoon,
      );
      expect(
        warrantyStatus(expiry: DateTime(2026, 9, 29), now: now),
        WarrantyStatus.expiringSoon,
      );
    });

    test('expired in the past', () {
      expect(
        warrantyStatus(expiry: DateTime(2026, 9, 28), now: now),
        WarrantyStatus.expired,
      );
    });

    test('custom threshold is honored', () {
      expect(
        warrantyStatus(
          expiry: DateTime(2026, 10, 10),
          now: now,
          expiringSoonThresholdDays: 7,
        ),
        WarrantyStatus.active,
      );
    });
  });
}
