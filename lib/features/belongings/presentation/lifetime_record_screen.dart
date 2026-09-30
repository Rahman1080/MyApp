import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utilities/money.dart';
import '../domain/item_lifetime_service.dart';

/// Phase 22 UI — Item Lifetime Record.
///
/// Shows the complete lifetime record of a single item in one place:
/// details, acquisition and disposition, full history timeline, purchase,
/// warranties, service records, warranty claims, and documents.
/// The record can be exported as JSON and shared.
class LifetimeRecordScreen extends StatefulWidget {
  const LifetimeRecordScreen({
    super.key,
    required this.lifetimeService,
    required this.belongingId,
  });

  static String routePathFor(String belongingId) =>
      '/belongings/$belongingId/lifetime';

  final ItemLifetimeService lifetimeService;
  final String belongingId;

  @override
  State<LifetimeRecordScreen> createState() => _LifetimeRecordScreenState();
}

class _LifetimeRecordScreenState extends State<LifetimeRecordScreen> {
  ItemLifetimeRecord? _record;
  bool _loading = true;
  bool _exporting = false;

  final _dateFormat = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final record =
          await widget.lifetimeService.getLifetimeRecord(widget.belongingId);
      if (!mounted) return;
      setState(() => _record = record);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json =
          await widget.lifetimeService.exportToJson(widget.belongingId);
      final dir = await getTemporaryDirectory();
      final name =
          _record?.belonging.name.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_') ??
              'item';
      final file = File('${dir.path}/lifetime-$name.json');
      await file.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Lifetime record for ${_record?.belonging.name}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lifetime Record'),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
            tooltip: 'Export as JSON',
            onPressed: _exporting || _record == null ? null : _export,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _record == null
              ? const Center(child: Text('Could not load lifetime record.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDetails(),
                    const SizedBox(height: 12),
                    _buildAcquisition(),
                    const SizedBox(height: 12),
                    _buildHistory(),
                    const SizedBox(height: 12),
                    _buildWarranties(),
                    const SizedBox(height: 12),
                    _buildServiceRecords(),
                    const SizedBox(height: 12),
                    _buildPurchase(),
                    const SizedBox(height: 12),
                    _buildDocuments(),
                  ],
                ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final b = _record!.belonging;
    return _section('Details', [
      _row('Name', b.name),
      if (b.brand != null && b.brand!.isNotEmpty)
        _row('Brand', b.brand!),
      if (b.model != null && b.model!.isNotEmpty) _row('Model', b.model!),
      if (b.serialNumber != null && b.serialNumber!.isNotEmpty)
        _row('Serial', b.serialNumber!),
      if (b.condition != null) _row('Condition', b.condition!),
      if (b.valueCents != null)
        _row(
          'Est. value',
          formatMoney(b.valueCents, b.currencyCode ?? 'USD'),
        ),
      if (b.notes != null && b.notes!.isNotEmpty) _row('Notes', b.notes!),
    ]);
  }

  Widget _buildAcquisition() {
    final b = _record!.belonging;
    return _section('Acquisition & Disposition', [
      if (b.acquisitionType != null) _row('Acquired via', b.acquisitionType!),
      if (b.acquisitionDate != null)
        _row('Acquired on', _dateFormat.format(b.acquisitionDate!)),
      if (b.dispositionDate != null)
        _row('Disposed on', _dateFormat.format(b.dispositionDate!)),
      if (b.dispositionMethod != null)
        _row('Disposition', b.dispositionMethod!),
      if (b.dispositionPriceCents != null)
        _row(
          'Disposition value',
          formatMoney(
            b.dispositionPriceCents,
            b.dispositionCurrencyCode ?? 'USD',
          ),
        ),
      if (b.acquisitionType == null && b.dispositionDate == null)
        const Text('No acquisition or disposition details recorded.'),
    ]);
  }

  Widget _buildHistory() {
    final history = _record!.history;
    return _section('History (${history.length})', [
      if (history.isEmpty)
        const Text('No history entries yet.')
      else
        ...history.take(20).map(
              (h) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 20),
                title: Text(h.title),
                subtitle: Text(_dateFormat.format(h.occurredAt)),
              ),
            ),
    ]);
  }

  Widget _buildWarranties() {
    final warranties = _record!.warranties;
    return _section('Warranties (${warranties.length})', [
      if (warranties.isEmpty)
        const Text('No warranties recorded.')
      else
        ...warranties.map(
              (w) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined, size: 20),
                title: Text(w.provider ?? 'Warranty'),
                subtitle: w.expirationDate != null
                    ? Text('Expires ${_dateFormat.format(w.expirationDate!)}')
                    : null,
              ),
            ),
    ]);
  }

  Widget _buildServiceRecords() {
    final records = _record!.serviceRecords;
    final claims = _record!.warrantyClaims;
    return _section(
      'Service & Claims (${records.length + claims.length})',
      [
        if (records.isEmpty && claims.isEmpty)
          const Text('No service records or claims.')
        else ...[
          ...records.map(
                (r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.build_outlined, size: 20),
                  title: Text(
                    '${r.serviceType}${r.provider != null ? ' — ${r.provider}' : ''}',
                  ),
                  subtitle: Text(_dateFormat.format(r.serviceDate)),
                ),
              ),
          ...claims.map(
                (c) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_outlined, size: 20),
                  title: Text('Claim: ${c.status}'),
                  subtitle: Text('Filed ${_dateFormat.format(c.claimDate)}'),
                ),
              ),
        ],
      ],
    );
  }

  Widget _buildPurchase() {
    final purchase = _record!.purchase;
    return _section('Purchase', [
      if (purchase == null)
        const Text('No purchase linked.')
      else ...[
        _row('Item', purchase.productName),
        _row('Store', purchase.store ?? '—'),
        if (purchase.purchaseDate != null)
          _row('Date', _dateFormat.format(purchase.purchaseDate!)),
        if (purchase.priceCents != null)
          _row(
            'Total',
            formatMoney(purchase.priceCents, purchase.currencyCode),
          ),
      ],
    ]);
  }

  Widget _buildDocuments() {
    final docs = _record!.documents;
    return _section('Documents (${docs.length})', [
      if (docs.isEmpty)
        const Text('No documents attached.')
      else
        ...docs.map(
              (d) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined, size: 20),
                title: Text(d.title),
              ),
            ),
    ]);
  }
}
