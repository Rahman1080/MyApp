import 'package:flutter/material.dart';

/// Small colored pill showing a purchase or refund status.
///
/// Purchase statuses: active, returned, refunded, exchanged.
/// Refund statuses: requested, pending, received.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  static const Map<String, (String, Color)> _purchaseStyles = {
    'active': ('Active', Color(0xFF1B7A4D)),
    'returned': ('Returned', Color(0xFF8A6D00)),
    'refunded': ('Refunded', Color(0xFF0B6E99)),
    'exchanged': ('Exchanged', Color(0xFF6A4FB3)),
  };

  static const Map<String, (String, Color)> _refundStyles = {
    'requested': ('Requested', Color(0xFF8A6D00)),
    'pending': ('Pending', Color(0xFFB25E09)),
    'received': ('Received', Color(0xFF1B7A4D)),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _purchaseStyles[status] ?? _refundStyles[status];
    final label = style?.$1 ?? status;
    final base = style?.$2 ?? scheme.onSurfaceVariant;

    final background = Color.alphaBlend(base.withAlpha(36), scheme.surface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: base,
              fontWeight: FontWeight.w700,
            ),
        semanticsLabel: 'Status: $label',
      ),
    );
  }
}
