import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Provides a stable per-device identifier for sync.
///
/// The ID is generated once (cryptographically random, 128 bits) and
/// persisted in the app's documents directory so it survives restarts.
/// It is only ever shown to the user for manual peer identification —
/// it is never transmitted automatically anywhere.
class DeviceIdProvider {
  DeviceIdProvider._(this._file);

  final File _file;

  static Future<DeviceIdProvider> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/keepit_device_id.txt');
    return DeviceIdProvider._(file);
  }

  /// Returns the existing device ID, generating and persisting one on
  /// first use.
  Future<String> getDeviceId() async {
    if (await _file.exists()) {
      final stored = (await _file.readAsString()).trim();
      if (stored.isNotEmpty) return stored;
    }
    final id = _generate();
    await _file.writeAsString(id);
    return id;
  }

  String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
