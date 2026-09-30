import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utilities/money.dart';
import '../../domain/receipt_text_parser.dart';

/// Confirmation form shown after OCR completes.
///
/// The recognized text and the heuristic parse are displayed for review;
/// every field is editable. The user must tap Confirm (or Discard) — nothing
/// is ever saved from OCR output without explicit confirmation.
class ReceiptConfirmForm extends StatefulWidget {
  const ReceiptConfirmForm({
    super.key,
    required this.image,
    required this.rawText,
    required this.parsed,
    required this.onConfirm,
    required this.onDiscard,
  });

  final File image;
  final String rawText;
  final ParsedReceipt parsed;

  /// Called with the user-reviewed values when Confirm is tapped.
  final void Function({
    required String? store,
    required DateTime? date,
    required int? totalCents,
    required int? subtotalCents,
    required int? taxCents,
  }) onConfirm;

  final VoidCallback onDiscard;

  @override
  State<ReceiptConfirmForm> createState() => _ReceiptConfirmFormState();
}

class _ReceiptConfirmFormState extends State<ReceiptConfirmForm> {
  late final TextEditingController _storeController =
      TextEditingController(text: widget.parsed.store ?? '');
  late final TextEditingController _totalController = TextEditingController(
    text: centsToDecimalString(widget.parsed.totalCents),
  );
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.parsed.date;
  }

  @override
  void dispose() {
    _storeController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  String get _dateLabel => _date == null
      ? 'No date found'
      : DateFormat.yMMMd().format(_date!);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(1990),
      lastDate: now,
      helpText: 'Receipt date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _confirm() {
    int? totalCents;
    try {
      totalCents = parseMoneyToCents(_totalController.text);
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That total doesn\'t look like an amount.'),
        ),
      );
      return;
    }
    final store = _storeController.text.trim();
    setState(() => _saving = true);
    widget.onConfirm(
      store: store.isEmpty ? null : store,
      date: _date,
      totalCents: totalCents,
      subtotalCents: widget.parsed.subtotalCents,
      taxCents: widget.parsed.taxCents,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              widget.image,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check the details — edit anything the scan got wrong.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _storeController,
            decoration: const InputDecoration(
              labelText: 'Store',
              hintText: 'Where did you buy it?',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('receiptDateButton'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_dateLabel),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              if (_date != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear date',
                  onPressed: () => setState(() => _date = null),
                  icon: const Icon(Icons.clear),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _totalController,
            decoration: const InputDecoration(
              labelText: 'Total',
              hintText: '0.00',
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          if (widget.rawText.trim().isNotEmpty)
            ExpansionTile(
              title: const Text('What the scan read'),
              subtitle: const Text('Raw text — for transparency only'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SelectableText(
                    widget.rawText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('confirmReceiptButton'),
            onPressed: _saving ? null : _confirm,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'Confirm receipt'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 56),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('discardReceiptButton'),
            onPressed: _saving ? null : widget.onDiscard,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 56),
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}
