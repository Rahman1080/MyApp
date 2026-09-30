import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../core/utilities/money.dart';
import '../domain/evidence_export_service.dart';
import '../domain/inventory_report.dart';
import '../domain/pdf_report_builder.dart';
import '../domain/report_service.dart';
import '../domain/advanced_report_service.dart';
import '../../web/domain/web_companion_service.dart';

/// Phase 11 — Insurance inventory and reports.
///
/// Lets the user generate a professional PDF inventory report (full, per
/// place, per location, per category, or hand-picked items), review what
/// information is missing, and export an evidence ZIP with the PDF plus
/// the original photos, receipt images and documents. Everything is
/// user-initiated; nothing is uploaded.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.reportService,
    required this.pdfBuilder,
    required this.exportService,
    required this.placeRepository,
    required this.locationRepository,
    required this.categoryRepository,
    required this.belongingRepository,
  });

  static const routePath = '/reports';

  final ReportService reportService;
  final PdfReportBuilder pdfBuilder;
  final EvidenceExportService exportService;
  final PlaceRepository placeRepository;
  final LocationRepository locationRepository;
  final CategoryRepository categoryRepository;
  final BelongingRepository belongingRepository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportScopeKind _kind = ReportScopeKind.full;
  String? _placeId;
  String? _locationId;
  String? _categoryId;
  bool _includeInactive = false;
  final Set<String> _selectedIds = {};

  List<Place> _places = [];
  List<Location> _locations = [];
  List<Category> _categories = [];
  List<Belonging> _belongings = [];
  bool _loadingPickers = true;

  InventoryReport? _report;
  bool _busy = false;

  final _dateFormat = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    _loadPickers();
  }

  Future<void> _loadPickers() async {
    // One-shot queries: watch().first can stall later queries under
    // Flutter's FakeAsync test clock, so picker loads use get().
    final places = await widget.placeRepository.getAll();
    final locations = await widget.locationRepository.getAll();
    final categories = await widget.categoryRepository.getAll();
    final belongings = await widget.belongingRepository.getAll();
    if (!mounted) return;
    setState(() {
      _places = places;
      _locations = locations;
      _categories = categories;
      _belongings = belongings;
      _placeId = places.isNotEmpty ? places.first.id : null;
      _categoryId = categories.isNotEmpty ? categories.first.id : null;
      _locationId = locations.isNotEmpty ? locations.first.id : null;
      _loadingPickers = false;
    });
  }

  String _locationLabel(Location location) {
    final byId = {for (final l in _locations) l.id: l};
    final names = <String>[location.name];
    var parentId = location.parentLocationId;
    final seen = <String>{location.id};
    while (parentId != null && seen.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      names.insert(0, parent.name);
      parentId = parent.parentLocationId;
    }
    final placeName = _places
        .where((pl) => pl.id == location.placeId)
        .map((pl) => pl.name)
        .firstOrNull;
    if (placeName != null) names.insert(0, placeName);
    return names.join(' › ');
  }

  ReportScope _currentScope() {
    String? labelFor(String? id, List<dynamic> list) {
      if (id == null) return null;
      for (final e in list) {
        if ((e as dynamic).id == id) return (e as dynamic).name as String;
      }
      return null;
    }

    return switch (_kind) {
      ReportScopeKind.full => ReportScope.full(
        includeInactive: _includeInactive,
      ),
      ReportScopeKind.place => ReportScope.place(
        _placeId,
        label: labelFor(_placeId, _places),
        includeInactive: _includeInactive,
      ),
      ReportScopeKind.location => ReportScope.location(
        _locationId,
        label: _locationId == null
            ? null
            : _locationLabel(_locations.firstWhere((l) => l.id == _locationId)),
        includeInactive: _includeInactive,
      ),
      ReportScopeKind.category => ReportScope.category(
        _categoryId,
        label: labelFor(_categoryId, _categories),
        includeInactive: _includeInactive,
      ),
      ReportScopeKind.selected => ReportScope.selected(
        Set.of(_selectedIds),
        includeInactive: _includeInactive,
      ),
    };
  }

  Future<void> _generate() async {
    if (_busy) return;
    if (_kind == ReportScopeKind.selected && _selectedIds.isEmpty) {
      _snack('Select at least one item first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final report = await widget.reportService.buildReport(_currentScope());
      if (!mounted) return;
      setState(() => _report = report);
    } catch (_) {
      _snack('The report could not be generated. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Builds the PDF for the current report, showing a progress dialog
  /// while the (potentially large) document renders.
  Future<({String fileName, Uint8List bytes})?> _buildPdf() async {
    final report = _report;
    if (report == null) return null;
    final progress = ValueNotifier<double>(0);
    var dialogOpen = false;
    try {
      if (mounted) {
        dialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                const Expanded(child: Text('Generating PDF report')),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, value, _) =>
                      Text('${(value * 100).round()}%'),
                ),
              ],
            ),
          ),
        );
      }
      // The pdf package renders synchronously; yield so the dialog paints.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      progress.value = 0.3;
      final bytes = await widget.pdfBuilder.build(report);
      progress.value = 1.0;
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(report.generatedAt);
      return (fileName: 'keepit-inventory-$stamp.pdf', bytes: bytes);
    } finally {
      progress.dispose();
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _savePdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) return;
      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Save inventory report',
        fileName: pdf.fileName,
        bytes: pdf.bytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savedUri == null) {
        _snack('Save cancelled.');
        return;
      }
      _snack('Report saved.');
    } catch (_) {
      _snack('The PDF could not be created. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) return;
      final temp = File(p.join(Directory.systemTemp.path, pdf.fileName));
      await temp.writeAsBytes(pdf.bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(temp.path)],
          subject: 'KEEPIT inventory report',
          text: 'KEEPIT inventory report',
        ),
      );
    } catch (_) {
      _snack('Sharing failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportEvidence() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final report = _report;
      if (report == null) return;
      final pdf = await _buildPdf();
      if (pdf == null || !mounted) return;
      final zip = await widget.exportService.createEvidenceZip(
        report: report,
        pdfBytes: pdf.bytes,
      );
      try {
        final bytes = await zip.readAsBytes();
        final savedUri = await FilePicker.saveFile(
          dialogTitle: 'Save evidence export',
          fileName: p.basename(zip.path),
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (savedUri == null) {
          _snack('Export cancelled.');
          return;
        }
        _snack('Evidence exported.');
      } finally {
        await zip.delete().catchError((_) => zip);
      }
    } catch (_) {
      _snack('The evidence export could not be created. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareCsv() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final report = _report;
      if (report == null) return;
      final csv = CsvExporter().export(report.items.map((i) => i.belonging).toList());
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(report.generatedAt);
      final fileName = 'keepit-inventory-$stamp.csv';
      final temp = File(p.join(Directory.systemTemp.path, fileName));
      await temp.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(temp.path)],
          subject: '${report.title} (CSV)',
          text: '${report.title} CSV export',
        ),
      );
    } catch (_) {
      _snack('CSV export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareWebCompanion() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final report = _report;
      if (report == null) return;
      final html = await WebCompanionService(widget.reportService.db).generateHtml(
        title: report.title,
        locationId: _kind == ReportScopeKind.location ? _locationId : null,
      );
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(report.generatedAt);
      final fileName = 'keepit-web-$stamp.html';
      final temp = File(p.join(Directory.systemTemp.path, fileName));
      await temp.writeAsString(html);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(temp.path)],
          subject: '${report.title} (Web Companion HTML)',
          text: '${report.title} Web Companion HTML file',
        ),
      );
    } catch (_) {
      _snack('Web Companion export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Reports')),
      body: _loadingPickers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _scopePicker(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Include past items'),
                    subtitle: const Text(
                      'Also report sold, donated, disposed and archived items.',
                    ),
                    value: _includeInactive,
                    onChanged: (v) => setState(() => _includeInactive = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: const Icon(Icons.summarize_outlined),
                    label: const Text('Generate report'),
                  ),
                  if (_report != null) ...[
                    const SizedBox(height: 16),
                    _reportSummary(_report!),
                    const SizedBox(height: 12),
                    _exportButtons(),
                    const SizedBox(height: 16),
                    _missingInfoSection(_report!),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _scopePicker() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report type', style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<ReportScopeKind>(
              groupValue: _kind,
              onChanged: (v) =>
                  setState(() => _kind = v ?? ReportScopeKind.full),
              child: Column(
                children: [
                  for (final kind in ReportScopeKind.values)
                    RadioListTile<ReportScopeKind>(
                      title: Text(_kindLabel(kind)),
                      value: kind,
                      dense: true,
                    ),
                ],
              ),
            ),
            _scopeDetail(),
          ],
        ),
      ),
    );
  }

  String _kindLabel(ReportScopeKind kind) => switch (kind) {
    ReportScopeKind.full => 'Full inventory',
    ReportScopeKind.place => 'Home inventory (by place)',
    ReportScopeKind.location => 'Room inventory (by location)',
    ReportScopeKind.category => 'Category inventory',
    ReportScopeKind.selected => 'Selected items',
  };

  Widget _scopeDetail() {
    switch (_kind) {
      case ReportScopeKind.full:
        return const SizedBox.shrink();
      case ReportScopeKind.place:
        if (_places.isEmpty) {
          return const Text('No places yet.');
        }
        return DropdownButtonFormField<String>(
          initialValue: _placeId,
          decoration: const InputDecoration(labelText: 'Place'),
          items: [
            for (final place in _places)
              DropdownMenuItem(value: place.id, child: Text(place.name)),
          ],
          onChanged: (v) => setState(() => _placeId = v),
        );
      case ReportScopeKind.location:
        if (_locations.isEmpty) {
          return const Text('No locations yet.');
        }
        return DropdownButtonFormField<String>(
          initialValue: _locationId,
          decoration: const InputDecoration(labelText: 'Location'),
          items: [
            for (final location in _locations)
              DropdownMenuItem(
                value: location.id,
                child: Text(
                  _locationLabel(location),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _locationId = v),
        );
      case ReportScopeKind.category:
        if (_categories.isEmpty) {
          return const Text('No categories yet.');
        }
        return DropdownButtonFormField<String>(
          initialValue: _categoryId,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final category in _categories)
              DropdownMenuItem(value: category.id, child: Text(category.name)),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        );
      case ReportScopeKind.selected:
        if (_belongings.isEmpty) {
          return const Text('No items yet.');
        }
        return Column(
          children: [
            Text(
              '${_selectedIds.length} selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: _belongings.length,
                itemBuilder: (context, i) {
                  final item = _belongings[i];
                  final selected = _selectedIds.contains(item.id);
                  return CheckboxListTile(
                    title: Text(item.name, overflow: TextOverflow.ellipsis),
                    value: selected,
                    dense: true,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIds.add(item.id);
                      } else {
                        _selectedIds.remove(item.id);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        );
    }
  }

  Widget _reportSummary(InventoryReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Generated ${_dateFormat.format(report.generatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _summaryRow('Items', '${report.items.length}'),
            _summaryRow('Total known value', _totalValueLabel(report)),
            _summaryRow(
              'Items needing documentation',
              '${report.incompleteCount} item(s)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  /// Total known value grouped by currency — never converted.
  String _totalValueLabel(InventoryReport report) {
    final perCurrency = report.valueByCurrency;
    if (perCurrency.isEmpty) return '—';
    final parts = perCurrency.entries
        .map((e) => formatMoney(e.value, e.key))
        .toList();
    return parts.join(' + ');
  }

  Widget _exportButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _savePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Save PDF'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _sharePdf,
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share PDF'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _shareCsv,
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Share CSV'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _shareWebCompanion,
          icon: const Icon(Icons.web_outlined),
          label: const Text('Export Web HTML'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _exportEvidence,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Export evidence ZIP'),
        ),
      ],
    );
  }

  Widget _missingInfoSection(InventoryReport report) {
    if (report.missingInfo.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Every item in this report has complete documentation.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Missing information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap an item to see how to complete its documentation.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final entry in report.missingInfo)
              ExpansionTile(
                title: Text(
                  entry.belonging.name,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  entry.missing.map((m) => m.label).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                dense: true,
                children: [
                  for (final field in entry.missing)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline, size: 18),
                      title: Text(field.label),
                      subtitle: Text(field.suggestion),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
