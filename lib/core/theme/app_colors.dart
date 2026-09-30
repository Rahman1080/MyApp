import 'package:flutter/material.dart';

/// Brand palette for KeepIt.
///
/// Trustworthy teal/green tones. Solid colors only — no gradients anywhere
/// in the app.
abstract final class AppColors {
  /// Primary brand color (teal).
  static const Color primary = Color(0xFF0E7C6B);

  /// Darker variant used for pressed states and dark surfaces.
  static const Color primaryDark = Color(0xFF0A5A4E);

  /// Soft tinted surface for highlights and selected states (light theme).
  static const Color primaryContainerLight = Color(0xFFD9EFE9);

  /// Urgency colors. Used sparingly and never as full-screen alarms.
  static const Color warning = Color(0xFFB7791F);
  static const Color urgent = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D32);
}
