import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/notifications/payload_routing.dart';

void main() {
  group('routeForPayload', () {
    Future<String?> purchaseFor(String id) async =>
        id == 'known' ? 'purchase-1' : null;

    test('deadline payload routes to the deadline detail', () async {
      expect(
        await routeForPayload(
          'deadline:abc-123',
          purchaseIdForWarranty: purchaseFor,
          purchaseIdForReturnDeadline: purchaseFor,
        ),
        '/deadlines/abc-123',
      );
    });

    test('warranty payload routes to the owning purchase', () async {
      expect(
        await routeForPayload(
          'warranty:known',
          purchaseIdForWarranty: purchaseFor,
          purchaseIdForReturnDeadline: purchaseFor,
        ),
        '/purchases/purchase-1',
      );
    });

    test('warranty without a purchase falls back to the warranties list',
        () async {
      expect(
        await routeForPayload(
          'warranty:gone',
          purchaseIdForWarranty: purchaseFor,
          purchaseIdForReturnDeadline: purchaseFor,
        ),
        '/purchases/warranties',
      );
    });

    test('return_deadline payload routes to the owning purchase', () async {
      expect(
        await routeForPayload(
          'return_deadline:known',
          purchaseIdForWarranty: purchaseFor,
          purchaseIdForReturnDeadline: purchaseFor,
        ),
        '/purchases/purchase-1',
      );
    });

    test('return_deadline without a purchase falls back to purchases',
        () async {
      expect(
        await routeForPayload(
          'return_deadline:gone',
          purchaseIdForWarranty: purchaseFor,
          purchaseIdForReturnDeadline: purchaseFor,
        ),
        '/purchases',
      );
    });

    test('null and empty payloads return null', () async {
      for (final payload in [null, '']) {
        expect(
          await routeForPayload(
            payload,
            purchaseIdForWarranty: purchaseFor,
            purchaseIdForReturnDeadline: purchaseFor,
          ),
          isNull,
        );
      }
    });

    test('malformed payloads return null', () async {
      for (final payload in ['no-separator', 'deadline:', ':abc']) {
        expect(
          await routeForPayload(
            payload,
            purchaseIdForWarranty: purchaseFor,
            purchaseIdForReturnDeadline: purchaseFor,
          ),
          isNull,
        );
      }
    });

    test('unknown entity types return null', () async {
      expect(
        await routeForPayload(
          'purchase:abc',
          purchaseIdForWarranty: purchaseFor,
          purchaseIdForReturnDeadline: purchaseFor,
        ),
        isNull,
      );
    });
  });
}
