import 'dart:convert';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_history_repository.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/document_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/service_record_repository.dart';
import '../../../core/database/repositories/warranty_claim_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';

/// Complete lifetime record for a single item (Phase 22).
///
/// Aggregates all data about an item into one portable record:
/// - Basic item details
/// - Acquisition information (Phase 13)
/// - Full history timeline (Phase 9)
/// - Warranties (Phase 14)
/// - Service records (Phase 14)
/// - Warranty claims (Phase 14)
/// - Purchase information
/// - Documents
/// - Disposition information (Phase 13)
///
/// The record can be exported to JSON for portability.
class ItemLifetimeRecord {
  const ItemLifetimeRecord({
    required this.belonging,
    required this.history,
    required this.warranties,
    required this.serviceRecords,
    required this.warrantyClaims,
    required this.purchase,
    required this.documents,
    required this.exportedAt,
  });

  final Belonging belonging;
  final List<BelongingHistoryData> history;
  final List<Warranty> warranties;
  final List<ServiceRecord> serviceRecords;
  final List<WarrantyClaim> warrantyClaims;
  final Purchase? purchase;
  final List<Document> documents;
  final DateTime exportedAt;

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'exportedAt': exportedAt.toIso8601String(),
      'belonging': {
        'id': belonging.id,
        'name': belonging.name,
        'brand': belonging.brand,
        'model': belonging.model,
        'serialNumber': belonging.serialNumber,
        'categoryId': belonging.categoryId,
        'locationId': belonging.locationId,
        'quantity': belonging.quantity,
        'valueCents': belonging.valueCents,
        'currencyCode': belonging.currencyCode,
        'condition': belonging.condition,
        'archiveState': belonging.archiveState,
        'archivedAt': belonging.archivedAt?.toIso8601String(),
        'acquisitionType': belonging.acquisitionType,
        'acquisitionDate': belonging.acquisitionDate?.toIso8601String(),
        'dispositionDate': belonging.dispositionDate?.toIso8601String(),
        'dispositionPriceCents': belonging.dispositionPriceCents,
        'dispositionCurrencyCode': belonging.dispositionCurrencyCode,
        'dispositionRecipient': belonging.dispositionRecipient,
        'dispositionMethod': belonging.dispositionMethod,
        'dispositionNotes': belonging.dispositionNotes,
        'privacyLevel': belonging.privacyLevel,
        'ownerMemberId': belonging.ownerMemberId,
        'notes': belonging.notes,
        'createdAt': belonging.createdAt.toIso8601String(),
        'updatedAt': belonging.updatedAt.toIso8601String(),
      },
      'history': history
          .map((h) => {
                'id': h.id,
                'eventType': h.eventType,
                'title': h.title,
                'details': h.details,
                'occurredAt': h.occurredAt.toIso8601String(),
                'relatedEntityType': h.relatedEntityType,
                'relatedEntityId': h.relatedEntityId,
              })
          .toList(),
      'warranties': warranties
          .map((w) => {
                'id': w.id,
                'provider': w.provider,
                'warrantyNumber': w.warrantyNumber,
                'startDate': w.startDate?.toIso8601String(),
                'expirationDate': w.expirationDate?.toIso8601String(),
                'durationMonths': w.durationMonths,
                'notes': w.notes,
              })
          .toList(),
      'serviceRecords': serviceRecords
          .map((s) => {
                'id': s.id,
                'serviceType': s.serviceType,
                'serviceDate': s.serviceDate.toIso8601String(),
                'provider': s.provider,
                'costCents': s.costCents,
                'currencyCode': s.currencyCode,
                'notes': s.notes,
              })
          .toList(),
      'warrantyClaims': warrantyClaims
          .map((c) => {
                'id': c.id,
                'warrantyId': c.warrantyId,
                'claimNumber': c.claimNumber,
                'status': c.status,
                'claimDate': c.claimDate.toIso8601String(),
                'description': c.description,
              })
          .toList(),
      'purchase': purchase == null
          ? null
          : {
              'id': purchase!.id,
              'productName': purchase!.productName,
              'store': purchase!.store,
              'purchaseDate': purchase!.purchaseDate?.toIso8601String(),
              'priceCents': purchase!.priceCents,
              'currencyCode': purchase!.currencyCode,
            },
      'documents': documents
          .map((d) => {
                'id': d.id,
                'title': d.title,
                'filePath': d.filePath,
                'mimeType': d.mimeType,
                'documentType': d.documentType,
                'notes': d.notes,
              })
          .toList(),
    };
  }

  /// Serializes to a JSON string.
  String toJsonString() => jsonEncode(toJson());
}

/// Service for generating complete item lifetime records (Phase 22).
///
/// Read-only aggregation. Never modifies data.
class ItemLifetimeService {
  ItemLifetimeService(KeepItDatabase db)
    : _belongings = BelongingRepository(db),
      _history = BelongingHistoryRepository(db),
      _warranties = WarrantyRepository(db),
      _services = ServiceRecordRepository(db),
      _claims = WarrantyClaimRepository(db),
      _purchases = PurchaseRepository(db),
      _documents = DocumentRepository(db);

  final BelongingRepository _belongings;
  final BelongingHistoryRepository _history;
  final WarrantyRepository _warranties;
  final ServiceRecordRepository _services;
  final WarrantyClaimRepository _claims;
  final PurchaseRepository _purchases;
  final DocumentRepository _documents;

  /// Generates the complete lifetime record for an item.
  ///
  /// Throws [StateError] if the item does not exist.
  Future<ItemLifetimeRecord> getLifetimeRecord(String belongingId) async {
    final belonging = await _belongings.getById(belongingId);
    if (belonging == null) {
      throw StateError('Belonging not found: $belongingId');
    }

    final history = await _history.historyFor(belongingId);
    final warranties = await _warranties.forBelonging(belongingId);
    final serviceRecords = await _services.forBelonging(belongingId);
    final warrantyClaims = await _claims.forBelonging(belongingId);
    final documents = await _documents.getByBelonging(belongingId);

    // Find purchase via purchase_id.
    Purchase? purchase;
    if (belonging.purchaseId != null) {
      purchase = await _purchases.getById(belonging.purchaseId!);
    }

    return ItemLifetimeRecord(
      belonging: belonging,
      history: history,
      warranties: warranties,
      serviceRecords: serviceRecords,
      warrantyClaims: warrantyClaims,
      purchase: purchase,
      documents: documents,
      exportedAt: DateTime.now(),
    );
  }

  /// Exports the lifetime record as a JSON string.
  Future<String> exportToJson(String belongingId) async {
    final record = await getLifetimeRecord(belongingId);
    return record.toJsonString();
  }
}
