import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key-value secure storage contract.
///
/// The production implementation delegates to [FlutterSecureStorage]
/// (Keychain on iOS, Keystore on Android). Tests use [InMemorySecureStore].
/// Only the app-lock PIN hash is stored through this interface — never
/// user content.
abstract class SecureStore {
  Future<bool> containsKey(String key);
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production [SecureStore] backed by the platform keystore/keychain.
class PlatformSecureStore implements SecureStore {
  PlatformSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory [SecureStore] for tests. Never used in production.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
