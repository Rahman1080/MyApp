import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/tables.dart' show newRecordId;
import '../../../core/database/repositories/belonging_repository.dart';
import '../../../core/database/repositories/category_repository.dart';
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utilities/money.dart';
import '../../../shared/services/file_storage.dart';
import 'widgets/location_path.dart';

/// Add/edit form for a belonging. Name is required; everything else —
/// brand, category, hierarchical location, quantity, notes and a photo —
/// is optional.
class BelongingFormScreen extends StatefulWidget {
  const BelongingFormScreen({
    super.key,
    required this.belongingRepository,
    required this.categoryRepository,
    required this.locationRepository,
    this.permissionService = const PermissionService(),
    this.fileStorage,
    this.imagePicker,
    this.belongingId,
    this.onSaved,
  });

  final BelongingRepository belongingRepository;
  final CategoryRepository categoryRepository;
  final LocationRepository locationRepository;
  final PermissionService permissionService;
  final FileStorage? fileStorage;
  final ImagePicker? imagePicker;

  /// Null for a new belonging, set when editing.
  final String? belongingId;

  /// Called after a successful save. Defaults to popping the form.
  final VoidCallback? onSaved;

  @override
  State<BelongingFormScreen> createState() => _BelongingFormScreenState();
}

class _BelongingFormScreenState extends State<BelongingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _notesController = TextEditingController();
  final _valueController = TextEditingController();

  String? _categoryId;
  String? _locationId;
  int _quantity = 1;
  String _currencyCode = 'USD';
  String? _photoPath; // persisted path of the current photo, if any
  File? _pendingPhoto; // newly picked, not yet persisted

  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.belongingId != null;

  FileStorage get _fileStorage => widget.fileStorage ?? FileStorage();
  ImagePicker get _imagePicker => widget.imagePicker ?? ImagePicker();

  @override
  void initState() {
    super.initState();
    _currencyCode = defaultCurrencyCode();
    _load();
  }

  Future<void> _load() async {
    if (_isEditing) {
      final belonging =
          await widget.belongingRepository.getById(widget.belongingId!);
      if (belonging != null) {
        _nameController.text = belonging.name;
        _brandController.text = belonging.brand ?? '';
        _notesController.text = belonging.notes ?? '';
        _valueController.text = centsToDecimalString(belonging.valueCents);
        _categoryId = belonging.categoryId;
        _locationId = belonging.locationId;
        _quantity = belonging.quantity;
        _currencyCode =
            belonging.currencyCode ?? defaultCurrencyCode();
        _photoPath = belonging.photoPath;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
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
      final valueCents = parseMoneyToCents(_valueController.text);
      final companion = BelongingsCompanion(
        id: _isEditing
            ? const drift.Value.absent()
            : drift.Value(newRecordId()),
        name: drift.Value(name),
        brand: drift.Value(
          _brandController.text.trim().isEmpty
              ? null
              : _brandController.text.trim(),
        ),
        categoryId: drift.Value(_categoryId),
        locationId: drift.Value(_locationId),
        photoPath: drift.Value(photoPath),
        quantity: drift.Value(_quantity),
        valueCents: drift.Value(valueCents),
        // Only store a currency when a value was entered.
        currencyCode: drift.Value(valueCents == null ? null : _currencyCode),
        notes: drift.Value(
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      );
      if (_isEditing) {
        await widget.belongingRepository.update(
            widget.belongingId!, companion);
      } else {
        await widget.belongingRepository.create(companion);
      }

      if (widget.onSaved != null) {
        widget.onSaved!();
      } else if (mounted) {
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
                  TextFormField(
                    controller: _brandController,
                    decoration: const InputDecoration(
                      labelText: 'Brand (optional)',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Category>>(
                    future: widget.categoryRepository.getAll(),
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
                          decoration: const InputDecoration(
                            labelText: 'Value (optional)',
                            hintText: 'e.g. 49.99',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
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
