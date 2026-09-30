import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/document_repository.dart';
import '../../../core/database/repositories/product_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/refund_repository.dart';
import '../../../core/database/repositories/reminder_repository.dart';
import '../../../core/database/repositories/return_deadline_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reminder_coordinator.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/services/return_deadline_service.dart';
import '../../../shared/services/warranty_service.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../documents/domain/document_service.dart';
import '../../documents/presentation/widgets/documents_section.dart';
import '../../receipts/presentation/widgets/receipt_section.dart';
import 'purchase_form_screen.dart';
import 'widgets/refund_dialog.dart';
import 'widgets/return_window_dialog.dart';

/// Full detail view for one purchase: fields, line items, warranty and
/// return-deadline management, refund actions, receipt and document
/// attachments.
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({
    super.key,
    required this.purchaseId,
    required this.database,
    required this.purchaseRepository,
    required this.productRepository,
    required this.warrantyRepository,
    required this.returnDeadlineRepository,
    required this.refundRepository,
    required this.reminderRepository,
    required this.reminderCoordinator,
    required this.notificationService,
    this.onEdit,
    this.onDeleted,
  });

  static String routePathFor(String id) => '/purchases/$id';

  final String purchaseId;
  final KeepItDatabase database;
  final PurchaseRepository purchaseRepository;
  final ProductRepository productRepository;
  final WarrantyRepository warrantyRepository;
  final ReturnDeadlineRepository returnDeadlineRepository;
  final RefundRepository refundRepository;
  final ReminderRepository reminderRepository;
  final ReminderCoordinator reminderCoordinator;
  final NotificationService notificationService;

  /// Defaults to pushing the edit route.
  final VoidCallback? onEdit;

  /// Called after a successful delete. Defaults to popping the screen.
  final VoidCallback? onDeleted;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _DetailData {
  _DetailData({
    required this.purchase,
    required this.products,
    required this.warranty,
    required this.returnDeadline,
    required this.refund,
  });

  final Purchase purchase;
  final List<Product> products;
  final Warranty? warranty;
  final ReturnDeadline? returnDeadline;
  final Refund? refund;
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  late Future<_DetailData?> _dataFuture = _load();

  Future<_DetailData?> _load() async {
    final purchase =
        await widget.purchaseRepository.getById(widget.purchaseId);
    if (purchase == null) return null;
    final results = await Future.wait([
      widget.productRepository.getByPurchase(purchase.id),
      widget.warrantyRepository.getByPurchaseId(purchase.id),
      widget.returnDeadlineRepository.getByPurchaseId(purchase.id),
      widget.refundRepository.getByPurchaseId(purchase.id),
    ]);
    return _DetailData(
      purchase: purchase,
      products: results[0] as List<Product>,
      warranty: results[1] as Warranty?,
      returnDeadline: results[2] as ReturnDeadline?,
      refund: results[3] as Refund?,
    );
  }

  void _refresh() => setState(() => _dataFuture = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit purchase',
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete purchase',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: FutureBuilder<_DetailData?>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(
              child: Text('Purchase not found. It may have been deleted.'),
            );
          }
          return _body(context, data);
        },
      ),
    );
  }

  Future<void> _edit() async {
    if (widget.onEdit != null) {
      widget.onEdit!();
    } else {
      await context.push(
        PurchaseFormScreen.editRoutePathFor(widget.purchaseId),
      );
    }
    _refresh();
  }

  Future<void> _confirmDelete() async {
    final data = await _dataFuture;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete purchase?'),
        content: Text(
          '“${data?.purchase.productName}” and its linked products, receipt, '
          'warranty, return deadline and refund will be permanently deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.purchaseRepository.delete(widget.purchaseId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Purchase deleted')),
    );
    if (widget.onDeleted != null) {
      widget.onDeleted!();
    } else {
      context.pop();
    }
  }

  Widget _body(BuildContext context, _DetailData data) {
    final p = data.purchase;
    final theme = Theme.of(context);
    final date = p.purchaseDate;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(theme, p, date),
        const SizedBox(height: 16),
        _detailsCard(theme, p, date),
        if (data.products.isNotEmpty) ...[
          const SizedBox(height: 16),
          _productsCard(theme, data.products),
        ],
        const SizedBox(height: 16),
        _warrantyCard(theme, data),
        const SizedBox(height: 16),
        _returnCard(theme, data),
        const SizedBox(height: 16),
        _refundSection(theme, data),
        const SizedBox(height: 16),
        ReceiptSection(
          purchaseId: data.purchase.id,
          database: widget.database,
          currencyCode: data.purchase.currencyCode,
          onAddReceipt: () => context.push(
            '/scan?purchaseId=${Uri.encodeComponent(data.purchase.id)}',
          ),
        ),
        const SizedBox(height: 16),
        DocumentsSection(
          purchaseId: data.purchase.id,
          documentService: DocumentService(
            documentRepository: DocumentRepository(widget.database),
          ),
        ),
      ],
    );
  }

  Widget _header(ThemeData theme, Purchase p, DateTime? date) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                p.productName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            StatusBadge(status: p.status),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          formatMoney(p.priceCents, p.currencyCode),
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            if ((p.store ?? '').isNotEmpty) p.store!,
            if (date != null) DateFormat.yMMMd().format(date),
          ].join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _detailsCard(ThemeData theme, Purchase p, DateTime? date) {
    return Card(
      child: Column(
        children: [
          if ((p.brand ?? '').isNotEmpty)
            _row(theme, 'Brand', p.brand!),
          _row(theme, 'Quantity', '${p.quantity}'),
          if ((p.paymentMethod ?? '').isNotEmpty)
            _row(theme, 'Paid with', p.paymentMethod!),
          _row(theme, 'Currency', p.currencyCode),
          if ((p.notes ?? '').isNotEmpty)
            _row(theme, 'Notes', p.notes!, multiline: true),
          _row(
            theme,
            'Added',
            DateFormat.yMMMd().add_jm().format(p.createdAt),
          ),
        ],
      ),
    );
  }

  Widget _productsCard(ThemeData theme, List<Product> products) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Items', style: theme.textTheme.titleMedium),
          ),
          for (var i = 0; i < products.length; i++) ...[
            ListTile(
              dense: true,
              title: Text(products[i].name),
              subtitle: products[i].quantity > 1
                  ? Text('Qty ${products[i].quantity}')
                  : null,
              trailing: Text(
                formatMoney(products[i].priceCents, 'USD'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (i < products.length - 1) const Divider(height: 1, indent: 16),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _warrantyCard(ThemeData theme, _DetailData data) {
    final warranty = data.warranty;
    if (warranty == null) {
      return OutlinedButton.icon(
        onPressed: () async {
          await context.push(
            '/purchases/warranties/new'
            '?purchaseId=${Uri.encodeComponent(data.purchase.id)}',
          );
          _refresh();
        },
        icon: const Icon(Icons.verified_outlined),
        label: const Text('Add warranty'),
      );
    }

    final now = DateTime.now();
    final expiry = warrantyExpiryDate(
      startDate: warranty.startDate,
      durationMonths: warranty.durationMonths,
      expirationDate: warranty.expirationDate,
    );
    final status =
        expiry == null ? null : warrantyStatus(expiry: expiry, now: now);
    final daysLeft =
        expiry == null ? null : warrantyDaysRemaining(expiry, now);

    final (String label, Color color) = switch (status) {
      WarrantyStatus.active => ('Active', const Color(0xFF1B7A4D)),
      WarrantyStatus.expiringSoon => ('Expiring soon', const Color(0xFFB25E09)),
      WarrantyStatus.expired => ('Expired', theme.colorScheme.error),
      null => ('No expiry date', theme.colorScheme.onSurfaceVariant),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Warranty', style: theme.textTheme.titleMedium),
                const Spacer(),
                _pill(theme, label, color),
              ],
            ),
            const SizedBox(height: 12),
            if ((warranty.provider ?? '').isNotEmpty)
              _kv(theme, 'Provider', warranty.provider!),
            if (expiry != null) ...[
              _kv(theme, 'Expires', DateFormat.yMMMd().format(expiry)),
              _kv(
                theme,
                'Coverage left',
                daysLeft! < 0
                    ? 'Expired ${-daysLeft} days ago'
                    : daysLeft == 0
                        ? 'Last day today'
                        : '$daysLeft days',
              ),
            ],
            if ((warranty.notes ?? '').isNotEmpty)
              _kv(theme, 'Notes', warranty.notes!),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await context.push(
                    '/purchases/warranties/${warranty.id}/edit',
                  );
                  _refresh();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Manage'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _returnCard(ThemeData theme, _DetailData data) {
    final deadline = data.returnDeadline;
    if (deadline == null) {
      return OutlinedButton.icon(
        onPressed: () => _editReturnWindow(data, null),
        icon: const Icon(Icons.assignment_return_outlined),
        label: const Text('Set return window'),
      );
    }

    final now = DateTime.now();
    final daysLeft = returnDaysLeft(deadline.deadlineDate, now);
    final overdue = isReturnOverdue(deadline.deadlineDate, now);
    final color = overdue
        ? theme.colorScheme.error
        : daysLeft <= 7
            ? const Color(0xFFB25E09)
            : const Color(0xFF1B7A4D);
    final label = overdue
        ? 'Overdue by ${-daysLeft} days'
        : daysLeft == 0
            ? 'Last day today'
            : '$daysLeft days left';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_return_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Return deadline', style: theme.textTheme.titleMedium),
                const Spacer(),
                _pill(theme, label, color),
              ],
            ),
            const SizedBox(height: 12),
            _kv(
              theme,
              'Return by',
              DateFormat.yMMMd().format(deadline.deadlineDate),
            ),
            if ((deadline.notes ?? '').isNotEmpty)
              _kv(theme, 'Notes', deadline.notes!),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editReturnWindow(data, deadline),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _markReturned(data),
                  icon: const Icon(Icons.keyboard_return),
                  label: const Text('Mark returned'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editReturnWindow(
    _DetailData data,
    ReturnDeadline? existing,
  ) async {
    final saved = await ReturnWindowDialog.show(
      context,
      purchase: data.purchase,
      existing: existing,
      returnDeadlineRepository: widget.returnDeadlineRepository,
      reminderCoordinator: widget.reminderCoordinator,
      notificationService: widget.notificationService,
    );
    if (saved == true) _refresh();
  }

  Future<void> _markReturned(_DetailData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as returned?'),
        content: Text(
          '“${data.purchase.productName}” will be marked returned and its '
          'return deadline and reminders removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark returned'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deadline = data.returnDeadline;
    if (deadline != null) {
      await widget.reminderCoordinator.clearEntity(
        entityType: 'return_deadline',
        entityId: deadline.id,
      );
      await widget.returnDeadlineRepository.delete(deadline.id);
    }
    await widget.purchaseRepository.update(
      data.purchase.id,
      const PurchasesCompanion(status: drift.Value('returned')),
    );
    _refresh();
  }

  Widget _refundSection(ThemeData theme, _DetailData data) {
    final refund = data.refund;
    if (refund == null) {
      return OutlinedButton.icon(
        onPressed: () => _editRefund(data, null),
        icon: const Icon(Icons.savings_outlined),
        label: const Text('Mark refunded'),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Refund', style: theme.textTheme.titleMedium),
                const Spacer(),
                StatusBadge(status: refund.status),
              ],
            ),
            const SizedBox(height: 12),
            if (refund.amountCents != null)
              _kv(
                theme,
                'Amount',
                formatMoney(refund.amountCents, 'USD'),
              ),
            if (refund.expectedDate != null)
              _kv(
                theme,
                'Expected',
                DateFormat.yMMMd().format(refund.expectedDate!),
              ),
            if ((refund.notes ?? '').isNotEmpty)
              _kv(theme, 'Notes', refund.notes!),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _editRefund(data, refund),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRefund(_DetailData data, Refund? existing) async {
    final saved = await RefundDialog.show(
      context,
      purchase: data.purchase,
      existing: existing,
      refundRepository: widget.refundRepository,
      purchaseRepository: widget.purchaseRepository,
    );
    if (saved == true) _refresh();
  }

  Widget _row(ThemeData theme, String label, String value,
      {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
