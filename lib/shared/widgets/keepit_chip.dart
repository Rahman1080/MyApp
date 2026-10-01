import 'package:flutter/material.dart';

/// Pill-style filter and action chip for KeepIt.
///
/// Features:
/// - Full-pill 999dp corner radius
/// - Subtle borders in inactive state
/// - Soft mint/teal tint when selected
/// - Compact touch-friendly height
class KeepitFilterChip extends StatelessWidget {
  const KeepitFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg = isDark
        ? const Color(0xFF1B3D37)
        : theme.colorScheme.primaryContainer;
    final selectedText = isDark
        ? const Color(0xFF2DD4BF)
        : theme.colorScheme.primary;

    return ChoiceChip(
      avatar: icon != null
          ? Icon(
              icon,
              size: 16,
              color: selected
                  ? selectedText
                  : theme.colorScheme.onSurfaceVariant,
            )
          : null,
      label: Text(
        count == null ? label : '$label ($count)',
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected
              ? selectedText
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: selectedBg,
      backgroundColor: theme.colorScheme.surface,
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected
              ? (isDark ? const Color(0xFF2DD4BF).withAlpha(120) : theme.colorScheme.primary)
              : theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }
}
