import 'package:flutter/material.dart';

/// Brand palette for KeepIt.
///
/// Trustworthy teal/green tones with a dark minimalist foundation.
/// Solid colors only — no gradients anywhere in the app.
abstract final class AppColors {
  /// Primary brand color (teal).
  static const Color primary = Color(0xFF0E7C6B);

  /// Mint / teal primary accent for dark mode highlights and badges.
  static const Color mintAccent = Color(0xFF14B8A6);

  /// Mint highlight light tone for dark-mode subtle icon containers.
  static const Color mintHighlight = Color(0xFF2DD4BF);

  /// Darker variant used for pressed states and dark surfaces.
  static const Color primaryDark = Color(0xFF0A5A4E);

  /// Soft tinted surface for highlights and selected states (light theme).
  static const Color primaryContainerLight = Color(0xFFD9EFE9);

  /// Dark mode palette (near-black, minimalist, thin understated borders).
  static const Color darkBackground = Color(0xFF111413);
  static const Color darkSurface = Color(0xFF181D1C);
  static const Color darkSurfaceRaised = Color(0xFF202725);
  static const Color darkBorder = Color(0xFF28322F);
  static const Color darkTextPrimary = Color(0xFFF3F7F6);
  static const Color darkTextSecondary = Color(0xFF94A3A0);
  static const Color darkTextMuted = Color(0xFF637370);

  /// Light mode palette.
  static const Color lightBackground = Color(0xFFF6F8F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFF0F4F2);
  static const Color lightBorder = Color(0xFFE0E7E5);
  static const Color lightTextPrimary = Color(0xFF111817);
  static const Color lightTextSecondary = Color(0xFF5A6966);
  static const Color lightTextMuted = Color(0xFF8A9A97);

  /// Urgency colors. Used sparingly and never as full-screen alarms.
  static const Color warning = Color(0xFFB7791F);
  static const Color urgent = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D32);
}
