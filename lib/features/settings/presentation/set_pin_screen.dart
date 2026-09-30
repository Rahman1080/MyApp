import 'package:flutter/material.dart';

import '../../settings/data/settings_repository.dart';
import 'pin_pad.dart';
import '../../../core/security/pin_lock_service.dart';

/// The PIN mode this screen operates in. The route takes `?mode=` with one
/// of `setup`, `change` (default), or `remove`.
enum SetPinMode { setup, change, remove }

/// Set, change, or remove the app-lock PIN.
///
/// - setup: enter new PIN → confirm → saved, app lock enabled.
/// - change: verify current PIN → enter new → confirm.
/// - remove: verify current PIN → PIN cleared, app lock disabled.
///
/// Returns `true` when the PIN was successfully saved or removed, so the
/// Settings screen can refresh and confirm.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({
    super.key,
    required this.pinLock,
    required this.settingsRepository,
    required this.initialMode,
  });

  final PinLockService pinLock;
  final SettingsRepository settingsRepository;
  final SetPinMode initialMode;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _pinPadKey = GlobalKey<PinPadState>();

  /// 0 = verify current PIN (change/remove only), 1 = enter new, 2 = confirm.
  late int _step = widget.initialMode == SetPinMode.setup ? 1 : 0;
  String? _firstPin;
  String? _error;
  bool _saving = false;

  String get _title => switch (widget.initialMode) {
        SetPinMode.setup => 'Set app lock PIN',
        SetPinMode.change => 'Change PIN',
        SetPinMode.remove => 'Remove PIN',
      };

  String get _prompt => switch (_step) {
        0 => 'Enter your current PIN',
        1 => 'Choose a ${PinPadState.minLength}–${PinPadState.maxLength} digit PIN',
        _ => 'Confirm your new PIN',
      };

  Future<void> _submit(String pin) async {
    if (_saving) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      if (_step == 0) {
        final ok = await widget.pinLock.verifyPin(pin);
        if (!mounted) return;
        if (!ok) {
          _pinPadKey.currentState?.reset();
          setState(() => _error = 'Wrong PIN. Try again.');
          return;
        }
        if (widget.initialMode == SetPinMode.remove) {
          await widget.pinLock.clearPin();
          await widget.settingsRepository.setAppLockEnabled(false);
          await widget.settingsRepository.setBiometricUnlockEnabled(false);
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        setState(() => _step = 1);
        _pinPadKey.currentState?.reset();
      } else if (_step == 1) {
        setState(() {
          _firstPin = pin;
          _step = 2;
        });
        _pinPadKey.currentState?.reset();
      } else {
        if (pin != _firstPin) {
          _pinPadKey.currentState?.reset();
          setState(() {
            _error = 'PINs do not match. Start over.';
            _step = 1;
            _firstPin = null;
          });
          return;
        }
        await widget.pinLock.setPin(pin);
        await widget.settingsRepository.setAppLockEnabled(true);
        if (mounted) Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _prompt,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your PIN is stored only on this device as a salted '
                    'hash — never the digits themselves.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  PinPad(
                    key: _pinPadKey,
                    onSubmitted: _submit,
                    actionLabel: switch (_step) {
                      0 => 'Verify',
                      1 => 'Continue',
                      _ => 'Save PIN',
                    },
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
