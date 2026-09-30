import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_store.dart';

/// Owns the app-lock PIN and optional biometric unlock.
///
/// The PIN itself is never stored: only a salted SHA-256 hash lives in
/// secure storage (`saltHex:hashHex`). Verification is constant-time.
/// Nothing here logs or exposes the PIN.
class PinLockService {
  PinLockService({SecureStore? secureStore, LocalAuthentication? localAuth})
      : _store = secureStore ?? PlatformSecureStore(),
        _auth = localAuth ?? LocalAuthentication();

  final SecureStore _store;
  final LocalAuthentication _auth;

  static const String _pinKey = 'keepit_pin_hash_v1';
  static const int minPinLength = 4;
  static const int maxPinLength = 8;

  /// Whether a PIN is currently set.
  Future<bool> hasPin() => _store.containsKey(_pinKey);

  /// Stores a new PIN (replacing any existing one). Throws [PinException]
  /// when the PIN does not meet the length rules.
  Future<void> setPin(String pin) async {
    _validatePin(pin);
    final salt = _randomSalt();
    final hash = _hash(pin, salt);
    await _store.write(_pinKey, '${_toHex(salt)}:${_toHex(hash)}');
  }

  /// Returns true when [pin] matches the stored PIN.
  Future<bool> verifyPin(String pin) async {
    final stored = await _store.read(_pinKey);
    if (stored == null) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = _fromHex(parts[0]);
    final expected = _fromHex(parts[1]);
    if (salt == null || expected == null) return false;
    return _constantTimeEquals(_hash(pin, salt), expected);
  }

  /// Removes the stored PIN.
  Future<void> clearPin() => _store.delete(_pinKey);

  /// Whether the device can do biometric or device-credential auth right now.
  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts the system biometric / device-credential dialog. Returns true
  /// when the user authenticated. Never throws: failures return false.
  Future<bool> authenticateWithBiometrics({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      // Deliberately no details logged: auth errors must not leak state.
      debugPrint('KeepIt: biometric auth unavailable (${e.code.name}).');
      return false;
    } catch (_) {
      return false;
    }
  }

  void _validatePin(String pin) {
    final digitsOnly = RegExp(r'^\d+$').hasMatch(pin);
    if (!digitsOnly ||
        pin.length < minPinLength ||
        pin.length > maxPinLength) {
      throw PinException(
        'PIN must be $minPinLength–$maxPinLength digits.',
      );
    }
  }

  List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  List<int> _hash(String pin, List<int> salt) {
    return sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int>? _fromHex(String hex) {
    if (hex.length.isOdd) return null;
    try {
      final out = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        out.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}

/// Thrown when a PIN does not meet the format rules.
class PinException implements Exception {
  PinException(this.message);
  final String message;

  @override
  String toString() => 'PinException: $message';
}
