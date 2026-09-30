import 'package:drift/drift.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_history_repository.dart';
import '../../../core/database/repositories/service_record_repository.dart';
import '../../../core/database/repositories/warranty_claim_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';

/// Service types for maintenance records.
class ServiceType {
  static const String oilChange = 'oil_change';
  static const String repair = 'repair';
  static const String inspection = 'inspection';
  static const String cleaning = 'cleaning';
  static const String tuneUp = 'tune_up';
  static const String other = 'other';

  static const List<String> all = [
    oilChange,
    repair,
    inspection,
    cleaning,
    tuneUp,
    other,
  ];

  static String labelOf(String? type) {
    switch (type) {
      case oilChange:
        return 'Oil change';
      case repair:
        return 'Repair';
      case inspection:
        return 'Inspection';
      case cleaning:
        return 'Cleaning';
      case tuneUp:
        return 'Tune-up';
      case other:
        return 'Other';
      default:
        return 'Service';
    }
  }
}

/// Warranty claim statuses.
class WarrantyClaimStatus {
  static const String filed = 'filed';
  static const String inProgress = 'in_progress';
  static const String approved = 'approved';
  static const String denied = 'denied';
  static const String closed = 'closed';

  static const List<String> all = [filed, inProgress, approved, denied, closed];

  static String labelOf(String? status) {
    switch (status) {
      case filed:
        return 'Filed';
      case inProgress:
        return 'In progress';
      case approved:
        return 'Approved';
      case denied:
        return 'Denied';
      case closed:
        return 'Closed';
      default:
        return 'Unknown';
    }
  }
}

/// Details for recording a service event.
class ServiceDetails {
  ServiceDetails({
    required this.serviceType,
    required this.serviceDate,
    this.provider,
    this.costCents,
    this.currencyCode,
    this.notes,
    this.nextServiceDate,
  });

  final String serviceType;
  final DateTime serviceDate;
  final String? provider;
  final int? costCents;
  final String? currencyCode;
  final String? notes;
  final DateTime? nextServiceDate;
}

/// Details for filing a warranty claim.
class WarrantyClaimDetails {
  WarrantyClaimDetails({
    required this.claimDate,
    this.claimNumber,
    this.description,
  });

  final DateTime claimDate;
  final String? claimNumber;
  final String? description;
}

/// Domain service for advanced warranty and service history (Phase 14).
///
/// Coordinates service records, warranty claims, and history entries.
class WarrantyService {
  WarrantyService(KeepItDatabase db)
    : _services = ServiceRecordRepository(db),
      _claims = WarrantyClaimRepository(db),
      _warranties = WarrantyRepository(db),
      _history = BelongingHistoryRepository(db);

  final ServiceRecordRepository _services;
  final WarrantyClaimRepository _claims;
  final WarrantyRepository _warranties;
  final BelongingHistoryRepository _history;

  /// Records a service/maintenance event for a belonging.
  Future<String> recordService({
    required String belongingId,
    required ServiceDetails details,
  }) async {
    final id = await _services.create(
      ServiceRecordsCompanion.insert(
        belongingId: belongingId,
        serviceType: details.serviceType,
        serviceDate: details.serviceDate,
        provider: Value(details.provider),
        costCents: Value(details.costCents),
        currencyCode: Value(details.currencyCode),
        notes: Value(details.notes),
        nextServiceDate: Value(details.nextServiceDate),
      ),
    );

    await _history.log(
      belongingId: belongingId,
      eventType: 'service',
      title: '${ServiceType.labelOf(details.serviceType)} recorded',
      details: details.provider,
    );

    return id;
  }

  /// Files a warranty claim.
  Future<String> fileClaim({
    required String warrantyId,
    required WarrantyClaimDetails details,
  }) async {
    final id = await _claims.create(
      WarrantyClaimsCompanion.insert(
        warrantyId: warrantyId,
        claimDate: details.claimDate,
        claimNumber: Value(details.claimNumber),
        description: Value(details.description),
      ),
    );

    // Log to history if warranty is linked to a belonging.
    final warranty = await _warranties.getById(warrantyId);
    if (warranty?.belongingId != null) {
      await _history.log(
        belongingId: warranty!.belongingId!,
        eventType: 'warranty_claim',
        title: 'Warranty claim filed',
        details: details.claimNumber,
      );
    }

    return id;
  }

  /// Updates a claim's status.
  Future<void> updateClaimStatus(String claimId, String status) async {
    assert(WarrantyClaimStatus.all.contains(status));
    await _claims.updateStatus(claimId, status);
  }

  /// Links a warranty directly to a belonging.
  Future<void> linkWarrantyToBelonging({
    required String warrantyId,
    required String belongingId,
  }) async {
    await _warranties.update(
      warrantyId,
      WarrantiesCompanion(belongingId: Value(belongingId)),
    );
  }

  /// Gets all service records for a belonging.
  Future<List<ServiceRecord>> serviceHistory(String belongingId) =>
      _services.forBelonging(belongingId);

  /// Gets all warranty claims for a belonging.
  Future<List<WarrantyClaim>> claimsForBelonging(String belongingId) =>
      _claims.forBelonging(belongingId);

  /// Gets upcoming maintenance (records with future next_service_date).
  Future<List<ServiceRecord>> upcomingMaintenance() => _services.upcoming();
}
