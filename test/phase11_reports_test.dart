import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/database/database_provider.dart';
import 'package:keepit/core/database/keepit_database.dart';
import 'package:keepit/core/database/repositories/belonging_photo_repository.dart';
import 'package:keepit/core/database/repositories/belonging_repository.dart';
import 'package:keepit/core/database/repositories/category_repository.dart';
import 'package:keepit/core/database/repositories/document_repository.dart';
import 'package:keepit/core/database/repositories/location_repository.dart';
import 'package:keepit/core/database/repositories/place_repository.dart';
import 'package:keepit/core/database/repositories/purchase_repository.dart';
import 'package:keepit/core/database/repositories/receipt_repository.dart';
import 'package:keepit/core/database/repositories/warranty_repository.dart';
import 'package:keepit/features/reports/domain/evidence_export_service.dart';
import 'package:keepit/features/reports/domain/inventory_report.dart';
import 'package:keepit/features/reports/domain/pdf_report_builder.dart';
import 'package:keepit/features/reports/domain/report_service.dart';
import 'package:keepit/features/reports/presentation/reports_screen.dart';
import 'package:keepit/shared/services/warranty_service.dart';

/// Phase 11 "Insurance Inventory and Reports" tests: report scopes, item
/// assembly from the existing repositories, the six missing-information
/// checks, PDF generation (empty / small / large / long names / missing
/// files), and the evidence ZIP export.
void main() {
  late KeepItDatabase db;
  late ReportService reports;
  late PdfReportBuilder pdfBuilder;
  late EvidenceExportService exportService;
  late PlaceRepository places;
  late LocationRepository locations;
  late BelongingRepository belongings;
  late CategoryRepository categories;
  late PurchaseRepository purchases;
  late ReceiptRepository receipts;
  late WarrantyRepository warranties;
  late DocumentRepository documents;
  late BelongingPhotoRepository itemPhotos;
  late Directory tempDir;

  // 1x1 transparent PNG used as a stand-in for real photos/receipts.
  Uint8List tinyPng() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  Future<String> writeTempImage(String name) async {
    final file = File('${tempDir.path}/$name.png');
    await file.writeAsBytes(tinyPng());
    return file.path;
  }

  setUp(() async {
    db = openInMemoryDatabase();
    reports = ReportService(db: db);
    pdfBuilder = PdfReportBuilder();
    exportService = EvidenceExportService();
    places = PlaceRepository(db);
    locations = LocationRepository(db);
    belongings = BelongingRepository(db);
    categories = CategoryRepository(db);
    purchases = PurchaseRepository(db);
    receipts = ReceiptRepository(db);
    warranties = WarrantyRepository(db);
    documents = DocumentRepository(db);
    itemPhotos = BelongingPhotoRepository(db);
    tempDir = await Directory.systemTemp.createTemp('keepit-phase11-test');
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> createLocation(
    String name, {
    String? parentId,
    String? placeId,
  }) async {
    final id = 'loc-${name.replaceAll(' ', '-')}';
    await locations.create(
      LocationsCompanion.insert(
        id: Value(id),
        name: name,
        parentLocationId: Value(parentId),
        placeId: placeId == null ? const Value.absent() : Value(placeId),
      ),
    );
    return id;
  }

  Future<String> createItem(
    String name, {
    String? locationId,
    String? categoryId,
    String? purchaseId,
    String? photoPath,
    bool isContainer = false,
    String? containerId,
    int? valueCents,
    String? serialNumber,
    String archiveState = 'owned',
  }) {
    return belongings.create(
      BelongingsCompanion.insert(
        name: name,
        locationId: Value(locationId),
        categoryId: Value(categoryId),
        purchaseId: Value(purchaseId),
        photoPath: Value(photoPath),
        isContainer: Value(isContainer),
        containerId: Value(containerId),
        valueCents: Value(valueCents),
        serialNumber: Value(serialNumber),
        archiveState: Value(archiveState),
      ),
    );
  }

  /// Creates a purchase with a receipt image and a warranty, returning the
  /// purchase id.
  Future<String> createPurchaseWithReceiptAndWarranty({
    required String productName,
    required DateTime purchaseDate,
    required String receiptImagePath,
    DateTime? warrantyExpiry,
  }) async {
    final purchaseId = 'pur-$productName';
    await purchases.create(
      PurchasesCompanion.insert(
        id: Value(purchaseId),
        productName: productName,
        purchaseDate: Value(purchaseDate),
        priceCents: const Value(9999),
      ),
    );
    await receipts.create(
      ReceiptsCompanion.insert(
        purchaseId: purchaseId,
        imagePath: Value(receiptImagePath),
        store: const Value('Test Store'),
      ),
    );
    if (warrantyExpiry != null) {
      await warranties.create(
        WarrantiesCompanion.insert(
          purchaseId: purchaseId,
          provider: const Value('Test Provider'),
          expirationDate: Value(warrantyExpiry),
        ),
      );
    }
    return purchaseId;
  }

  bool isPdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46; // %PDF

  group('report scopes', () {
    test('empty inventory produces an empty report', () async {
      final report = await reports.buildReport(const ReportScope.full());
      expect(report.items, isEmpty);
      expect(report.missingInfo, isEmpty);
      expect(report.title, contains('Full Inventory'));
    });

    test('full report lists owned items sorted by name', () async {
      await createItem('Zebra');
      await createItem('Apple');
      await createItem('Mango', archiveState: 'sold');

      final report = await reports.buildReport(const ReportScope.full());
      expect(report.items.map((i) => i.belonging.name), ['Apple', 'Zebra']);
    });

    test('includeInactive adds sold/donated/disposed/archived items', () async {
      await createItem('Sold item', archiveState: 'sold');
      await createItem('Owned item');

      final ownedOnly = await reports.buildReport(const ReportScope.full());
      expect(ownedOnly.items, hasLength(1));

      final withInactive = await reports.buildReport(
        const ReportScope.full(includeInactive: true),
      );
      expect(withInactive.items, hasLength(2));
    });

    test('place scope only includes items in that place', () async {
      final homeId = await places.createNamed('Home');
      final officeId = await places.createNamed('Office');
      final kitchen = await createLocation('Kitchen', placeId: homeId);
      final desk = await createLocation('Desk', placeId: officeId);
      await createItem('Toaster', locationId: kitchen);
      await createItem('Monitor', locationId: desk);

      final report = await reports.buildReport(
        ReportScope.place(homeId, label: 'Home'),
      );
      expect(report.items.map((i) => i.belonging.name), ['Toaster']);
      expect(report.title, contains('Home'));
    });

    test('location scope includes sub-locations and boxed items', () async {
      final garage = await createLocation('Garage');
      final shelf = await createLocation('Shelf', parentId: garage);
      final boxId = await createItem(
        'Box 1',
        locationId: shelf,
        isContainer: true,
      );
      await createItem('Hammer', locationId: shelf);
      // Items inside a container derive their location from the box.
      await createItem('Nails', containerId: boxId);
      await createItem('Elsewhere');

      final report = await reports.buildReport(
        ReportScope.location(garage, label: 'Garage'),
      );
      final names = report.items.map((i) => i.belonging.name).toSet();
      expect(names, {'Box 1', 'Hammer', 'Nails'});
    });

    test('category scope filters by category', () async {
      final catId = 'cat-electronics';
      await categories.create(
        CategoriesCompanion.insert(id: Value(catId), name: 'Electronics'),
      );
      await createItem('TV', categoryId: catId);
      await createItem('Sofa');

      final report = await reports.buildReport(
        ReportScope.category(catId, label: 'Electronics'),
      );
      expect(report.items.map((i) => i.belonging.name), ['TV']);
    });

    test('selected scope reports only the chosen items', () async {
      final a = await createItem('Alpha');
      await createItem('Beta');
      final c = await createItem('Gamma');

      final report = await reports.buildReport(ReportScope.selected({a, c}));
      expect(report.items.map((i) => i.belonging.name).toSet(), {
        'Alpha',
        'Gamma',
      });
    });
  });

  group('item assembly', () {
    test(
      'assembles category, path, purchase, receipt, warranty, docs',
      () async {
        final now = DateTime(2026, 9, 30);
        final catId = 'cat-av';
        await categories.create(
          CategoriesCompanion.insert(id: Value(catId), name: 'Audio/Video'),
        );
        final garage = await createLocation('Garage');
        final receiptImage = await writeTempImage('receipt');
        final photoPath = await writeTempImage('tv-photo');
        final purchaseId = await createPurchaseWithReceiptAndWarranty(
          productName: 'TV',
          purchaseDate: DateTime(2024, 3, 15),
          receiptImagePath: receiptImage,
          warrantyExpiry: DateTime(2025, 3, 15), // expired at `now`
        );
        final itemId = await createItem(
          'TV',
          locationId: garage,
          categoryId: catId,
          purchaseId: purchaseId,
          photoPath: photoPath,
          valueCents: 49999,
          serialNumber: 'SN-123',
        );
        final docPath = await writeTempImage('manual');
        await documents.create(
          DocumentsCompanion.insert(
            title: 'User manual',
            filePath: docPath,
            belongingId: Value(itemId),
          ),
        );

        final report = await reports.buildReport(
          const ReportScope.full(),
          now: now,
        );
        expect(report.items, hasLength(1));
        final item = report.items.single;
        expect(item.categoryName, 'Audio/Video');
        expect(item.locationPath, contains('Garage'));
        expect(item.purchase?.purchaseDate, DateTime(2024, 3, 15));
        expect(item.hasReceipt, isTrue);
        expect(item.warranty?.provider, 'Test Provider');
        expect(item.warrantyStatus, WarrantyStatus.expired);
        expect(item.documents.map((d) => d.title), ['User manual']);
        expect(item.photoPaths.first, photoPath);
        // Fully documented: no missing-information entry.
        expect(report.missingInfo, isEmpty);
      },
    );

    test('warranty statuses are computed against the report date', () async {
      final now = DateTime(2026, 9, 30);
      final receiptImage = await writeTempImage('receipt2');
      final soonId = await createPurchaseWithReceiptAndWarranty(
        productName: 'Soon',
        purchaseDate: DateTime(2026, 1, 1),
        receiptImagePath: receiptImage,
        warrantyExpiry: DateTime(2026, 10, 10), // 10 days out
      );
      final activeId = await createPurchaseWithReceiptAndWarranty(
        productName: 'Active',
        purchaseDate: DateTime(2026, 1, 1),
        receiptImagePath: receiptImage,
        warrantyExpiry: DateTime(2028, 1, 1),
      );
      await createItem('Expiring item', purchaseId: soonId);
      await createItem('Active item', purchaseId: activeId);

      final report = await reports.buildReport(
        const ReportScope.full(),
        now: now,
      );
      final byName = {for (final i in report.items) i.belonging.name: i};
      expect(
        byName['Expiring item']!.warrantyStatus,
        WarrantyStatus.expiringSoon,
      );
      expect(byName['Active item']!.warrantyStatus, WarrantyStatus.active);
    });

    test('item without purchase has no receipt or purchase date', () async {
      await createItem('Orphan');
      final report = await reports.buildReport(const ReportScope.full());
      final item = report.items.single;
      expect(item.hasReceipt, isFalse);
      expect(item.hasPurchaseDate, isFalse);
      expect(item.warrantyStatus, isNull);
    });
  });

  group('missing information', () {
    test('bare item is flagged for all six checks', () async {
      await createItem('Bare');
      final report = await reports.buildReport(const ReportScope.full());
      expect(report.missingInfo, hasLength(1));
      final entry = report.missingInfo.single;
      expect(entry.missing, {
        MissingField.receipt,
        MissingField.photo,
        MissingField.location,
        MissingField.purchaseDate,
        MissingField.value,
        MissingField.serialNumber,
      });
      // Every check carries a human-readable label and a suggestion.
      for (final field in MissingField.values) {
        expect(field.label, isNotEmpty);
        expect(field.suggestion, isNotEmpty);
      }
    });

    test('partially documented item flags only what is missing', () async {
      final garage = await createLocation('Garage');
      final photoPath = await writeTempImage('bike');
      await createItem(
        'Bike',
        locationId: garage,
        photoPath: photoPath,
        valueCents: 29900,
      );

      final report = await reports.buildReport(const ReportScope.full());
      final entry = report.missingInfo.single;
      expect(entry.missing, {
        MissingField.receipt,
        MissingField.purchaseDate,
        MissingField.serialNumber,
      });
    });
  });

  group('PDF generation', () {
    test('empty report produces a valid PDF', () async {
      final report = await reports.buildReport(const ReportScope.full());
      final bytes = await pdfBuilder.build(report);
      expect(isPdf(bytes), isTrue);
      expect(bytes.length, greaterThan(1000));
    });

    test('full report with photos, long names and missing data', () async {
      final garage = await createLocation('Garage');
      final receiptImage = await writeTempImage('receipt3');
      final photoPath = await writeTempImage('item-photo');
      final purchaseId = await createPurchaseWithReceiptAndWarranty(
        productName: 'Widget',
        purchaseDate: DateTime(2025, 5, 5),
        receiptImagePath: receiptImage,
        warrantyExpiry: DateTime(2027, 5, 5),
      );
      await createItem(
        'Fully documented widget',
        locationId: garage,
        purchaseId: purchaseId,
        photoPath: photoPath,
        valueCents: 1299,
        serialNumber: 'W-1',
      );
      // A very long name must wrap, not break layout.
      await createItem('L' * 500);
      // A photo path pointing at nothing must not break the report.
      await createItem(
        'Missing photo file',
        photoPath: '${tempDir.path}/does-not-exist.png',
      );

      final report = await reports.buildReport(
        const ReportScope.full(),
        now: DateTime(2026, 9, 30),
      );
      final bytes = await pdfBuilder.build(report);
      expect(isPdf(bytes), isTrue);
      // Missing fields are omitted, never invented: the PDF still builds.
      expect(report.missingInfo, hasLength(2));
    });

    test('large inventory report completes', () async {
      for (var i = 0; i < 250; i++) {
        await createItem(
          'Item ${i.toString().padLeft(3, '0')}',
          valueCents: i * 100,
          serialNumber: i.isEven ? 'SN-$i' : null,
        );
      }
      final report = await reports.buildReport(const ReportScope.full());
      expect(report.items, hasLength(250));
      final bytes = await pdfBuilder.build(report);
      expect(isPdf(bytes), isTrue);
    });

    test('item with many photos: PDF embeds one, ZIP keeps all', () async {
      final itemId = await createItem('Gallery piece');
      const photoCount = 20;
      for (var i = 0; i < photoCount; i++) {
        final path = await writeTempImage('gallery-$i');
        await itemPhotos.add(belongingId: itemId, filePath: path);
      }
      final report = await reports.buildReport(const ReportScope.full());
      final item = report.items.singleWhere((i) => i.belonging.id == itemId);
      expect(item.photoPaths, hasLength(photoCount));

      // PDF embeds only the first photo: it must still build quickly and
      // stay a valid PDF with a large gallery attached.
      final pdfBytes = await pdfBuilder.build(report);
      expect(isPdf(pdfBytes), isTrue);

      // The evidence ZIP keeps every photo.
      final zip = await exportService.createEvidenceZip(
        report: report,
        pdfBytes: pdfBytes,
      );
      try {
        final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
        final photoEntries = [
          for (final f in archive.files)
            if (f.isFile && f.name.startsWith('photos/')) f.name,
        ];
        expect(photoEntries, hasLength(photoCount));
      } finally {
        await zip.delete().catchError((_) => zip);
      }
    });
  });

  group('evidence export', () {
    test('ZIP contains PDF, photos, receipts and documents', () async {
      final garage = await createLocation('Garage');
      final receiptImage = await writeTempImage('receipt4');
      final photoPath = await writeTempImage('camera-photo');
      final purchaseId = await createPurchaseWithReceiptAndWarranty(
        productName: 'Camera',
        purchaseDate: DateTime(2024, 6, 1),
        receiptImagePath: receiptImage,
      );
      final itemId = await createItem(
        'Camera',
        locationId: garage,
        purchaseId: purchaseId,
        photoPath: photoPath,
      );
      final docPath = await writeTempImage('warranty-card');
      await documents.create(
        DocumentsCompanion.insert(
          title: 'Warranty card',
          filePath: docPath,
          belongingId: Value(itemId),
        ),
      );

      final report = await reports.buildReport(const ReportScope.full());
      final pdfBytes = await pdfBuilder.build(report);
      final zip = await exportService.createEvidenceZip(
        report: report,
        pdfBytes: pdfBytes,
      );
      try {
        final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
        final names = {
          for (final f in archive.files)
            if (f.isFile) f.name,
        };
        expect(names.any((n) => n.endsWith('inventory-report.pdf')), isTrue);
        expect(
          names.any(
            (n) => n.startsWith('photos/Camera/') && n.endsWith('.png'),
          ),
          isTrue,
        );
        expect(
          names.any((n) => n.startsWith('receipts/') && n.endsWith('.png')),
          isTrue,
        );
        expect(
          names.any((n) => n.startsWith('documents/') && n.endsWith('.png')),
          isTrue,
        );
      } finally {
        await zip.delete().catchError((_) => zip);
      }
    });

    test('missing files are skipped, never fatal', () async {
      await createItem('Ghost photo', photoPath: '${tempDir.path}/nope.png');
      final report = await reports.buildReport(const ReportScope.full());
      final pdfBytes = await pdfBuilder.build(report);
      final zip = await exportService.createEvidenceZip(
        report: report,
        pdfBytes: pdfBytes,
      );
      try {
        final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
        final names = [
          for (final f in archive.files)
            if (f.isFile) f.name,
        ];
        // Only the PDF: the ghost photo was skipped silently.
        expect(names, hasLength(1));
        expect(names.single.endsWith('inventory-report.pdf'), isTrue);
      } finally {
        await zip.delete().catchError((_) => zip);
      }
    });
  });

  group('reports screen', () {
    testWidgets('generating a full report shows summary and actions', (
      tester,
    ) async {
      final screenDb = openInMemoryDatabase();
      final screenBelongings = BelongingRepository(screenDb);
      addTearDown(() async {
        await tester.binding.delayed(Duration.zero);
        await screenDb.close();
      });
      await screenBelongings.create(BelongingsCompanion.insert(name: 'Widget'));

      await tester.pumpWidget(
        MaterialApp(
          home: ReportsScreen(
            reportService: ReportService(db: screenDb),
            pdfBuilder: PdfReportBuilder(),
            exportService: EvidenceExportService(),
            placeRepository: PlaceRepository(screenDb),
            locationRepository: LocationRepository(screenDb),
            categoryRepository: CategoryRepository(screenDb),
            belongingRepository: screenBelongings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventory Reports'), findsOneWidget);
      expect(find.text('Full inventory'), findsOneWidget);

      await tester.tap(find.text('Generate report'));
      await tester.pumpAndSettle();

      expect(find.text('Full Inventory Report'), findsWidgets);
      expect(find.text('Save PDF'), findsOneWidget);
      expect(find.text('Share PDF'), findsOneWidget);
      expect(find.text('Export evidence ZIP'), findsOneWidget);
      // The bare item is missing everything.
      expect(find.text('Missing information'), findsOneWidget);
    });
  });
}
