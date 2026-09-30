import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/keepit_database.dart';
import '../../../../core/database/repositories/receipt_repository.dart';
import '../../../../core/utilities/money.dart';
import '../../../../shared/services/file_storage.dart';

/// Receipt card on the purchase detail screen.
///
/// Shows the linked receipt (thumbnail, store, date, total) with full-image
/// view and delete, or an "Add receipt" button when there is none.
/// Deleting removes both the database row and the stored image file.
class ReceiptSection extends StatefulWidget {
  const ReceiptSection({
    super.key,
    required this.purchaseId,
    required this.database,
    required this.currencyCode,
    required this.onAddReceipt,
  });

  final String purchaseId;
  final KeepItDatabase database;
  final String currencyCode;
  final VoidCallback onAddReceipt;

  @override
  State<ReceiptSection> createState() => _ReceiptSectionState();
}

class _ReceiptSectionState extends State<ReceiptSection> {
  late final ReceiptRepository _receipts = ReceiptRepository(widget.database);
  late final FileStorage _storage = FileStorage();
  Receipt? _receipt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final receipt = await _receipts.getByPurchaseId(widget.purchaseId);
    if (mounted) {
      setState(() {
        _receipt = receipt;
        _loading = false;
      });
    }
  }

  Future<void> _delete() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: const Text(
          'The receipt and its photo will be removed. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _receipts.delete(receipt.id);
    await _storage.deleteFile(receipt.imagePath);
    if (mounted) {
      setState(() => _receipt = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt deleted.')),
      );
    }
  }

  void _viewFullImage() {
    final path = _receipt?.imagePath;
    if (path == null) return;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Receipt'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  File(path),
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('The receipt image file is missing.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Receipt', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (_receipt != null)
                  IconButton(
                    tooltip: 'Delete receipt',
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_receipt == null)
              OutlinedButton.icon(
                key: const Key('addReceiptButton'),
                onPressed: widget.onAddReceipt,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan receipt'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
              )
            else
              _receiptCard(context, theme, _receipt!),
          ],
        ),
      ),
    );
  }

  Widget _receiptCard(BuildContext context, ThemeData theme, Receipt receipt) {
    final path = receipt.imagePath;
    return InkWell(
      key: const Key('receiptCard'),
      onTap: _viewFullImage,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: path != null
                ? Image.file(
                    File(path),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _thumbFallback(theme),
                  )
                : _thumbFallback(theme),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.store ?? 'Receipt',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (receipt.receiptDate != null)
                      DateFormat.yMMMd().format(receipt.receiptDate!),
                    formatMoney(receipt.totalCents, widget.currencyCode),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _thumbFallback(ThemeData theme) {
    return Container(
      width: 72,
      height: 72,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.receipt_long_outlined),
    );
  }
}
