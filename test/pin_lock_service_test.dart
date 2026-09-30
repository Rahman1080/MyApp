import 'package:flutter_test/flutter_test.dart';
import 'package:keepit/core/security/pin_lock_service.dart';
import 'package:keepit/core/security/secure_store.dart';

/// Records every write so tests can inspect what was stored without knowing
/// the private storage key.
class _RecordingStore extends InMemorySecureStore {
  final Map<String, String> written = {};

  @override
  Future<void> write(String key, String value) async {
    written[key] = value;
    await super.write(key, value);
  }
}

void main() {
  late _RecordingStore store;
  late PinLockService pinLock;

  setUp(() {
    store = _RecordingStore();
    pinLock = PinLockService(secureStore: store);
  });

  group('setPin / verifyPin / hasPin / clearPin', () {
    test('no PIN set initially', () async {
      expect(await pinLock.hasPin(), isFalse);
      expect(await pinLock.verifyPin('1234'), isFalse);
    });

    test('correct PIN verifies, wrong PIN does not', () async {
      await pinLock.setPin('2468');
      expect(await pinLock.hasPin(), isTrue);
      expect(await pinLock.verifyPin('2468'), isTrue);
      expect(await pinLock.verifyPin('2469'), isFalse);
      expect(await pinLock.verifyPin(''), isFalse);
    });

    test('clearPin removes the PIN', () async {
      await pinLock.setPin('1357');
      await pinLock.clearPin();
      expect(await pinLock.hasPin(), isFalse);
      expect(await pinLock.verifyPin('1357'), isFalse);
    });

    test('re-setting the PIN replaces the old one', () async {
      await pinLock.setPin('1111');
      await pinLock.setPin('2222');
      expect(await pinLock.verifyPin('1111'), isFalse);
      expect(await pinLock.verifyPin('2222'), isTrue);
    });
  });

  group('PIN validation', () {
    test('rejects non-digit PINs', () async {
      await expectLater(pinLock.setPin('12a4'), throwsA(isA<PinException>()));
      await expectLater(pinLock.setPin('abcd'), throwsA(isA<PinException>()));
      await expectLater(pinLock.setPin('12 4'), throwsA(isA<PinException>()));
    });

    test('rejects PINs outside 4-8 digits', () async {
      await expectLater(pinLock.setPin('123'), throwsA(isA<PinException>()));
      await expectLater(
          pinLock.setPin('123456789'), throwsA(isA<PinException>()));
      await expectLater(pinLock.setPin(''), throwsA(isA<PinException>()));
    });

    test('accepts 4 to 8 digit PINs', () async {
      for (final pin in ['1234', '12345', '123456', '1234567', '12345678']) {
        await pinLock.setPin(pin);
        expect(await pinLock.verifyPin(pin), isTrue,
            reason: 'PIN $pin should verify');
      }
    });
  });

  group('storage hygiene', () {
    test('the PIN itself is never stored', () async {
      await pinLock.setPin('9876');
      expect(store.written, hasLength(1));
      final stored = store.written.values.single;
      expect(stored, isNot(contains('9876')));
    });

    test('identical PINs get different salts', () async {
      final storeA = _RecordingStore();
      final storeB = _RecordingStore();
      await PinLockService(secureStore: storeA).setPin('5555');
      await PinLockService(secureStore: storeB).setPin('5555');
      expect(
        storeA.written.values.single,
        isNot(storeB.written.values.single),
      );
    });

    test('a tampered hash never verifies', () async {
      await pinLock.setPin('4321');
      final key = store.written.keys.single;
      await store.write(key, 'tampered-value');
      expect(await pinLock.verifyPin('4321'), isFalse);
    });
  });

  group('biometrics', () {
    test('canUseBiometrics is false when the platform is unavailable',
        () async {
      // In a unit test there is no platform channel, so this must fail
      // closed rather than throw.
      expect(await pinLock.canUseBiometrics(), isFalse);
    });

    test('authenticateWithBiometrics fails closed without a platform',
        () async {
      expect(
        await pinLock.authenticateWithBiometrics(reason: 'test'),
        isFalse,
      );
    });
  });
}
