import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/location_meta.dart';
import '../../../core/database/tables.dart' show newRecordId;
import '../../../core/database/repositories/location_repository.dart';
import '../../../core/database/repositories/place_repository.dart';
import '../../../shared/services/location_service.dart';
import '../../belongings/presentation/widgets/location_path.dart';

/// Add/edit form for a location. The parent picker excludes the location
/// itself and all of its descendants, so a cycle can never be created.
class LocationFormScreen extends StatefulWidget {
  const LocationFormScreen({
    super.key,
    required this.locationRepository,
    required this.locationService,
    required this.placeRepository,
    this.locationId,
    this.initialParentId,
    this.initialPlaceId,
    this.onSaved,
  });

  final LocationRepository locationRepository;
  final LocationService locationService;
  final PlaceRepository placeRepository;

  /// Null for a new location, set when editing.
  final String? locationId;

  /// Pre-selected parent for "add sub-location" flows.
  final String? initialParentId;

  /// Pre-selected place for "add location" flows (e.g. from a place chip).
  final String? initialPlaceId;

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
  String? _placeId;
  List<Place> _places = const [];
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
    _places = await widget.placeRepository.getAll();
    if (_isEditing) {
      final location =
          await widget.locationRepository.getById(widget.locationId!);
      if (location != null) {
        _nameController.text = location.name;
        _notesController.text = location.notes ?? '';
        _parentId = location.parentLocationId;
        _placeId = location.placeId;
      }
    } else {
      // New locations inherit the parent's place; otherwise use the
      // pre-selected place (or fall back to the default place).
      _placeId = widget.initialPlaceId;
      if (_parentId != null) {
        final parent =
            await widget.locationRepository.getById(_parentId!);
        _placeId = parent?.placeId ?? _placeId;
      }
      _placeId ??= _places.isEmpty ? null : _places.first.id;
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
        placeId: _placeId == null
            ? const drift.Value.absent()
            : drift.Value(_placeId!),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Location updated.' : 'Location saved.',
            ),
          ),
        );
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
                  if (!_isEditing) ...[
                    const SizedBox(height: 12),
                    const Text('Room templates'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final template in LocationTemplates.all)
                          ActionChip(
                            label: Text(template),
                            onPressed: () => setState(() =>
                                _nameController.text = template),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_places.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _places.any((p) => p.id == _placeId)
                          ? _placeId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Place',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final place in _places)
                          DropdownMenuItem(
                            value: place.id,
                            child: Text(place.name),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _placeId = value),
                    ),
                  if (_places.length > 1) const SizedBox(height: 16),
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
                        onChanged: (value) async {
                          setState(() => _parentId = value);
                          if (value != null) {
                            final parent = await widget.locationRepository
                                .getById(value);
                            if (mounted && parent != null) {
                              setState(() => _placeId = parent.placeId);
                            }
                          }
                        },
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
