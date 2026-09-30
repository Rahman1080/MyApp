import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/keepit_database.dart';
import '../../../../core/database/repositories/purchase_repository.dart';
import '../../../../core/database/repositories/refund_repository.dart';
import '../../../../core/database/tables.dart' show newRecordId;

/// Refund statuses stored on [Refund.status].
const Map<String, String> kRefundStatuses = {
  'pending': 'Pending',
  'received': 'Received',
};

/// Dialog to record (or edit) a refund for a purchase.
///
/// Saving creates/updates the [Refund] row and moves the purchase to the
/// `refunded` status. Returns true when saved.
class RefundDialog extends StatefulWidget {
  const RefundDialog({
    super.key,
    required this.purchase,
    required this.existing,
    required this.refundRepository,
    required this.purchaseRepository,
  });

  final Purchase purchase;
  final Refund? existing;
  final RefundRepository refundRepository;
  final PurchaseRepository purchaseRepository;

  static Future<bool?> show(
    BuildContext context, {
    required Purchase purchase,
    required Refund? existing,
    required RefundRepository refundRepository,
    required PurchaseRepository purchaseRepository,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => RefundDialog(
        purchase: purchase,
        existing: existing,
        refundRepository: refundRepository,
        purchaseRepository: purchaseRepository,
      ),
    );
  }

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _requestDate;
  String _status = 'pending';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      if (existing.amountCents != null) {
        _amountController.text =
            (existing.amountCents! / 100).toStringAsFixed(2);
      }
      _notesController.text = existing.notes ?? '';
      _requestDate = existing.requestDate;
      if (kRefundStatuses.containsKey(existing.status)) {
        _status = existing.status;
      }
    } else {
      _amountController.text =
          ((widget.purchase.priceCents ?? 0) / 100).toStringAsFixed(2);
      _requestDate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int? _amountCents() {
    final parsed = double.tryParse(_amountController.text.trim());
    if (parsed == null || parsed < 0) return null;
    return (parsed * 100).round();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final id = existing?.id ?? newRecordId();
      final companion = RefundsCompanion(
        id: existing == null
            ? drift.Value(id)
            : const drift.Value.absent(),
        purchaseId: drift.Value(widget.purchase.id),
        amountCents: drift.Value(_amountCents()),
        status: drift.Value(_status),
        requestDate: drift.Value(
          _requestDate == null
              ? null
              : DateTime(
                  _requestDate!.year,
                  _requestDate!.month,
                  _requestDate!.day,
                ),
        ),
        notes: drift.Value(
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      );
      if (existing == null) {
        await widget.refundRepository.create(companion);
      } else {
        await widget.refundRepository.update(existing.id, companion);
      }
      await widget.purchaseRepository.update(
        widget.purchase.id,
        PurchasesCompanion(status: const drift.Value('refunded')),
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record refund'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount (${widget.purchase.currencyCode})',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}'),
                  ),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter the refund amount.';
                  }
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed < 0) {
                    return 'Enter a valid amount.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _requestDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _requestDate = picked);
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Refund date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _requestDate == null
                        ? 'Pick a date'
                        : DateFormat.yMMMd().format(_requestDate!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry in kRefundStatuses.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? 'pending'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
