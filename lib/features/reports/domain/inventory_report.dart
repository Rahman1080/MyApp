import '../../../core/database/keepit_database.dart';
import '../../../shared/services/warranty_service.dart';

/// Which slice of the inventory a report covers.
enum ReportScopeKind {
  /// Every item in the database.
  full,

  /// Everything stored in one place ("My Home", "Office", ...).
  place,

  /// Everything in one location and its sub-locations.
  location,

  /// Everything in one category.
  category,

  /// An explicit hand-picked set of items.
  selected,
}

/// A report scope: the kind plus the id it refers to (place id, location
/// id, category id) or the hand-picked item ids for [ReportScopeKind.selected].
class ReportScope {
  const ReportScope.full({this.includeInactive = false})
    : kind = ReportScopeKind.full,
      id = null,
      label = null,
      selectedIds = null;

  const ReportScope.place(this.id, {this.label, this.includeInactive = false})
    : kind = ReportScopeKind.place,
      selectedIds = null;

  const ReportScope.location(
    this.id, {
    this.label,
    this.includeInactive = false,
  }) : kind = ReportScopeKind.location,
       selectedIds = null;

  const ReportScope.category(
    this.id, {
    this.label,
    this.includeInactive = false,
  }) : kind = ReportScopeKind.category,
       selectedIds = null;

  const ReportScope.selected(this.selectedIds, {this.includeInactive = false})
    : kind = ReportScopeKind.selected,
      id = null,
      label = null;

  final ReportScopeKind kind;

  /// Place id, location id or category id depending on [kind].
  final String? id;
  final String? label;
  final Set<String>? selectedIds;

  /// When false (default) only currently owned items are reported; when
  /// true, archived/sold/donated/disposed items are included too.
  final bool includeInactive;
}

/// One inventory line: the belonging plus everything the report needs
/// about it, assembled from the existing repositories. Fields that have no
/// data stay null — the PDF builder renders only what is available and
/// never invents missing values.
class ReportItem {
  const ReportItem({
    required this.belonging,
    this.categoryName,
    this.locationPath,
    this.purchase,
    this.receipt,
    this.warranty,
    this.warrantyStatus,
    this.documents = const [],
    this.photoPaths = const [],
  });

  final Belonging belonging;
  final String? categoryName;

  /// Full "where is it?" path, e.g. "My Home > Garage > Box 7".
  /// Null when the item has no stored location.
  final String? locationPath;

  final Purchase? purchase;
  final Receipt? receipt;
  final Warranty? warranty;

  /// Computed from the warranty's expiry against the report date.
  /// Null when the item has no warranty with a known expiry.
  final WarrantyStatus? warrantyStatus;

  final List<Document> documents;

  /// Local photo paths: cover photo first, then gallery photos.
  final List<String> photoPaths;

  /// A receipt counts as available only when the purchase has a receipt
  /// row with an actual image file recorded.
  bool get hasReceipt =>
      receipt != null &&
      (receipt!.imagePath != null && receipt!.imagePath!.isNotEmpty);

  bool get hasPhotos => photoPaths.isNotEmpty;
  bool get hasLocation => locationPath != null && locationPath!.isNotEmpty;
  bool get hasPurchaseDate => purchase?.purchaseDate != null;
  bool get hasValue => belonging.valueCents != null;
  bool get hasSerialNumber =>
      belonging.serialNumber != null &&
      belonging.serialNumber!.trim().isNotEmpty;
}

/// The six "missing information" checks from the Phase 11 spec.
enum MissingField {
  receipt,
  photo,
  location,
  purchaseDate,
  value,
  serialNumber,
}

extension MissingFieldLabel on MissingField {
  String get label => switch (this) {
    MissingField.receipt => 'No receipt',
    MissingField.photo => 'No photos',
    MissingField.location => 'No location',
    MissingField.purchaseDate => 'No purchase date',
    MissingField.value => 'No value',
    MissingField.serialNumber => 'No serial number',
  };

  /// What the user can do about it, shown next to the item.
  String get suggestion => switch (this) {
    MissingField.receipt =>
      'Link the purchase this item came from, or scan its receipt.',
    MissingField.photo => 'Take a photo of the item for visual evidence.',
    MissingField.location => 'Record where the item is stored.',
    MissingField.purchaseDate =>
      'Add the purchase date from the receipt or order history.',
    MissingField.value => 'Enter an estimated current value.',
    MissingField.serialNumber =>
      'Add the serial number from the product or its box.',
  };
}

/// One item together with the fields it is missing.
class MissingInfoEntry {
  const MissingInfoEntry({required this.belonging, required this.missing});

  final Belonging belonging;
  final Set<MissingField> missing;
}

/// A complete generated report: the scope it was built from, when it was
/// generated, and the assembled items. Pure data — rendering (PDF) and
/// export (ZIP) are separate steps.
class InventoryReport {
  const InventoryReport({
    required this.scope,
    required this.title,
    required this.generatedAt,
    required this.items,
    required this.missingInfo,
  });

  final ReportScope scope;
  final String title;
  final DateTime generatedAt;
  final List<ReportItem> items;
  final List<MissingInfoEntry> missingInfo;

  /// Items missing at least one piece of information.
  int get incompleteCount => missingInfo.length;

  /// Sum of known estimated values, in minor units. Items without a value
  /// contribute nothing — never a fake zero average.
  ///
  /// WARNING: this sums across currencies without conversion. For display,
  /// prefer [valueByCurrency], which groups by currency code.
  int get totalValueCents =>
      items.fold(0, (sum, item) => sum + (item.belonging.valueCents ?? 0));

  /// Known estimated values grouped by currency code (never converted).
  /// Items without a value or currency are skipped.
  Map<String, int> get valueByCurrency {
    final totals = <String, int>{};
    for (final item in items) {
      final cents = item.belonging.valueCents;
      final code = item.belonging.currencyCode;
      if (cents == null || code == null || code.isEmpty) continue;
      totals[code] = (totals[code] ?? 0) + cents;
    }
    return totals;
  }

  int get valuedItemCount =>
      items.where((item) => item.belonging.valueCents != null).length;
}
