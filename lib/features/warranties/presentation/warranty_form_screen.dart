import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/document_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/warranty_repository.dart';
import '../../../core/database/tables.dart' show newRecordId;
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reminder_coordinator.dart';
import '../../documents/domain/document_service.dart';
import '../../../shared/services/warranty_service.dart';
import '../../documents/presentation/widgets/documents_section.dart';

enum _ExpiryMode { duration, exactDate }

/// Add/edit form for a warranty.
///
/// Expiry can be entered as a duration (years/months/days) or as an exact
/// date. Durations that fit whole months are stored in `durationMonths`;
/// anything else (including an explicit date) is stored as an explicit
/// `expirationDate` so no information is lost.
///
/// When an expiry is known, expiry reminders (30 days and 1 day before) are
/// scheduled with the notification permission flow: rationale first, OS
/// prompt only after an explicit "Allow".
class WarrantyFormScreen extends StatefulWidget {
  const WarrantyFormScreen({
    super.key,
    required this.warrantyRepository,
    required this.purchaseRepository,
    required this.documentRepository,
    required this.reminderCoordinator,
    required this.notificationService,
    this.warrantyId,
    this.initialPurchaseId,
  });

  final WarrantyRepository warrantyRepository;
  final PurchaseRepository purchaseRepository;
  final DocumentRepository documentRepository;
  final ReminderCoordinator reminderCoordinator;
  final NotificationService notificationService;

  /// Null for a new warranty, set when editing.
  final String? warrantyId;

  /// Pre-selects the purchase when opened from a purchase detail screen.
  final String? initialPurchaseId;

  @override
  State<WarrantyFormScreen> createState() => _WarrantyFormScreenState();
}

class _WarrantyFormScreenState extends State<WarrantyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _numberController = TextEditingController();
  final _notesController = TextEditingController();
  final _yearsController = TextEditingController(text: '0');
  final _monthsController = TextEditingController(text: '0');
  final _daysController = TextEditingController(text: '0');

  String? _purchaseId;
  DateTime? _startDate;
  _ExpiryMode _expiryMode = _ExpiryMode.duration;
  DateTime? _exactDate;

  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.warrantyId != null;

  @override
  void initState() {
    super.initState();
    _purchaseId = widget.initialPurchaseId;
    _load();
  }

  Future<void> _load() async {
    if (_isEditing) {
      final warranty =
          await widget.warrantyRepository.getById(widget.warrantyId!);
      if (warranty != null) {
        _purchaseId = warranty.purchaseId;
        _providerController.text = warranty.provider ?? '';
        _numberController.text = warranty.warrantyNumber ?? '';
        _notesController.text = warranty.notes ?? '';
        _startDate = warranty.startDate;
        if (warranty.expirationDate != null) {
          _expiryMode = _ExpiryMode.exactDate;
          _exactDate = warranty.expirationDate;
        } else {
          _expiryMode = _ExpiryMode.duration;
          final months = warranty.durationMonths ?? 0;
          _yearsController.text = (months ~/ 12).toString();
          _monthsController.text = (months % 12).toString();
        }
      }
    } else if (_purchaseId != null) {
      final purchase =
          await widget.purchaseRepository.getById(_purchaseId!);
      _startDate = purchase?.purchaseDate;
    }
    _startDate ??= DateTime.now();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _providerController.dispose();
    _numberController.dispose();
    _notesController.dispose();
    _yearsController.dispose();
    _monthsController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  int _intOf(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  /// Computes the expiry date from the form, or null when the inputs are
  /// invalid (the form validator rejects those cases).
  DateTime? _computeExpiry() {
    final start = _startDate;
    if (start == null) return null;
    if (_expiryMode == _ExpiryMode.exactDate) return _exactDate;
    final years = _intOf(_yearsController);
    final months = _intOf(_monthsController);
    final days = _intOf(_daysController);
    if (years <= 0 && months <= 0 && days <= 0) return null;
    return addWarrantyDuration(
      start,
      WarrantyDuration(days: days, months: months, years: years),
    );
  }

  String? _validateDuration(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return 'Must be 0 or more';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_purchaseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a purchase for this warranty.')),
      );
      return;
    }
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a warranty start date.')),
      );
      return;
    }
    final expiry = _computeExpiry();
    if (expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a duration of at least one day or an expiry date.'),
        ),
      );
      return;
    }
    if (_expiryMode == _ExpiryMode.exactDate &&
        _exactDate!.isBefore(
          DateTime(_startDate!.year, _startDate!.month, _startDate!.day),
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expiry date must be after the start date.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final warrantyId = _isEditing ? widget.warrantyId! : newRecordId();

      // Only durations that are whole months fit `durationMonths`; anything
      // else (or an explicit date) is stored as an explicit expirationDate.
      final years = _intOf(_yearsController);
      final months = _intOf(_monthsController);
      final days = _intOf(_daysController);
      final isWholeMonths =
          _expiryMode == _ExpiryMode.duration && days == 0;
      final companion = WarrantiesCompanion(
        id: _isEditing ? const drift.Value.absent() : drift.Value(warrantyId),
        purchaseId: drift.Value(_purchaseId!),
        provider: drift.Value(
          _providerController.text.trim().isEmpty
              ? null
              : _providerController.text.trim(),
        ),
        warrantyNumber: drift.Value(
          _numberController.text.trim().isEmpty
              ? null
              : _numberController.text.trim(),
        ),
        startDate: drift.Value(_startDate),
        expirationDate:
            drift.Value(isWholeMonths ? null : expiry),
        durationMonths: drift.Value(
          isWholeMonths ? years * 12 + months : null,
        ),
        notes: drift.Value(
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      );
      if (_isEditing) {
        await widget.warrantyRepository.update(widget.warrantyId!, companion);
      } else {
        await widget.warrantyRepository.create(companion);
      }

      // Expiry reminders: 30 days and 1 day before. Permission is requested
      // with KeepIt's own rationale first.
      final purchase =
          await widget.purchaseRepository.getById(_purchaseId!);
      if (!mounted) return;
      final offsets = [
        const Duration(days: 30),
        const Duration(days: 1),
      ];
      var schedule = false;
      if (expiry.isAfter(DateTime.now())) {
        schedule =
            await widget.notificationService.requestPermissions(context);
      }
      await widget.reminderCoordinator.resyncEntity(
        entityType: 'warranty',
        entityId: warrantyId,
        title: 'Warranty expiring: ${purchase?.productName ?? 'item'}',
        dueDate: expiry,
        offsets: schedule ? offsets : const [],
        notes: _providerController.text.trim().isEmpty
            ? null
            : _providerController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Warranty updated.' : 'Warranty saved.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit warranty' : 'New warranty'),
        actions: [
          if (_loaded)
            TextButton(
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
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FutureBuilder<List<Purchase>>(
                    future: widget.purchaseRepository.getAll(),
                    builder: (context, snapshot) {
                      final purchases = snapshot.data ?? const <Purchase>[];
                      return DropdownButtonFormField<String>(
                        initialValue: _purchaseId,
                        decoration: const InputDecoration(
                          labelText: 'Purchase',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final purchase in purchases)
                            DropdownMenuItem(
                              value: purchase.id,
                              child: Text(
                                purchase.productName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _isEditing
                            ? null
                            : (value) =>
                                setState(() => _purchaseId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _providerController,
                    decoration: const InputDecoration(
                      labelText: 'Provider (optional)',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _numberController,
                    decoration: const InputDecoration(
                      labelText: 'Warranty number (optional)',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  _DateRow(
                    label: 'Start date',
                    value: _startDate == null
                        ? 'Pick a date'
                        : DateFormat.yMMMd().format(_startDate!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<_ExpiryMode>(
                    segments: const [
                      ButtonSegment(
                        value: _ExpiryMode.duration,
                        label: Text('Duration'),
                        icon: Icon(Icons.timer_outlined),
                      ),
                      ButtonSegment(
                        value: _ExpiryMode.exactDate,
                        label: Text('Exact date'),
                        icon: Icon(Icons.event_outlined),
                      ),
                    ],
                    selected: {_expiryMode},
                    onSelectionChanged: (selection) =>
                        setState(() => _expiryMode = selection.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  if (_expiryMode == _ExpiryMode.duration)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _yearsController,
                            decoration: const InputDecoration(
                              labelText: 'Years',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validateDuration,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _monthsController,
                            decoration: const InputDecoration(
                              labelText: 'Months',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validateDuration,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _daysController,
                            decoration: const InputDecoration(
                              labelText: 'Days',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validateDuration,
                          ),
                        ),
                      ],
                    )
                  else
                    _DateRow(
                      label: 'Expiry date',
                      value: _exactDate == null
                          ? 'Pick a date'
                          : DateFormat.yMMMd().format(_exactDate!),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _exactDate ??
                              DateTime.now().add(
                                const Duration(days: 365),
                              ),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _exactDate = picked);
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  if (_purchaseId != null)
                    DocumentsSection(
                      purchaseId: _purchaseId!,
                      documentService: DocumentService(
                        documentRepository: widget.documentRepository,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Expiry reminders (30 days and 1 day before) are '
                    'scheduled on this device. Notification permission is '
                    'asked when you save.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(value),
      ),
    );
  }
}
