import '../../../core/database/belonging_meta.dart';
import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_photo_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/document_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/receipt_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../shared/services/location_service.dart';
import '../../../shared/services/warranty_service.dart';
import 'inventory_report.dart';

/// Builds [InventoryReport]s from the existing repositories.
///
/// Phase 11 adds no database tables: every fact a report needs (item,
/// category, location path, purchase, receipt, warranty, documents, photos)
/// already lives in schema v5. This service only reads — it never writes,
/// modifies, or deletes user data.
class ReportService {
  ReportService({
    required KeepItDatabase db,
    BelongingPhotoRepository? photoRepository,
    CategoryRepository? categoryRepository,
    DocumentRepository? documentRepository,
    PurchaseRepository? purchaseRepository,
    ReceiptRepository? receiptRepository,
    WarrantyRepository? warrantyRepository,
    LocationService? locationService,
  }) : _db = db,
       _photos = photoRepository ?? BelongingPhotoRepository(db),
       _categories = categoryRepository ?? CategoryRepository(db),
       _documents = documentRepository ?? DocumentRepository(db),
       _purchases = purchaseRepository ?? PurchaseRepository(db),
       _receipts = receiptRepository ?? ReceiptRepository(db),
       _warranties = warrantyRepository ?? WarrantyRepository(db),
       _locations = locationService ?? LocationService(db);

  final KeepItDatabase _db;
  KeepItDatabase get db => _db;
  final BelongingPhotoRepository _photos;
  final CategoryRepository _categories;
  final DocumentRepository _documents;
  final PurchaseRepository _purchases;
  final ReceiptRepository _receipts;
  final WarrantyRepository _warranties;
  final LocationService _locations;

  /// Assembles the report for [scope]. [now] anchors warranty-status math
  /// (defaults to the current time) so tests can fix it.
  Future<InventoryReport> buildReport(
    ReportScope scope, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final all = await _db.select(_db.belongings).get();
    final filtered = await _applyScope(all, scope);
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final categories = {for (final c in await _categories.getAll()) c.id: c};

    final items = <ReportItem>[];
    for (final belonging in filtered) {
      items.add(await _assembleItem(belonging, categories, effectiveNow));
    }

    return InventoryReport(
      scope: scope,
      title: _titleFor(scope),
      generatedAt: effectiveNow,
      items: items,
      missingInfo: _missingInfo(filtered, items),
    );
  }

  // -- scope filtering ----------------------------------------------------

  Future<List<Belonging>> _applyScope(
    List<Belonging> all,
    ReportScope scope,
  ) async {
    Iterable<Belonging> result = all;
    if (!scope.includeInactive) {
      result = result.where(
        (b) => b.archiveState == BelongingArchiveState.owned,
      );
    }
    switch (scope.kind) {
      case ReportScopeKind.full:
        break;
      case ReportScopeKind.selected:
        final ids = scope.selectedIds ?? const <String>{};
        result = result.where((b) => ids.contains(b.id));
        break;
      case ReportScopeKind.category:
        result = result.where((b) => b.categoryId == scope.id);
        break;
      case ReportScopeKind.place:
        final locationIds = await _locationIdsInPlace(scope.id!);
        result = await _inEffectiveLocations(result, locationIds);
        break;
      case ReportScopeKind.location:
        final subtree = <String>{scope.id!};
        for (final child in await _locations.descendants(scope.id!)) {
          subtree.add(child.id);
        }
        result = await _inEffectiveLocations(result, subtree);
        break;
    }
    return result.toList();
  }

  Future<Set<String>> _locationIdsInPlace(String placeId) async {
    final locations = await (_db.select(
      _db.locations,
    )..where((t) => t.placeId.equals(placeId))).get();
    return {for (final l in locations) l.id};
  }

  /// Keeps belongings whose *effective* location is in [locationIds].
  /// An item inside a container derives its location from the outermost
  /// container, whose own locationId is set (container items have their
  /// locationId cleared), so the item is found via its container chain.
  Future<List<Belonging>> _inEffectiveLocations(
    Iterable<Belonging> belongings,
    Set<String> locationIds,
  ) async {
    final result = <Belonging>[];
    for (final b in belongings) {
      final effective = await _effectiveLocationId(b);
      if (effective != null && locationIds.contains(effective)) {
        result.add(b);
      }
    }
    return result;
  }

  /// The location id that actually holds [belonging]: its own locationId,
  /// or the outermost container's locationId when it sits inside a box.
  Future<String?> _effectiveLocationId(Belonging belonging) async {
    if (belonging.containerId == null) return belonging.locationId;
    final chain = await _locations.containerAncestors(belonging);
    if (chain.isEmpty) return belonging.locationId;
    return chain.first.locationId;
  }

  // -- item assembly ------------------------------------------------------

  Future<ReportItem> _assembleItem(
    Belonging belonging,
    Map<String, Category> categories,
    DateTime now,
  ) async {
    final wherePath = await _locations.belongingWherePath(belonging);
    Purchase? purchase;
    Receipt? receipt;
    Warranty? warranty;
    WarrantyStatus? status;
    if (belonging.purchaseId != null) {
      purchase = await _purchases.getById(belonging.purchaseId!);
      if (purchase != null) {
        receipt = await _receipts.getByPurchaseId(purchase.id);
        warranty = await _warranties.getByPurchaseId(purchase.id);
        final expiry = warranty == null
            ? null
            : warrantyExpiryDate(
                startDate: warranty.startDate,
                durationMonths: warranty.durationMonths,
                expirationDate: warranty.expirationDate,
              );
        if (expiry != null) {
          status = warrantyStatus(expiry: expiry, now: now);
        }
      }
    }
    final documents = await _documents.getByBelonging(belonging.id);
    final photos = await _photos.photosFor(belonging.id);
    final photoPaths = <String>[
      if (belonging.photoPath != null && belonging.photoPath!.isNotEmpty)
        belonging.photoPath!,
      for (final p in photos)
        if (p.filePath != belonging.photoPath) p.filePath,
    ];

    return ReportItem(
      belonging: belonging,
      categoryName: categories[belonging.categoryId]?.name,
      locationPath: wherePath.isEmpty ? null : wherePath,
      purchase: purchase,
      receipt: receipt,
      warranty: warranty,
      warrantyStatus: status,
      documents: documents,
      photoPaths: photoPaths,
    );
  }

  // -- missing information ------------------------------------------------

  List<MissingInfoEntry> _missingInfo(
    List<Belonging> belongings,
    List<ReportItem> items,
  ) {
    final entries = <MissingInfoEntry>[];
    for (var i = 0; i < belongings.length; i++) {
      final item = items[i];
      final missing = <MissingField>{};
      if (!item.hasReceipt) missing.add(MissingField.receipt);
      if (!item.hasPhotos) missing.add(MissingField.photo);
      if (!item.hasLocation) missing.add(MissingField.location);
      if (!item.hasPurchaseDate) missing.add(MissingField.purchaseDate);
      if (!item.hasValue) missing.add(MissingField.value);
      if (!item.hasSerialNumber) missing.add(MissingField.serialNumber);
      if (missing.isNotEmpty) {
        entries.add(
          MissingInfoEntry(belonging: belongings[i], missing: missing),
        );
      }
    }
    return entries;
  }

  // -- titles ---------------------------------------------------------------

  String _titleFor(ReportScope scope) {
    final label = scope.label;
    return switch (scope.kind) {
      ReportScopeKind.full => 'Full Inventory Report',
      ReportScopeKind.place =>
        'Home Inventory Report${label == null ? '' : ' — $label'}',
      ReportScopeKind.location =>
        'Room Inventory Report${label == null ? '' : ' — $label'}',
      ReportScopeKind.category =>
        'Category Inventory Report${label == null ? '' : ' — $label'}',
      ReportScopeKind.selected => 'Selected Items Report',
    };
  }
}
