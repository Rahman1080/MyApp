import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/keepit_database.dart';
import '../domain/device_id_provider.dart';
import '../domain/sync_service.dart';

/// Phase 17 UI — Cloud Backup and Cross-Device Sync.
///
/// Lets the user:
/// - See this device's sync ID
/// - Export changes to a shareable JSON file (send to another device)
/// - Import a sync file from another device, with explicit conflict
///   resolution (keep mine / keep theirs / keep newest)
///
/// Sync is manual and peer-to-peer: the user moves the file themselves
/// (messaging app, USB, cloud drive). Nothing is uploaded automatically.
class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    required this.database,
    this.syncService,
  });

  static const routePath = '/sync';

  final KeepItDatabase database;

  /// Pre-built service (used in tests to skip device-ID resolution).
  final SyncService? syncService;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncService? _syncService;
  bool _busy = false;
  SyncResult? _lastResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.syncService != null) {
      _syncService = widget.syncService;
    } else {
      _initService();
    }
  }

  Future<void> _initService() async {
    try {
      final provider = await DeviceIdProvider.load();
      final deviceId = await provider.getDeviceId();
      if (!mounted) return;
      setState(() {
        _syncService = SyncService(
          widget.database,
          FileSyncProvider({}),
          deviceId,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start sync: $e');
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _syncService!.exportChanges(null);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/keepit-sync-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(data));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'KEEPIT sync data from this device',
        ),
      );
    } catch (e) {
      setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      final json = await File(path).readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      final syncResult = await _syncService!.importData(data);
      setState(() => _lastResult = syncResult);
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveConflict(
    SyncConflict conflict,
    ConflictResolution resolution,
  ) async {
    await _syncService!.resolveConflict(conflict, resolution);
    setState(() {
      _lastResult = SyncResult(
        pushed: _lastResult?.pushed ?? 0,
        pulled: _lastResult?.pulled ?? 0,
        conflicts: _lastResult!.conflicts
            .where((c) => c.entityId != conflict.entityId)
            .toList(),
        syncedAt: _lastResult!.syncedAt,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: _syncService == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDeviceCard(),
          const SizedBox(height: 16),
          _buildActionsCard(),
          const SizedBox(height: 16),
          if (_error != null) _buildError(),
          if (_lastResult != null) _buildResult(),
        ],
      ),
    );
  }

  Widget _buildDeviceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This device',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _syncService!.deviceId,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy device ID',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _syncService!.deviceId),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device ID copied')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Share this ID with your other device so it can find your data.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    final ready = _syncService != null && !_busy;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Export to another device'),
            subtitle: const Text(
              'Create a sync file and send it however you like.',
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: ready ? _export : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import from another device'),
            subtitle: const Text(
              'Pick a sync file. Conflicts are shown for you to resolve.',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: ready ? _import : null,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!),
      ),
    );
  }

  Widget _buildResult() {
    final result = _lastResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('New items', result.pulled),
                _stat('Conflicts', result.conflicts.length),
              ],
            ),
          ),
        ),
        if (result.conflicts.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Conflicts — choose which version to keep',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...result.conflicts.map(_buildConflictCard),
        ] else ...[
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text('Sync complete — no conflicts'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stat(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildConflictCard(SyncConflict conflict) {
    final localName =
        (conflict.localData['name'] as String?) ?? conflict.entityId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Changed on both devices. '
              '${conflict.remoteIsNewer ? "The other device's version is newer." : "Your version is newer."}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _resolveConflict(
                    conflict,
                    ConflictResolution.keepLocal,
                  ),
                  child: const Text('Keep mine'),
                ),
                OutlinedButton(
                  onPressed: () => _resolveConflict(
                    conflict,
                    ConflictResolution.keepRemote,
                  ),
                  child: const Text('Keep theirs'),
                ),
                FilledButton.tonal(
                  onPressed: () => _resolveConflict(
                    conflict,
                    ConflictResolution.keepNewest,
                  ),
                  child: const Text('Keep newest'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
