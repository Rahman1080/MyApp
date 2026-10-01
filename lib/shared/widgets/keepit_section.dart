import 'package:flutter/material.dart';

/// Reusable section title for KeepIt screens.
///
/// Provides consistent typography, spacing, and optional action link
/// (e.g. "See all" or "Edit").
class KeepitSection extends StatelessWidget {
  const KeepitSection({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget? actionWidget = trailing;
    if (actionWidget == null && actionLabel != null) {
      actionWidget = TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(actionLabel!),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              letterSpacing: -0.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          ?actionWidget,
        ],
      ),
    );
  }
}
