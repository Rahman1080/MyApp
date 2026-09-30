import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/features/product/domain/product_intelligence_service.dart';

/// Phase 19: Product Intelligence (optional, no paid APIs).
void main() {
  late ProductIntelligenceService service;

  setUp(() {
    service = ProductIntelligenceService();
  });

  group('Phase 19 Product Intelligence', () {
    group('UPC-A validation', () {
      test('validates correct UPC-A', () {
        // Valid UPC-A: 036000291452 (Coca-Cola).
        final result = service.validateProductId('036000291452');
        expect(result.isValid, isTrue);
        expect(result.type, ProductIdType.upcA);
        expect(result.normalized, '036000291452');
      });

      test('rejects UPC-A with bad checksum', () {
        final result = service.validateProductId('036000291453');
        expect(result.isValid, isFalse);
        expect(result.error, isNotNull);
      });
    });

    group('EAN-13 validation', () {
      test('validates correct EAN-13', () {
        // Valid EAN-13: 5901234123457.
        final result = service.validateProductId('5901234123457');
        expect(result.isValid, isTrue);
        expect(result.type, ProductIdType.ean13);
      });

      test('rejects EAN-13 with bad checksum', () {
        final result = service.validateProductId('5901234123458');
        expect(result.isValid, isFalse);
      });
    });

    group('ISBN validation', () {
      test('validates correct ISBN-13', () {
        // Valid ISBN-13: 9780306406157.
        final result = service.validateProductId('9780306406157');
        expect(result.isValid, isTrue);
        expect(result.type, ProductIdType.isbn13);
      });

      test('validates correct ISBN-10', () {
        // Valid ISBN-10: 0306406152.
        final result = service.validateProductId('0306406152');
        expect(result.isValid, isTrue);
        expect(result.type, ProductIdType.isbn10);
      });

      test('validates ISBN-10 with X check digit', () {
        // Valid ISBN-10 with X: 080442957X.
        final result = service.validateProductId('080442957X');
        expect(result.isValid, isTrue);
        expect(result.type, ProductIdType.isbn10);
      });

      test('rejects ISBN-10 with bad checksum', () {
        final result = service.validateProductId('0306406153');
        expect(result.isValid, isFalse);
      });
    });

    group('input normalization', () {
      test('strips hyphens and spaces', () {
        final result = service.validateProductId('978-0-306-40615-7');
        expect(result.isValid, isTrue);
        expect(result.normalized, '9780306406157');
      });

      test('rejects empty input', () {
        final result = service.validateProductId('   ');
        expect(result.isValid, isFalse);
        expect(result.error, contains('empty'));
      });

      test('rejects unrecognized format', () {
        final result = service.validateProductId('ABC123');
        expect(result.isValid, isFalse);
        expect(result.type, ProductIdType.unknown);
      });
    });

    group('previewMerge', () {
      test('merges non-null fields without overwriting with null', () {
        const existing = ProductInfo(
          brand: 'Sony',
          model: 'WH-1000XM4',
          manufacturer: 'Sony Corp',
        );
        const newInfo = ProductInfo(
          brand: 'Sony Electronics',
          // model is null — should preserve existing
        );

        final merged = service.previewMerge(existing, newInfo);
        expect(merged.brand, 'Sony Electronics');
        expect(merged.model, 'WH-1000XM4'); // preserved
        expect(merged.manufacturer, 'Sony Corp'); // preserved
      });

      test('merges specifications', () {
        const existing = ProductInfo(
          specifications: {'color': 'black'},
        );
        const newInfo = ProductInfo(
          specifications: {'weight': '254g'},
        );

        final merged = service.previewMerge(existing, newInfo);
        expect(merged.specifications['color'], 'black');
        expect(merged.specifications['weight'], '254g');
      });

      test('does not modify the original', () {
        const existing = ProductInfo(brand: 'Sony');
        const newInfo = ProductInfo(brand: 'Bose');

        service.previewMerge(existing, newInfo);
        // Existing should be unchanged (immutability check).
        expect(existing.brand, 'Sony');
      });
    });

    group('hasChanges', () {
      test('returns false when no changes', () {
        const existing = ProductInfo(brand: 'Sony');
        const newInfo = ProductInfo(brand: 'Sony');

        expect(service.hasChanges(existing, newInfo), isFalse);
      });

      test('returns true when brand changes', () {
        const existing = ProductInfo(brand: 'Sony');
        const newInfo = ProductInfo(brand: 'Bose');

        expect(service.hasChanges(existing, newInfo), isTrue);
      });

      test('returns false when new info is empty', () {
        const existing = ProductInfo(brand: 'Sony');
        const newInfo = ProductInfo();

        expect(service.hasChanges(existing, newInfo), isFalse);
      });
    });

    group('ProductInfo', () {
      test('isEmpty when all fields null', () {
        const info = ProductInfo();
        expect(info.isEmpty, isTrue);
        expect(info.isNotEmpty, isFalse);
      });

      test('isNotEmpty when any field set', () {
        const info = ProductInfo(brand: 'Sony');
        expect(info.isNotEmpty, isTrue);
      });
    });
  });
}
