import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/keepit_database.dart';

/// How to resolve a sync conflict when the same record was modified
/// on both devices.
enum ConflictResolution {
  /// Keep the local version, discard the remote change.
  keepLocal,

  /// Keep the remote version, discard the local change.
  keepRemote,

  /// Keep whichever version has the newer updatedAt timestamp.
  keepNewest,
}

/// A record that was modified on both sides since the last sync.
class SyncConflict {
  const SyncConflict({
    required this.entityType,
    required this.entityId,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.localData,
    required this.remoteData,
  });

  final String entityType;
  final String entityId;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;

  /// The newer of the two versions.
  bool get remoteIsNewer => remoteUpdatedAt.isAfter(localUpdatedAt);
}

/// Result of a sync operation.
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.conflicts,
    required this.syncedAt,
  });

  final int pushed;
  final int pulled;
  final List<SyncConflict> conflicts;
  final DateTime syncedAt;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Abstract sync provider. Phase 17 ships with [FileSyncProvider];
/// cloud providers (Google Drive, iCloud, etc.) can implement this
/// interface in the future without changing [SyncService].
abstract class SyncProvider {
  /// Uploads sync data. Returns a provider-specific receipt/token.
  Future<String> upload(String deviceId, Map<String, dynamic> data);

  /// Downloads the latest sync data, or null if none exists.
  Future<Map<String, dynamic>?> download(String deviceId);

  /// When the remote data was last updated, or null if never.
  Future<DateTime?> lastRemoteUpdate(String deviceId);
}

/// File-based sync provider for manual device-to-device transfer.
/// Writes a JSON sync file that can be shared via any file-sharing method.
class FileSyncProvider implements SyncProvider {
  FileSyncProvider(this._storage);

  final Map<String, String> _storage;

  @override
  Future<String> upload(String deviceId, Map<String, dynamic> data) async {
    final key = 'sync_$deviceId';
    _storage[key] = jsonEncode(data);
    _storage['${key}_time'] = DateTime.now().toIso8601String();
    return key;
  }

  @override
  Future<Map<String, dynamic>?> download(String deviceId) async {
    final key = 'sync_$deviceId';
    final json = _storage[key];
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  @override
  Future<DateTime?> lastRemoteUpdate(String deviceId) async {
    final timeStr = _storage['sync_${deviceId}_time'];
    if (timeStr == null) return null;
    return DateTime.parse(timeStr);
  }
}

/// Cross-device sync service (Phase 17).
///
/// Offline-first: local data always works. Sync is explicit and user-initiated.
/// Conflicts are detected and surfaced — never silently overwritten.
class SyncService {
  SyncService(this._db, this._provider, this._deviceId);

  final KeepItDatabase _db;
  final SyncProvider _provider;
  final String _deviceId;

  /// This device's sync identifier.
  String get deviceId => _deviceId;

  /// Exports records modified since [since] for upload.
  Future<Map<String, dynamic>> exportChanges(DateTime? since) async {
    final belongings = await (_db.select(_db.belongings)
          ..where((t) => since == null
              ? const Constant(true)
              : t.updatedAt.isBiggerThanValue(since)))
        .get();

    return {
      'deviceId': _deviceId,
      'exportedAt': DateTime.now().toIso8601String(),
      'belongings': belongings.map((b) => b.toJson()).toList(),
    };
  }

  /// Performs a full sync: push local changes, pull remote changes from
  /// [peerDeviceIds], detect conflicts. Returns a [SyncResult] with any
  /// conflicts for the user to resolve explicitly.
  Future<SyncResult> sync({DateTime? since, List<String> peerDeviceIds = const []}) async {
    final localChanges = await exportChanges(since);
    final pushed = (localChanges['belongings'] as List).length;

    await _provider.upload(_deviceId, localChanges);

    var totalPulled = 0;
    final allConflicts = <SyncConflict>[];

    for (final peerId in peerDeviceIds) {
      if (peerId == _deviceId) continue;
      final remoteData = await _provider.download(peerId);
      if (remoteData == null) continue;

      final result = await _importRemote(remoteData, 0);
      totalPulled += result.pulled;
      allConflicts.addAll(result.conflicts);
    }

    return SyncResult(
      pushed: pushed,
      pulled: totalPulled,
      conflicts: allConflicts,
      syncedAt: DateTime.now(),
    );
  }

  /// Imports a sync payload (e.g. from a file shared by another device).
  /// Returns the sync result including any conflicts for explicit
  /// user resolution. Never silently overwrites local data.
  Future<SyncResult> importData(Map<String, dynamic> remoteData) {
    return _importRemote(remoteData, 0);
  }

  Future<SyncResult> _importRemote(
    Map<String, dynamic> remoteData,
    int pushed,
  ) async {
    final conflicts = <SyncConflict>[];
    var pulled = 0;

    final remoteBelongings =
        (remoteData['belongings'] as List?) ?? [];

    for (final raw in remoteBelongings) {
      final data = raw as Map<String, dynamic>;
      final id = data['id'] as String;

      final local = await (_db.select(_db.belongings)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

      if (local == null) {
        // New record from remote — insert it.
        await _db
            .into(_db.belongings)
            .insert(Belonging.fromJson(data));
        pulled++;
      } else {
        // Both sides have it — check for conflict.
        final remoteUpdatedAt = DateTime.parse(data['updatedAt'] as String);
        final localUpdatedAt = local.updatedAt;

        // If remote is newer and different, it's a conflict
        // (local may also have changes).
        if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
          final localJson = local.toJson();
          // Simple conflict detection: if any field differs,
          // flag it for explicit resolution.
          if (_hasDifferences(localJson, data)) {
            conflicts.add(SyncConflict(
              entityType: 'belonging',
              entityId: id,
              localUpdatedAt: localUpdatedAt,
              remoteUpdatedAt: remoteUpdatedAt,
              localData: localJson,
              remoteData: data,
            ));
          } else {
            // Same content, just update the timestamp.
            pulled++;
          }
        }
        // If local is newer or equal, keep local (no action).
      }
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      syncedAt: DateTime.now(),
    );
  }

  bool _hasDifferences(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // Compare all fields except updatedAt.
    final localCopy = Map<String, dynamic>.from(local)..remove('updatedAt');
    final remoteCopy = Map<String, dynamic>.from(remote)..remove('updatedAt');
    if (localCopy.length != remoteCopy.length) return true;
    for (final key in localCopy.keys) {
      if (localCopy[key] != remoteCopy[key]) return true;
    }
    return false;
  }

  /// Resolves a conflict using the specified strategy.
  Future<void> resolveConflict(
    SyncConflict conflict,
    ConflictResolution resolution,
  ) async {
    switch (resolution) {
      case ConflictResolution.keepLocal:
        // Do nothing — local version stays.
        break;
      case ConflictResolution.keepRemote:
        await (_db.update(_db.belongings)
              ..where((t) => t.id.equals(conflict.entityId)))
            .write(Belonging.fromJson(conflict.remoteData));
        break;
      case ConflictResolution.keepNewest:
        if (conflict.remoteIsNewer) {
          await (_db.update(_db.belongings)
                ..where((t) => t.id.equals(conflict.entityId)))
              .write(Belonging.fromJson(conflict.remoteData));
        }
        // Else keep local (do nothing).
        break;
    }
  }
}
