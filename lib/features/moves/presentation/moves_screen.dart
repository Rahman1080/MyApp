import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/database/keepit_database.dart';
import '../../../core/database/repositories/move_repository.dart';
import '../../../core/database/repositories/place_repository.dart';

/// Phase 12 "Moving Mode": list of relocation projects.
class MovesScreen extends StatefulWidget {
  static const routePath = '/moves';

  const MovesScreen({
    super.key,
    required this.moveRepository,
    required this.placeRepository,
  });

  final MoveRepository moveRepository;
  final PlaceRepository placeRepository;

  @override
  State<MovesScreen> createState() => _MovesScreenState();
}

class _MovesScreenState extends State<MovesScreen> {
  final _dateFormat = DateFormat.yMMMd();

  Future<void> _createMove() async {
    final places = await widget.placeRepository.getAll();
    if (!mounted) return;
    final result = await showDialog<_NewMoveData>(
      context: context,
      builder: (context) => _NewMoveDialog(places: places),
    );
    if (result == null) return;
    final id = await widget.moveRepository.createNamed(
      result.name,
      fromPlaceId: result.fromPlaceId,
      toPlaceId: result.toPlaceId,
      moveDate: result.moveDate,
      notes: result.notes,
    );
    if (mounted) {
      context.push('${MovesScreen.routePath}/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moving Mode')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createMove,
        icon: const Icon(Icons.local_shipping_outlined),
        label: const Text('New move'),
      ),
      body: StreamBuilder<List<Move>>(
        stream: widget.moveRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final moves = snapshot.data ?? [];
          if (moves.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No moves yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Start a move to track packing, transit, and unpacking '
                      'for a relocation.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: moves.length,
            itemBuilder: (context, index) {
              final move = moves[index];
              final terminal = MoveStatus.isTerminal(move.status);
              return Card(
                child: ListTile(
                  leading: Icon(
                    terminal
                        ? Icons.check_circle_outline
                        : Icons.local_shipping_outlined,
                    color: terminal
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(move.name),
                  subtitle: Text(
                    [
                      MoveStatus.label(move.status),
                      if (move.moveDate != null)
                        _dateFormat.format(move.moveDate!),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('${MovesScreen.routePath}/${move.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NewMoveData {
  _NewMoveData({
    required this.name,
    this.fromPlaceId,
    this.toPlaceId,
    this.moveDate,
    this.notes,
  });

  final String name;
  final String? fromPlaceId;
  final String? toPlaceId;
  final DateTime? moveDate;
  final String? notes;
}

class _NewMoveDialog extends StatefulWidget {
  const _NewMoveDialog({required this.places});

  final List<Place> places;

  @override
  State<_NewMoveDialog> createState() => _NewMoveDialogState();
}

class _NewMoveDialogState extends State<_NewMoveDialog> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  String? _fromPlaceId;
  String? _toPlaceId;
  DateTime? _moveDate;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New move'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Move name',
                hintText: 'e.g. Move to new apartment',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _fromPlaceId,
              decoration: const InputDecoration(labelText: 'From place'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not set')),
                for (final place in widget.places)
                  DropdownMenuItem(value: place.id, child: Text(place.name)),
              ],
              onChanged: (v) => setState(() => _fromPlaceId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _toPlaceId,
              decoration: const InputDecoration(labelText: 'To place'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not set')),
                for (final place in widget.places)
                  DropdownMenuItem(value: place.id, child: Text(place.name)),
              ],
              onChanged: (v) => setState(() => _toPlaceId = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Move date'),
              subtitle: Text(
                _moveDate == null
                    ? 'Not set'
                    : DateFormat.yMMMd().format(_moveDate!),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null) setState(() => _moveDate = picked);
              },
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(
              _NewMoveData(
                name: name,
                fromPlaceId: _fromPlaceId,
                toPlaceId: _toPlaceId,
                moveDate: _moveDate,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
