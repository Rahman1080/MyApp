/// Product identifier types.
enum ProductIdType {
  /// UPC-A (12 digits, North America).
  upcA,

  /// EAN-13 (13 digits, international).
  ean13,

  /// ISBN-10 (10 digits, books).
  isbn10,

  /// ISBN-13 (13 digits, books).
  isbn13,

  /// Unknown or custom identifier.
  unknown,
}

/// Result of validating a product identifier.
class ProductIdValidation {
  const ProductIdValidation({
    required this.isValid,
    required this.type,
    required this.normalized,
    this.error,
  });

  final bool isValid;
  final ProductIdType type;
  final String normalized;
  final String? error;
}

/// Structured product information (user-provided).
class ProductInfo {
  const ProductInfo({
    this.brand,
    this.model,
    this.productId,
    this.productIdType = ProductIdType.unknown,
    this.manufacturer,
    this.specifications = const {},
  });

  final String? brand;
  final String? model;
  final String? productId;
  final ProductIdType productIdType;
  final String? manufacturer;
  final Map<String, String> specifications;

  bool get isEmpty =>
      brand == null &&
      model == null &&
      productId == null &&
      manufacturer == null &&
      specifications.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

/// Product Intelligence service (Phase 19).
///
/// Optional product data enrichment with strict constraints:
/// - **No paid APIs:** Does not call any external product database.
/// - **No scraping:** Does not scrape websites.
/// - **No silent overwrites:** User must explicitly confirm any data changes.
/// - **Validation only:** Validates product identifiers (UPC/EAN/ISBN)
///   using checksum algorithms. All product data is user-provided.
class ProductIntelligenceService {
  /// Validates a product identifier and detects its type.
  ///
  /// Strips whitespace and hyphens, then validates the checksum.
  /// Returns a [ProductIdValidation] with the normalized form.
  ProductIdValidation validateProductId(String input) {
    final normalized = input.replaceAll(RegExp(r'[\s-]'), '');

    if (normalized.isEmpty) {
      return const ProductIdValidation(
        isValid: false,
        type: ProductIdType.unknown,
        normalized: '',
        error: 'Product ID is empty',
      );
    }

    // ISBN-10: 10 digits (last can be X).
    if (RegExp(r'^\d{9}[\dX]$').hasMatch(normalized)) {
      return ProductIdValidation(
        isValid: _validateIsbn10(normalized),
        type: ProductIdType.isbn10,
        normalized: normalized,
        error: _validateIsbn10(normalized) ? null : 'Invalid ISBN-10 checksum',
      );
    }

    // ISBN-13 / EAN-13: 13 digits.
    if (RegExp(r'^\d{13}$').hasMatch(normalized)) {
      final isValid = _validateEan13(normalized);
      // ISBN-13 starts with 978 or 979.
      final type = (normalized.startsWith('978') ||
              normalized.startsWith('979'))
          ? ProductIdType.isbn13
          : ProductIdType.ean13;
      return ProductIdValidation(
        isValid: isValid,
        type: type,
        normalized: normalized,
        error: isValid ? null : 'Invalid checksum',
      );
    }

    // UPC-A: 12 digits.
    if (RegExp(r'^\d{12}$').hasMatch(normalized)) {
      final isValid = _validateUpcA(normalized);
      return ProductIdValidation(
        isValid: isValid,
        type: ProductIdType.upcA,
        normalized: normalized,
        error: isValid ? null : 'Invalid UPC-A checksum',
      );
    }

    return ProductIdValidation(
      isValid: false,
      type: ProductIdType.unknown,
      normalized: normalized,
      error: 'Unrecognized product ID format',
    );
  }

  /// Validates UPC-A checksum (12 digits).
  bool _validateUpcA(String code) {
    var sum = 0;
    for (var i = 0; i < 11; i++) {
      final digit = int.parse(code[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == int.parse(code[11]);
  }

  /// Validates EAN-13 checksum (13 digits).
  bool _validateEan13(String code) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(code[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == int.parse(code[12]);
  }

  /// Validates ISBN-10 checksum (10 chars, last can be X).
  bool _validateIsbn10(String code) {
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(code[i]) * (10 - i);
    }
    final last = code[9] == 'X' ? 10 : int.parse(code[9]);
    sum += last;
    return sum % 11 == 0;
  }

  /// Merges user-provided [ProductInfo] into existing data.
  ///
  /// Returns the merged result WITHOUT modifying the database.
  /// The caller must explicitly save the result — this method
  /// never silently overwrites.
  ///
  /// Only non-null fields in [newInfo] overwrite existing values.
  /// Null fields preserve the existing value.
  ProductInfo previewMerge(ProductInfo existing, ProductInfo newInfo) {
    return ProductInfo(
      brand: newInfo.brand ?? existing.brand,
      model: newInfo.model ?? existing.model,
      productId: newInfo.productId ?? existing.productId,
      productIdType: newInfo.productId != null
          ? newInfo.productIdType
          : existing.productIdType,
      manufacturer: newInfo.manufacturer ?? existing.manufacturer,
      specifications: {
        ...existing.specifications,
        ...newInfo.specifications,
      },
    );
  }

  /// Checks if applying [newInfo] would change [existing].
  bool hasChanges(ProductInfo existing, ProductInfo newInfo) {
    final merged = previewMerge(existing, newInfo);
    return merged.brand != existing.brand ||
        merged.model != existing.model ||
        merged.productId != existing.productId ||
        merged.manufacturer != existing.manufacturer ||
        !_mapsEqual(merged.specifications, existing.specifications);
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
