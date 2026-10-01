import 'package:flutter/material.dart';

/// Reusable search bar adhering to KeepIt's minimalist aesthetic.
///
/// Features:
/// - Rounded 12dp border matching theme input decoration
/// - Clear button when text is present
/// - Optional debounce or on-change callback
/// - Clean dark / light surface contrast
class KeepitSearchBar extends StatefulWidget {
  const KeepitSearchBar({
    super.key,
    this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  @override
  State<KeepitSearchBar> createState() => _KeepitSearchBarState();
}

class _KeepitSearchBarState extends State<KeepitSearchBar> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_handleTextChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: widget.padding,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
