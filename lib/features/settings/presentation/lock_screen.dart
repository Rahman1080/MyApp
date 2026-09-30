import 'dart:async';

import 'package:flutter/material.dart';

import '../../settings/data/settings_repository.dart';
import 'pin_pad.dart';
import '../../../core/security/pin_lock_service.dart';

/// The gate shown when the app is locked. Verifies the PIN locally — nothing
/// is sent anywhere — and calls [onUnlock] on success.
///
/// Failed attempts are delayed with a lockout after [_maxAttempts] tries.
/// There is deliberately no auto-wipe: a forgotten PIN only means the data
/// stays on the device, unreachable until the PIN is remembered.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.pinLock,
    required this.settingsRepository,
    required this.onUnlock,
  });

  final PinLockService pinLock;
  final SettingsRepository settingsRepository;
  final VoidCallback onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _maxAttempts = 5;
  static const _lockout = Duration(seconds: 30);

  final _pinPadKey = GlobalKey<PinPadState>();
  String? _error;
  int _attempts = 0;
  DateTime? _lockedUntil;
  Timer? _lockoutTimer;
  bool _biometricOffered = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final enabled = await widget.settingsRepository
        .getBiometricUnlockEnabled()
        .catchError((_) => false);
    final can = enabled ? await widget.pinLock.canUseBiometrics() : false;
    if (mounted) setState(() => _biometricOffered = can);
  }

  bool get _isLockedOut {
    final lockedUntil = _lockedUntil;
    return lockedUntil != null && DateTime.now().isBefore(lockedUntil);
  }

  Future<void> _submit(String pin) async {
    if (_checking || _isLockedOut) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final ok = await widget.pinLock.verifyPin(pin);
      if (!mounted) return;
      if (ok) {
        widget.onUnlock();
        return;
      }
      _attempts++;
      _pinPadKey.currentState?.reset();
      if (_attempts >= _maxAttempts) {
        final until = DateTime.now().add(_lockout);
        setState(() {
          _lockedUntil = until;
          _error = 'Too many wrong attempts. Try again in 30 seconds.';
        });
        _lockoutTimer?.cancel();
        _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (DateTime.now().isAfter(until)) {
            timer.cancel();
            setState(() {
              _lockedUntil = null;
              _attempts = 0;
              _error = null;
            });
          } else {
            setState(() {
              _error =
                  'Too many wrong attempts. Try again in ${until.difference(DateTime.now()).inSeconds} seconds.';
            });
          }
        });
      } else {
        setState(() {
          _error =
              'Wrong PIN. ${_maxAttempts - _attempts} ${_maxAttempts - _attempts == 1 ? 'try' : 'tries'} left.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _useBiometric() async {
    if (_checking || _isLockedOut) return;
    setState(() => _checking = true);
    try {
      final ok = await widget.pinLock.authenticateWithBiometrics(
        reason: 'Unlock KeepIt',
      );
      if (!mounted) return;
      if (ok) {
        widget.onUnlock();
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showForgotPin() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot your PIN?'),
        content: const Text(
          'Your PIN is only stored on this device, so it cannot be recovered '
          'or reset by anyone — not even us. Your data stays safely on the '
          'device.\n\n'
          'To get back in, reinstall the app and restore from a backup you '
          'exported earlier. Anything added since that backup will be lost.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'KeepIt is locked',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your PIN to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  PinPad(
                    key: _pinPadKey,
                    onSubmitted: _submit,
                    actionLabel: 'Unlock',
                    showBiometricButton: _biometricOffered,
                    onBiometric: _useBiometric,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _showForgotPin,
                    child: const Text('Forgot PIN?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
