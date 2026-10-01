import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/belonging_meta.dart';
import '../../../core/database/keepit_database.dart';
import '../../../core/database/tables.dart' show newRecordId;
import '../../../core/database/repositories/belonging_history_repository.dart';
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/purchase_repository.dart';
import '../../../core/database/repositories/tag_repository.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/services/file_storage.dart';
import '../../../shared/widgets/tag_editor.dart';
import 'widgets/location_path.dart';

/// Add/edit form for a belonging. Name is required; everything else is
/// optional: brand, model, serial number, category, hierarchical location,
/// quantity, condition, estimated value (+ "value unknown"), notes, photo,
/// tags, and an optional link to the purchase the item came from.
class BelongingFormScreen extends StatefulWidget {
  const BelongingFormScreen({
    super.key,
    required this.belongingRepository,
    required this.categoryRepository,
    required this.locationRepository,
    required this.purchaseRepository,
    required this.tagRepository,
    required this.historyRepository,
    this.permissionService = const PermissionService(),
    this.fileStorage,
    this.imagePicker,
    this.belongingId,
    this.onSaved,
    this.initialLocationId,
    this.initialIsContainer = false,
  });

  final BelongingRepository belongingRepository;
  final CategoryRepository categoryRepository;
  final LocationRepository locationRepository;
  final PurchaseRepository purchaseRepository;
  final TagRepository tagRepository;
  final BelongingHistoryRepository historyRepository;
  final PermissionService permissionService;
  final FileStorage? fileStorage;
  final ImagePicker? imagePicker;

  /// Null for a new belonging, set when editing.
  final String? belongingId;

  /// Called after a successful save. Defaults to popping the form.
  final VoidCallback? onSaved;

  /// Pre-selected location for "add here" flows.
  final String? initialLocationId;

  /// Pre-checked container toggle for "new box" flows.
  final bool initialIsContainer;

  @override
  State<BelongingFormScreen> createState() => _BelongingFormScreenState();
}

class _BelongingFormScreenState extends State<BelongingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  final _notesController = TextEditingController();
  final _valueController = TextEditingController();

  String? _categoryId;
  String? _locationId;
  bool _isContainer = false;
  String? _purchaseId;
  String? _purchaseName;
  String? _condition;
  int _quantity = 1;
  String _currencyCode = 'USD';
  bool _valueUnknown = false;
  String? _photoPath; // persisted path of the current photo, if any
  File? _pendingPhoto; // newly picked, not yet persisted

  /// Tag names chosen before the belonging exists; linked after creation.
  final List<String> _pendingTags = [];

  bool _loaded = false;
  bool _saving = false;
  late Future<List<Category>> _categoriesFuture;

  bool get _isEditing => widget.belongingId != null;

  FileStorage get _fileStorage => widget.fileStorage ?? FileStorage();
  ImagePicker get _imagePicker => widget.imagePicker ?? ImagePicker();

  @override
  void initState() {
    super.initState();
    _currencyCode = defaultCurrencyCode();
    _categoriesFuture = widget.categoryRepository.getAll();
    _load();
  }

  /// Opens a small dialog to create a custom category, then selects it.
  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g. Musical instruments',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final id = newRecordId();
    await widget.categoryRepository.create(
      CategoriesCompanion.insert(id: drift.Value(id), name: name),
    );
    if (!mounted) return;
    setState(() {
      _categoriesFuture = widget.categoryRepository.getAll();
      _categoryId = id;
    });
  }

  Future<void> _load() async {
    if (_isEditing) {
      final belonging =
          await widget.belongingRepository.getById(widget.belongingId!);
      if (belonging != null) {
        _nameController.text = belonging.name;
        _brandController.text = belonging.brand ?? '';
        _modelController.text = belonging.model ?? '';
        _serialController.text = belonging.serialNumber ?? '';
        _notesController.text = belonging.notes ?? '';
        _valueController.text = centsToDecimalString(belonging.valueCents);
        _categoryId = belonging.categoryId;
        _locationId = belonging.locationId;
        _purchaseId = belonging.purchaseId;
        _condition = belonging.condition;
        _quantity = belonging.quantity;
        _valueUnknown = belonging.valueUnknown;
        _currencyCode =
            belonging.currencyCode ?? defaultCurrencyCode();
        _photoPath = belonging.photoPath;
        _isContainer = belonging.isContainer;
        if (_purchaseId != null) {
          final purchase =
              await widget.purchaseRepository.getById(_purchaseId!);
          _purchaseName = purchase?.productName;
        }
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _notesController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    // PermissionService guards `context.mounted` before every dialog or
    // snackbar, so passing context into the async request is safe.
    final granted = source == ImageSource.camera
        // ignore: use_build_context_synchronously
        ? await widget.permissionService.ensureCamera(context)
        // ignore: use_build_context_synchronously
        : await widget.permissionService.ensurePhotos(context);
    if (!granted) return;
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _pendingPhoto = File(picked.path));
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPurchase() async {
    final selected = await showDialog<Purchase>(
      context: context,
      builder: (dialogContext) => _PurchasePickerDialog(
        purchaseRepository: widget.purchaseRepository,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _purchaseId = selected.id;
        _purchaseName = selected.productName;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      // Persist a newly picked photo; drop the previous stored photo.
      var photoPath = _photoPath;
      if (_pendingPhoto != null) {
        final stored = await _fileStorage.saveBelongingPhoto(_pendingPhoto!);
        await _fileStorage.deleteFile(_photoPath);
        photoPath = stored.path;
      }

      final name = _nameController.text.trim();
      final valueCents =
          _valueUnknown ? null : parseMoneyToCents(_valueController.text);
      String? textOrNull(TextEditingController c) {
        final t = c.text.trim();
        return t.isEmpty ? null : t;
      }

      final companion = BelongingsCompanion(
        id: _isEditing
            ? const drift.Value.absent()
            : drift.Value(newRecordId()),
        name: drift.Value(name),
        brand: drift.Value(textOrNull(_brandController)),
        model: drift.Value(textOrNull(_modelController)),
        serialNumber: drift.Value(textOrNull(_serialController)),
        categoryId: drift.Value(_categoryId),
        locationId: drift.Value(_locationId),
        purchaseId: drift.Value(_purchaseId),
        photoPath: drift.Value(photoPath),
        quantity: drift.Value(_quantity),
        valueCents: drift.Value(valueCents),
        // Only store a currency when a value was entered.
        currencyCode: drift.Value(valueCents == null ? null : _currencyCode),
        valueUnknown: drift.Value(_valueUnknown),
        condition: drift.Value(_condition),
        isContainer: drift.Value(_isContainer),
        notes: drift.Value(textOrNull(_notesController)),
      );
      if (_isEditing) {
        final old = await widget.belongingRepository
            .getById(widget.belongingId!);
        await widget.belongingRepository.update(
            widget.belongingId!, companion);
        await _logFieldChanges(old, companion);
      } else {
        final id = _isContainer
            ? await widget.belongingRepository.createContainer(companion)
            : await widget.belongingRepository.create(companion);
        // Link tags chosen before the belonging existed.
        for (final tagName in _pendingTags) {
          final tag = await widget.tagRepository.getOrCreate(tagName);
          await widget.tagRepository.link(
            tagId: tag.id,
            entityType: 'belonging',
            entityId: id,
          );
        }
      }

      if (widget.onSaved != null) {
        widget.onSaved!();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Belonging updated.' : 'Belonging saved.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Records history entries for the edits the user actually changed:
  /// quantity, condition and value.
  Future<void> _logFieldChanges(
      Belonging? old, BelongingsCompanion companion) async {
    if (old == null || !_isEditing) return;
    final id = widget.belongingId!;
    final newQuantity =
        companion.quantity.present ? companion.quantity.value : old.quantity;
    if (newQuantity != old.quantity) {
      await widget.historyRepository.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.quantityChanged,
        title: 'Quantity changed from ${old.quantity} to $newQuantity',
      );
    }
    final newCondition = companion.condition.value;
    if (newCondition != old.condition) {
      await widget.historyRepository.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.conditionChanged,
        title: 'Condition changed to '
            '${BelongingCondition.labelOf(newCondition)}',
      );
    }
    final newValue = companion.valueCents.value;
    if (newValue != old.valueCents) {
      await widget.historyRepository.log(
        belongingId: id,
        eventType: BelongingHistoryEvent.valueChanged,
        title: newValue == null
            ? 'Value removed'
            : 'Value set to ${formatMoney(newValue, _currencyCode)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit belonging' : 'New belonging'),
        actions: [
          if (_loaded)
            TextButton(
              key: const Key('saveBelongingButton'),
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
                  _PhotoPicker(
                    pendingPhoto: _pendingPhoto,
                    photoPath: _photoPath,
                    onPick: _showPhotoSourceSheet,
                    onRemove: () => setState(() {
                      _pendingPhoto = null;
                      _photoPath = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('belonging-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Passport, Drill, Winter coat',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Give your belonging a name.'
                            : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _brandController,
                          decoration: const InputDecoration(
                            labelText: 'Brand (optional)',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            labelText: 'Model (optional)',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _serialController,
                    decoration: const InputDecoration(
                      labelText: 'Serial number (optional)',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Category>>(
                    future: _categoriesFuture,
                    builder: (context, snapshot) {
                      final categories = snapshot.data ?? const <Category>[];
                      return DropdownButtonFormField<String?>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          for (final category in categories)
                            DropdownMenuItem<String?>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _createCategory,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New category'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: _condition,
                    decoration: const InputDecoration(
                      labelText: 'Condition (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Not specified'),
                      ),
                      for (final code in BelongingCondition.all)
                        DropdownMenuItem<String?>(
                          value: code,
                          child: Text(BelongingCondition.labels[code]!),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _condition = value),
                  ),
                  SwitchListTile(
                    title: const Text('This is a container'),
                    subtitle: const Text(
                      'Boxes, bins and folders can hold other items.',
                    ),
                    secondary:
                        const Icon(Icons.inventory_2_outlined),
                    value: _isContainer,
                    onChanged: (value) =>
                        setState(() => _isContainer = value),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Location>>(
                    future: widget.locationRepository.getAll(),
                    builder: (context, snapshot) {
                      final locations = snapshot.data ?? const <Location>[];
                      final flat = flattenLocationTree(locations);
                      return DropdownButtonFormField<String?>(
                        initialValue: _locationId,
                        decoration: const InputDecoration(
                          labelText: 'Where is it kept? (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No location set'),
                          ),
                          for (final entry in flat)
                            DropdownMenuItem<String?>(
                              value: entry.location.id,
                              child: Text(
                                '${'  ' * entry.depth}${entry.location.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _locationId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _PurchaseLinkRow(
                    purchaseName: _purchaseName,
                    onPick: _pickPurchase,
                    onClear: () => setState(() {
                      _purchaseId = null;
                      _purchaseName = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Quantity'),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Decrease quantity',
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                      ),
                      Text('$_quantity',
                          style: Theme.of(context).textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Increase quantity',
                        onPressed: () => setState(() => _quantity++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: const Key('belonging-value'),
                          controller: _valueController,
                          enabled: !_valueUnknown,
                          decoration: const InputDecoration(
                            labelText: 'Value (optional)',
                            hintText: 'e.g. 49.99',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (value) {
                            if (_valueUnknown ||
                                value == null ||
                                value.trim().isEmpty) {
                              return null;
                            }
                            try {
                              parseMoneyToCents(value);
                            } catch (_) {
                              return 'Enter a valid amount, e.g. 49.99';
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            // Include any stored code so a value migrated or
                            // entered from another source never breaks the
                            // dropdown.
                            final currencies = {
                              ...commonCurrencies,
                              _currencyCode,
                            }.toList()
                              ..sort();
                            return DropdownButtonFormField<String>(
                              initialValue: _currencyCode,
                              decoration: const InputDecoration(
                                labelText: 'Currency',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final code in currencies)
                                  DropdownMenuItem<String>(
                                    value: code,
                                    child: Text(code),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _currencyCode = value);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: _valueUnknown,
                    onChanged: (value) => setState(
                        () => _valueUnknown = value ?? false),
                    title: const Text("I don't know the value"),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                  Text('Tags',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (_isEditing)
                    TagEditor(
                      tagRepository: widget.tagRepository,
                      entityType: 'belonging',
                      entityId: widget.belongingId!,
                      suggestions: const [
                        'Important',
                        'Expensive',
                        'Family',
                        'Work',
                        'School',
                        'Travel',
                        'Storage',
                      ],
                    )
                  else
                    _PendingTagEditor(
                      pendingTags: _pendingTags,
                      tagRepository: widget.tagRepository,
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
                ],
              ),
            ),
    );
  }
}

/// Linked-purchase row: shows the linked purchase or a button to link one.
class _PurchaseLinkRow extends StatelessWidget {
  const _PurchaseLinkRow({
    required this.purchaseName,
    required this.onPick,
    required this.onClear,
  });

  final String? purchaseName;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Linked purchase (optional)',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                purchaseName ?? 'Tap to link a purchase',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: purchaseName == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (purchaseName != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Unlink purchase',
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

/// Searchable purchase picker dialog.
class _PurchasePickerDialog extends StatefulWidget {
  const _PurchasePickerDialog({required this.purchaseRepository});

  final PurchaseRepository purchaseRepository;

  @override
  State<_PurchasePickerDialog> createState() => _PurchasePickerDialogState();
}

class _PurchasePickerDialogState extends State<_PurchasePickerDialog> {
  final _searchController = TextEditingController();
  List<Purchase> _purchases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = query.trim().isEmpty
        ? await widget.purchaseRepository.getAll()
        : await widget.purchaseRepository.searchByName(query.trim());
    if (mounted) {
      setState(() {
        _purchases = results;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link a purchase'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search purchases…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _purchases.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No purchases found.'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _purchases.length,
                          itemBuilder: (context, index) {
                            final purchase = _purchases[index];
                            return ListTile(
                              leading: const Icon(
                                  Icons.shopping_bag_outlined),
                              title: Text(purchase.productName),
                              subtitle: purchase.store == null
                                  ? null
                                  : Text(purchase.store!),
                              onTap: () =>
                                  Navigator.of(context).pop(purchase),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Tag editor for a belonging that doesn't exist yet: collects tag names in
/// memory; the form links them right after creating the belonging.
class _PendingTagEditor extends StatefulWidget {
  const _PendingTagEditor({
    required this.pendingTags,
    required this.tagRepository,
  });

  final List<String> pendingTags;
  final TagRepository tagRepository;

  @override
  State<_PendingTagEditor> createState() => _PendingTagEditorState();
}

class _PendingTagEditorState extends State<_PendingTagEditor> {
  Future<void> _openPicker() async {
    final all = await widget.tagRepository.watchAll().first;
    if (!mounted) return;
    final currentLower =
        widget.pendingTags.map((t) => t.toLowerCase()).toSet();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final controller = TextEditingController();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom:
                  MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Tags',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in [
                      'Important',
                      'Expensive',
                      'Family',
                      'Work',
                      'School',
                      'Travel',
                      'Storage',
                    ])
                      if (!currentLower.contains(s.toLowerCase()))
                        ActionChip(
                          label: Text(s),
                          onPressed: () {
                            setState(
                                () => widget.pendingTags.add(s));
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'New tag',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          final name = controller.text.trim();
                          if (name.isNotEmpty) {
                            setState(
                                () => widget.pendingTags.add(name));
                          }
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final name = controller.text.trim();
                        if (name.isNotEmpty) {
                          setState(
                              () => widget.pendingTags.add(name));
                        }
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tag in all)
                          if (!currentLower
                              .contains(tag.name.toLowerCase()))
                            ListTile(
                              dense: true,
                              leading:
                                  const Icon(Icons.label_outline),
                              title: Text(tag.name),
                              onTap: () {
                                setState(() => widget.pendingTags
                                    .add(tag.name));
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final name in widget.pendingTags)
          Chip(
            label: Text(name),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () =>
                setState(() => widget.pendingTags.remove(name)),
            visualDensity: VisualDensity.compact,
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: Text(
              widget.pendingTags.isEmpty ? 'Add tags' : 'Add'),
          onPressed: _openPicker,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.pendingPhoto,
    required this.photoPath,
    required this.onPick,
    required this.onRemove,
  });

  final File? pendingPhoto;
  final String? photoPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = pendingPhoto ??
        (photoPath == null || photoPath!.isEmpty ? null : File(photoPath!));
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        child: preview == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 40),
                    SizedBox(height: 8),
                    Text('Add a photo (optional)'),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    preview,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove photo',
                      onPressed: onRemove,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
