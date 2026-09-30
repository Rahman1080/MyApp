import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/core/database/repositories/service_record_repository.dart';
import 'package:keepit/core/database/repositories/warranty_claim_repository.dart';
import 'package:keepit/core/database/repositories/warranty_repository.dart';
import 'package:keepit/features/warranties/domain/warranty_service.dart';

void main() {
  group('Phase 14 Advanced Warranty and Service History', () {
    late KeepItDatabase db;
    late BelongingRepository belongings;
    late PurchaseRepository purchases;
    late WarrantyRepository warranties;
    late ServiceRecordRepository services;
    late WarrantyClaimRepository claims;
    late WarrantyService warrantyService;

    setUp(() async {
      db = KeepItDatabase(NativeDatabase.memory());
      belongings = BelongingRepository(db);
      purchases = PurchaseRepository(db);
      warranties = WarrantyRepository(db);
      services = ServiceRecordRepository(db);
      claims = WarrantyClaimRepository(db);
      warrantyService = WarrantyService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'schema is v9 with service_records and warranty_claims tables',
      () async {
        expect(db.schemaVersion, 9);

        final tables = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get();
        final tableNames = tables.map((r) => r.read<String>('name')).toSet();
        expect(tableNames, contains('service_records'));
        expect(tableNames, contains('warranty_claims'));
      },
    );

    test('recordService stores service record and history', () async {
      final belongingId = await belongings.create(
        BelongingsCompanion.insert(name: 'Car'),
      );

      final serviceId = await warrantyService.recordService(
        belongingId: belongingId,
        details: ServiceDetails(
          serviceType: ServiceType.oilChange,
          serviceDate: DateTime(2026, 1, 15),
          provider: 'Quick Lube',
          costCents: 4999,
          currencyCode: 'USD',
          notes: 'Full synthetic',
          nextServiceDate: DateTime(2026, 7, 15),
        ),
      );

      final record = await services.getById(serviceId);
      expect(record, isNotNull);
      expect(record!.serviceType, ServiceType.oilChange);
      expect(record.provider, 'Quick Lube');
      expect(record.costCents, 4999);
      expect(record.nextServiceDate, DateTime(2026, 7, 15));
    });

    test('serviceHistory returns records newest first', () async {
      final belongingId = await belongings.create(
        BelongingsCompanion.insert(name: 'Bike'),
      );

      await warrantyService.recordService(
        belongingId: belongingId,
        details: ServiceDetails(
          serviceType: ServiceType.inspection,
          serviceDate: DateTime(2025, 6, 1),
        ),
      );
      await warrantyService.recordService(
        belongingId: belongingId,
        details: ServiceDetails(
          serviceType: ServiceType.repair,
          serviceDate: DateTime(2026, 2, 1),
        ),
      );

      final history = await warrantyService.serviceHistory(belongingId);
      expect(history.length, 2);
      expect(history.first.serviceType, ServiceType.repair);
      expect(history.last.serviceType, ServiceType.inspection);
    });

    test('upcomingMaintenance finds future service dates', () async {
      final belongingId = await belongings.create(
        BelongingsCompanion.insert(name: 'AC Unit'),
      );

      await warrantyService.recordService(
        belongingId: belongingId,
        details: ServiceDetails(
          serviceType: ServiceType.cleaning,
          serviceDate: DateTime(2026, 1, 1),
          nextServiceDate: DateTime(2026, 12, 1),
        ),
      );
      await warrantyService.recordService(
        belongingId: belongingId,
        details: ServiceDetails(
          serviceType: ServiceType.inspection,
          serviceDate: DateTime(2025, 1, 1),
          // No next date - should not appear in upcoming
        ),
      );

      final upcoming = await warrantyService.upcomingMaintenance();
      expect(upcoming.length, 1);
      expect(upcoming.first.serviceType, ServiceType.cleaning);
    });

    test('fileClaim creates claim with filed status', () async {
      final purchaseId = 'purchase1';
      await purchases.create(
        PurchasesCompanion.insert(
          id: Value(purchaseId),
          productName: 'TV',
          store: Value('Best Buy'),
          purchaseDate: Value(DateTime(2026, 1, 1)),
        ),
      );
      final warrantyId = 'warranty1';
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(warrantyId),
          purchaseId: purchaseId,
          provider: Value('Manufacturer'),
        ),
      );

      final claimId = await warrantyService.fileClaim(
        warrantyId: warrantyId,
        details: WarrantyClaimDetails(
          claimDate: DateTime(2026, 3, 15),
          claimNumber: 'CLM-12345',
          description: 'Screen flickering',
        ),
      );

      final claim = await claims.getById(claimId);
      expect(claim, isNotNull);
      expect(claim!.status, WarrantyClaimStatus.filed);
      expect(claim.claimNumber, 'CLM-12345');
    });

    test('updateClaimStatus changes status', () async {
      final purchaseId = 'purchase2';
      await purchases.create(
        PurchasesCompanion.insert(
          id: Value(purchaseId),
          productName: 'Item',
          store: Value('Store'),
          purchaseDate: Value(DateTime(2026, 1, 1)),
        ),
      );
      final warrantyId = 'warranty_fix2';
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(warrantyId),
          purchaseId: purchaseId,
        ),
      );
      final claimId = await warrantyService.fileClaim(
        warrantyId: warrantyId,
        details: WarrantyClaimDetails(claimDate: DateTime.now()),
      );

      await warrantyService.updateClaimStatus(
        claimId,
        WarrantyClaimStatus.approved,
      );

      final claim = await claims.getById(claimId);
      expect(claim!.status, WarrantyClaimStatus.approved);
    });

    test('linkWarrantyToBelonging connects warranty to item', () async {
      final belongingId = await belongings.create(
        BelongingsCompanion.insert(name: 'Laptop'),
      );
      final purchaseId = 'purchase3';
      await purchases.create(
        PurchasesCompanion.insert(
          id: Value(purchaseId),
          productName: 'Laptop',
          store: Value('Apple'),
          purchaseDate: Value(DateTime(2026, 1, 1)),
        ),
      );
      final warrantyId = 'warranty_fix1';
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(warrantyId),
          purchaseId: purchaseId,
        ),
      );

      await warrantyService.linkWarrantyToBelonging(
        warrantyId: warrantyId,
        belongingId: belongingId,
      );

      final warranty = await warranties.getById(warrantyId);
      expect(warranty!.belongingId, belongingId);
    });

    test('claimsForBelonging finds claims via linked warranties', () async {
      final belongingId = await belongings.create(
        BelongingsCompanion.insert(name: 'Phone'),
      );
      final purchaseId = 'purchase4';
      await purchases.create(
        PurchasesCompanion.insert(
          id: Value(purchaseId),
          productName: 'Phone',
          store: Value('Carrier'),
          purchaseDate: Value(DateTime(2026, 1, 1)),
        ),
      );
      final warrantyId = 'warranty_fix0';
      await warranties.create(
        WarrantiesCompanion.insert(
          id: Value(warrantyId),
          purchaseId: purchaseId,
        ),
      );
      await warrantyService.linkWarrantyToBelonging(
        warrantyId: warrantyId,
        belongingId: belongingId,
      );
      await warrantyService.fileClaim(
        warrantyId: warrantyId,
        details: WarrantyClaimDetails(claimDate: DateTime.now()),
      );

      final belongingClaims = await warrantyService.claimsForBelonging(
        belongingId,
      );
      expect(belongingClaims.length, 1);
    });

    test('service type labels resolve', () {
      expect(ServiceType.labelOf(ServiceType.oilChange), 'Oil change');
      expect(ServiceType.labelOf(ServiceType.repair), 'Repair');
      expect(ServiceType.labelOf('unknown'), 'Service');
    });

    test('warranty claim status labels resolve', () {
      expect(WarrantyClaimStatus.labelOf(WarrantyClaimStatus.filed), 'Filed');
      expect(
        WarrantyClaimStatus.labelOf(WarrantyClaimStatus.inProgress),
        'In progress',
      );
      expect(
        WarrantyClaimStatus.labelOf(WarrantyClaimStatus.approved),
        'Approved',
      );
    });
  });
}
