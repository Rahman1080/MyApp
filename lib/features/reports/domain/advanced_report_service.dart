import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import 'report_filter.dart';

/// CSV exporter for inventory reports (Phase 23).
///
/// Generates RFC 4180-compliant CSV:
/// - Fields containing commas, quotes, or newlines are quoted
/// - Quotes within fields are doubled
/// - UTF-8 encoding (with BOM for Excel compatibility)
class CsvExporter {
  /// Exports belongings to CSV format.
  ///
  /// Returns the CSV content as a string (UTF-8, with BOM).
  String export(List<Belonging> belongings) {
    final buffer = StringBuffer();

    // BOM for Excel UTF-8 compatibility.
    buffer.write('\uFEFF');

    // Header row.
    buffer.writeln(_csvRow([
      'ID',
      'Name',
      'Brand',
      'Model',
      'Serial Number',
      'Category ID',
      'Location ID',
      'Quantity',
      'Value (cents)',
      'Currency',
      'Condition',
      'Archive State',
      'Acquisition Type',
      'Acquisition Date',
      'Privacy Level',
      'Notes',
      'Created At',
      'Updated At',
    ]));

    // Data rows.
    for (final b in belongings) {
      buffer.writeln(_csvRow([
        b.id,
        b.name,
        b.brand ?? '',
        b.model ?? '',
        b.serialNumber ?? '',
        b.categoryId ?? '',
        b.locationId ?? '',
        b.quantity.toString(),
        b.valueCents?.toString() ?? '',
        b.currencyCode ?? '',
        b.condition ?? '',
        b.archiveState,
        b.acquisitionType ?? '',
        b.acquisitionDate?.toIso8601String() ?? '',
        b.privacyLevel,
        b.notes ?? '',
        b.createdAt.toIso8601String(),
        b.updatedAt.toIso8601String(),
      ]));
    }

    return buffer.toString();
  }

  /// Formats a single CSV row, quoting fields as needed.
  String _csvRow(List<String> fields) {
    return fields.map(_escapeField).join(',');
  }

  /// Escapes a single CSV field per RFC 4180.
  String _escapeField(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      // Double any quotes, then wrap in quotes.
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }
}

/// Advanced reporting service (Phase 23).
///
/// Extends Phase 11 reporting with:
/// - Advanced filters (category, location, condition, value range,
///   privacy, archive state, acquisition date, text search)
/// - CSV export
///
/// PDF generation remains in Phase 11's ReportService/PdfReportBuilder.
/// Share/print integration uses share_plus (already a dependency).
class AdvancedReportService {
  AdvancedReportService(KeepItDatabase db)
    : _belongings = BelongingRepository(db);

  final BelongingRepository _belongings;
  final CsvExporter _csvExporter = CsvExporter();

  /// Returns belongings matching all filter criteria.
  ///
  /// Filters are combined with AND logic. An empty filter returns all items.
  Future<List<Belonging>> filterBelongings(ReportFilter filter) async {
    final all = await _belongings.getAll();

    if (filter.isEmpty) return all;

    return all.where((b) => _matches(b, filter)).toList();
  }

  /// Exports filtered belongings to CSV.
  Future<String> exportCsv(ReportFilter filter) async {
    final filtered = await filterBelongings(filter);
    return _csvExporter.export(filtered);
  }

  /// Checks if a belonging matches all filter criteria.
  bool _matches(Belonging b, ReportFilter filter) {
    // Category filter.
    if (filter.categoryIds != null &&
        !filter.categoryIds!.contains(b.categoryId)) {
      return false;
    }

    // Location filter.
    if (filter.locationIds != null &&
        !filter.locationIds!.contains(b.locationId)) {
      return false;
    }

    // Condition filter.
    if (filter.conditions != null &&
        !filter.conditions!.contains(b.condition)) {
      return false;
    }

    // Value range filter.
    if (filter.minValueCents != null) {
      final value = b.valueCents ?? 0;
      if (value < filter.minValueCents!) return false;
    }
    if (filter.maxValueCents != null) {
      final value = b.valueCents ?? 0;
      if (value > filter.maxValueCents!) return false;
    }

    // Privacy filter.
    if (filter.privacyLevels != null &&
        !filter.privacyLevels!.contains(b.privacyLevel)) {
      return false;
    }

    // Archive state filter.
    if (filter.archiveStates != null &&
        !filter.archiveStates!.contains(b.archiveState)) {
      return false;
    }

    // Acquisition date range.
    if (filter.acquiredAfter != null) {
      if (b.acquisitionDate == null ||
          b.acquisitionDate!.isBefore(filter.acquiredAfter!)) {
        return false;
      }
    }
    if (filter.acquiredBefore != null) {
      if (b.acquisitionDate == null ||
          b.acquisitionDate!.isAfter(filter.acquiredBefore!)) {
        return false;
      }
    }

    // Text search (name, brand, model, notes).
    if (filter.searchText != null && filter.searchText!.isNotEmpty) {
      final query = filter.searchText!.toLowerCase();
      final searchable = [
        b.name,
        b.brand,
        b.model,
        b.notes,
      ].whereType<String>().join(' ').toLowerCase();
      if (!searchable.contains(query)) return false;
    }

    return true;
  }
}
