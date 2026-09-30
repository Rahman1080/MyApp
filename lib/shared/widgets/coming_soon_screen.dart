import 'package:flutter/material.dart';

import 'empty_state.dart';

/// Honest placeholder for features scheduled for a later phase.
///
/// Used instead of a dead button or a fake screen: it says exactly what the
/// feature is and when it lands. No mock functionality.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.message,
  });

  static const String routePath = '/coming-soon';

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyState(
        icon: Icons.upcoming_outlined,
        headline: 'Coming soon',
        body: message,
      ),
    );
  }
}
