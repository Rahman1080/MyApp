import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/tables.dart' show newRecordId;
import '../../../core/database/repositories/location_repository.dart';
import '../../../shared/services/location_service.dart';
import '../../belongings/presentation/widgets/location_path.dart';

/// Add/edit form for a location. The parent picker excludes the location
/// itself and all of its descendants, so a cycle can never be created.
class LocationFormScreen extends StatefulWidget {
  const LocationFormScreen({
    super.key,
    required this.locationRepository,
    required this.locationService,
    this.locationId,
    this.initialParentId,
    this.onSaved,
  });

  final LocationRepository locationRepository;
  final LocationService locationService;

  /// Null for a new location, set when editing.
  final String? locationId;

  /// Pre-selected parent for "add sub-location" flows.
  final String? initialParentId;

  /// Called after a successful save. Defaults to popping the form.
  final VoidCallback? onSaved;

  @override
  State<LocationFormScreen> createState() => _LocationFormScreenState();
}

class _LocationFormScreenState extends State<LocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  String? _parentId;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEditing => widget.locationId != null;

  @override
  void initState() {
    super.initState();
    _parentId = widget.initialParentId;
    _load();
  }

  Future<void> _load() async {
    if (_isEditing) {
      final location =
          await widget.locationRepository.getById(widget.locationId!);
      if (location != null) {
        _nameController.text = location.name;
        _notesController.text = location.notes ?? '';
        _parentId = location.parentLocationId;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final name = _nameController.text.trim();
      final companion = LocationsCompanion(
        id: _isEditing
            ? const drift.Value.absent()
            : drift.Value(newRecordId()),
        name: drift.Value(name),
        parentLocationId: drift.Value(_parentId),
        notes: drift.Value(
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      );
      if (_isEditing) {
        await widget.locationRepository.update(
            widget.locationId!, companion);
      } else {
        await widget.locationRepository.create(companion);
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

  /// Parent candidates: every location except this one and its descendants
  /// (picking any of those would create a cycle).
  Future<List<Location>> _parentCandidates() async {
    final all = await widget.locationRepository.getAll();
    if (!_isEditing) return all;
    final candidates = <Location>[];
    for (final location in all) {
      if (location.id == widget.locationId) continue;
      if (await widget.locationService
          .wouldCreateCycle(widget.locationId!, location.id)) {
        continue;
      }
      candidates.add(location);
    }
    return candidates;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit location' : 'New location'),
        actions: [
          if (_loaded)
            TextButton(
              key: const Key('saveLocationButton'),
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
                  TextFormField(
                    key: const Key('location-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Home, Bedroom, Top drawer',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Give the location a name.'
                            : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Location>>(
                    future: _parentCandidates(),
                    builder: (context, snapshot) {
                      final candidates = snapshot.data ?? const <Location>[];
                      final paths = buildLocationPaths(candidates);
                      // The current parent may be filtered out only if it
                      // became invalid; keep the selection stable otherwise.
                      final effectiveParent =
                          candidates.any((l) => l.id == _parentId)
                              ? _parentId
                              : null;
                      return DropdownButtonFormField<String?>(
                        initialValue: effectiveParent,
                        decoration: const InputDecoration(
                          labelText: 'Inside (optional)',
                          helperText:
                              'Leave empty for a top-level location like “Home”.',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Top level'),
                          ),
                          for (final location in candidates)
                            DropdownMenuItem<String?>(
                              value: location.id,
                              child: Text(
                                paths[location.id] ?? location.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _parentId = value),
                      );
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
                ],
              ),
            ),
    );
  }
}
