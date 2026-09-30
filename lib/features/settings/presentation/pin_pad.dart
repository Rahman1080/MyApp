import 'package:flutter/material.dart';

/// A numeric keypad for entering a 4–8 digit PIN. The PIN itself never leaves
/// this widget except through [onSubmitted]; nothing is logged or stored.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmitted,
    this.actionLabel = 'Continue',
    this.showBiometricButton = false,
    this.onBiometric,
  });

  final ValueChanged<String> onSubmitted;
  final String actionLabel;
  final bool showBiometricButton;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  static const maxLength = 8;
  static const minLength = 4;

  String _pin = '';

  /// Clears the entered digits, e.g. after a failed attempt.
  void reset() => setState(() => _pin = '');

  void _addDigit(String digit) {
    if (_pin.length >= maxLength) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress dots.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(maxLength, (i) {
            final filled = i < _pin.length;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        // Keypad.
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            for (var d = 1; d <= 9; d++) _Key(label: '$d', onTap: () => _addDigit('$d')),
            widget.showBiometricButton
                ? _Key(
                    icon: Icons.fingerprint,
                    onTap: widget.onBiometric,
                    semanticLabel: 'Use biometrics',
                  )
                : const SizedBox.shrink(),
            _Key(label: '0', onTap: () => _addDigit('0')),
            _Key(
              icon: Icons.backspace_outlined,
              onTap: _backspace,
              semanticLabel: 'Delete digit',
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _pin.length >= minLength
              ? () => widget.onSubmitted(_pin)
              : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap, this.semanticLabel});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Center(
        child: icon != null
            ? Semantics(
                label: semanticLabel ?? 'Key',
                button: true,
                child: Icon(icon, size: 28),
              )
            : Text(
                label ?? '',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
      ),
    );
  }
}
