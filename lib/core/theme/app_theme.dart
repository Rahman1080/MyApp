import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 themes for KeepIt (light + dark).
///
/// Accessibility notes:
/// - Minimum touch target of 48dp is enforced through the component themes
///   below ([ElevatedButton], [TextButton], [OutlinedButton], [IconButton]).
/// - Text uses the Material 3 type scale; body text never goes below 14sp.
abstract final class AppTheme {
  static const double minTouchTarget = 48;

  static ThemeData get light => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
      );

  static ThemeData get dark => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    const buttonMinSize = Size(AppTheme.minTouchTarget, AppTheme.minTouchTarget);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: scheme.onSurface),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: buttonMinSize),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonMinSize),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: buttonMinSize),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: buttonMinSize),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            AppTheme.minTouchTarget,
            AppTheme.minTouchTarget,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        // FABs are 56dp by spec; keep them but never shrink below that.
        smallSizeConstraints: BoxConstraints.tightFor(width: 48, height: 48),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      textTheme: _accessibleTextTheme(scheme),
    );
  }

  /// Material 3 type scale with a slightly raised floor for readability.
  static TextTheme _accessibleTextTheme(ColorScheme scheme) {
    final base = scheme.brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    return base.copyWith(
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(fontSize: 14, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(fontSize: 15),
    );
  }
}
