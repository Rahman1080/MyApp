import 'package:drift/drift.dart' hide isNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/tables.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/services/duplicate_detector.dart';
import 'purchase_detail_screen.dart';
import 'widgets/duplicate_dialog.dart';

/// Add / edit purchase form.
///
/// On save, [DuplicateDetector] runs first: when candidates are found the
/// "Possible duplicate" dialog offers "View existing" or "Create anyway".
/// The app never merges or deletes automatically.
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({
    super.key,
    required this.purchaseRepository,
    required this.database,
    this.purchaseId,
    this.onSaved,
    this.onViewPurchase,
  });

  static const String newRoutePath = '/purchases/new';
  static String editRoutePathFor(String id) => '/purchases/$id/edit';

  final PurchaseRepository purchaseRepository;
  final KeepItDatabase database;

  /// null → creating a new purchase.
  final String? purchaseId;

  /// Called after a successful save. Defaults to popping the form.
  final VoidCallback? onSaved;

  /// Called with an existing purchase id from the duplicate dialog.
  /// Defaults to replacing the form with that purchase's detail screen.
  final void Function(String purchaseId)? onViewPurchase;

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _storeController = TextEditingController();
  final _priceController = TextEditingController();
  final _paymentController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _purchaseDate;
  String _currencyCode = 'USD';
  int _quantity = 1;
  String _status = 'active';
  bool _loading = true;
  bool _saving = false;
  Purchase? _existing;

  static const List<String> _statuses = [
    'active',
    'returned',
    'refunded',
    'exchanged',
  ];

  bool get _isEditing => widget.purchaseId != null;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (!_isEditing) {
      _purchaseDate = DateTime.now();
      setState(() => _loading = false);
      return;
    }
    final purchase =
        await widget.purchaseRepository.getById(widget.purchaseId!);
    if (!mounted) return;
    if (purchase == null) {
      setState(() => _loading = false);
      return;
    }
    _existing = purchase;
    _nameController.text = purchase.productName;
    _brandController.text = purchase.brand ?? '';
    _storeController.text = purchase.store ?? '';
    _priceController.text = centsToDecimalString(purchase.priceCents);
    _paymentController.text = purchase.paymentMethod ?? '';
    _notesController.text = purchase.notes ?? '';
    _purchaseDate = purchase.purchaseDate;
    _currencyCode = purchase.currencyCode;
    _quantity = purchase.quantity;
    _status = purchase.status;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _storeController.dispose();
    _priceController.dispose();
    _paymentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit purchase' : 'Add purchase'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _existing == null && _isEditing
              ? const Center(child: Text('Purchase not found.'))
              : _form(),
    );
  }

  Widget _form() {
    // SingleChildScrollView + Column (not ListView): every field stays
    // mounted while scrolling so Form.validate() never silently skips an
    // off-screen field.
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'What did you buy? *',
              hintText: 'e.g. Air fryer',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Give your purchase a name';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _brandController,
            decoration: const InputDecoration(
              labelText: 'Brand',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _storeController,
            decoration: const InputDecoration(
              labelText: 'Store',
              hintText: 'e.g. Walmart',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
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
                    if (value == null || value.trim().isEmpty) return null;
                    try {
                      parseMoneyToCents(value);
                    } catch (_) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _currencyCode,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final code in commonCurrencies)
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _currencyCode = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dateField(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quantityField(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _paymentController,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              hintText: 'e.g. Visa ·· 4242',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final status in _statuses)
                DropdownMenuItem(
                  value: status,
                  child: Text(_statusLabel(status)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('savePurchaseButton'),
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? 'Save changes' : 'Add purchase'),
          ),
          ],
        ),
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Purchase date',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          _purchaseDate == null
              ? 'No date'
              : DateFormat.yMMMd().format(_purchaseDate!),
        ),
      ),
    );
  }

  Widget _quantityField() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Decrease quantity',
          onPressed: _quantity > 1
              ? () => setState(() => _quantity--)
              : null,
        ),
        Expanded(
          child: Text(
            '$_quantity',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
            semanticsLabel: 'Quantity $_quantity',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Increase quantity',
          onPressed: () => setState(() => _quantity++),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final purchase = _buildPurchase();
      final candidates =
          await DuplicateDetector(widget.database).findCandidates(purchase);
      if (!mounted) return;
      if (candidates.isNotEmpty) {
        setState(() => _saving = false);
        _showDuplicateDialog(purchase, candidates);
        return;
      }
      await _persist(purchase);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Purchase _buildPurchase() {
    final now = DateTime.now();
    int? priceCents;
    try {
      priceCents = parseMoneyToCents(_priceController.text);
    } catch (_) {
      priceCents = null;
    }
    String? text(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    return Purchase(
      id: _existing?.id ?? newRecordId(),
      productName: _nameController.text.trim(),
      brand: text(_brandController),
      store: text(_storeController),
      purchaseDate: _purchaseDate,
      priceCents: priceCents,
      currencyCode: _currencyCode,
      quantity: _quantity,
      paymentMethod: text(_paymentController),
      notes: text(_notesController),
      status: _status,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  void _showDuplicateDialog(
    Purchase purchase,
    List<DuplicateCandidate> candidates,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => DuplicateDialog(
        candidates: candidates,
        onViewExisting: (id) {
          Navigator.of(dialogContext).pop();
          if (widget.onViewPurchase != null) {
            widget.onViewPurchase!(id);
          } else {
            // Leave the form and open the existing purchase instead.
            context.pop();
            context.push(PurchaseDetailScreen.routePathFor(id));
          }
        },
        onCreateAnyway: () {
          Navigator.of(dialogContext).pop();
          _persist(purchase);
        },
      ),
    );
  }

  Future<void> _persist(Purchase purchase) async {
    setState(() => _saving = true);
    try {
      final companion = PurchasesCompanion(
        id: Value(purchase.id),
        productName: Value(purchase.productName),
        brand: Value(purchase.brand),
        store: Value(purchase.store),
        purchaseDate: Value(purchase.purchaseDate),
        priceCents: Value(purchase.priceCents),
        currencyCode: Value(purchase.currencyCode),
        quantity: Value(purchase.quantity),
        paymentMethod: Value(purchase.paymentMethod),
        notes: Value(purchase.notes),
        status: Value(purchase.status),
        createdAt: Value(purchase.createdAt),
        updatedAt: Value(purchase.updatedAt),
      );
      if (_isEditing) {
        await widget.purchaseRepository.update(purchase.id, companion);
      } else {
        await widget.purchaseRepository.create(companion);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Purchase updated' : 'Purchase added',
          ),
        ),
      );
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'returned':
        return 'Returned';
      case 'refunded':
        return 'Refunded';
      case 'exchanged':
        return 'Exchanged';
      default:
        return status;
    }
  }
}
