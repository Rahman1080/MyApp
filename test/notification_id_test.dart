import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/notification_id.dart';

void main() {
  group('notificationIdFor', () {
    test('is stable across calls for the same UUID', () {
      const id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      expect(notificationIdFor(id), notificationIdFor(id));
    });

    test('parses the leading 8 hex digits', () {
      // 0x12345678 = 305419896
      expect(
        notificationIdFor('12345678-aaaa-bbbb-cccc-dddddddddddd'),
        0x12345678,
      );
    });

    test('different UUIDs map to different ids', () {
      expect(
        notificationIdFor('aaaaaaaa-0000-0000-0000-000000000000'),
        isNot(
          notificationIdFor('bbbbbbbb-0000-0000-0000-000000000000'),
        ),
      );
    });

    test('stays within the positive 32-bit range', () {
      // 0xFFFFFFFF is the largest possible head.
      expect(
        notificationIdFor('ffffffff-ffff-ffff-ffff-ffffffffffff'),
        0xFFFFFFFF,
      );
      expect(
        notificationIdFor('00000000-0000-0000-0000-000000000000'),
        greaterThanOrEqualTo(0),
      );
    });

    test('handles ids without dashes gracefully', () {
      expect(notificationIdFor('abcdef12'), 0xabcdef12);
    });
  });
}
