import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 themes for KeepIt (light + dark).
///
/// Refined dark minimalist design system:
/// - Near-black background with subtle surface elevation
/// - Thin, understated borders (1dp outline) with zero artificial card drop-shadows
/// - Crisp mint / teal primary accent
/// - Minimum touch target of 48dp enforced across clickable components
/// - Text uses the Material 3 type scale with raised floor for readability
abstract final class AppTheme {
  static const double minTouchTarget = 48;

  static ThemeData get light => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.lightSurface,
          onSurface: AppColors.lightTextPrimary,
          outline: AppColors.lightBorder,
          outlineVariant: AppColors.lightBorder,
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryContainerLight,
          surfaceContainerHighest: AppColors.lightSurfaceRaised,
        ),
        isDark: false,
      );

  static ThemeData get dark => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkTextPrimary,
          outline: AppColors.darkBorder,
          outlineVariant: AppColors.darkBorder,
          primary: AppColors.mintAccent,
          primaryContainer: const Color(0xFF183B34),
          onPrimaryContainer: AppColors.mintHighlight,
          surfaceContainerHighest: AppColors.darkSurfaceRaised,
        ),
        isDark: true,
      );

  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    const buttonMinSize = Size(AppTheme.minTouchTarget, AppTheme.minTouchTarget);
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.lightBackground;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scaffoldBg,
        elevation: 0,
        indicatorColor: isDark
            ? AppColors.mintAccent.withAlpha(36)
            : AppColors.primaryContainerLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? (isDark ? AppColors.mintAccent : AppColors.primary)
                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonMinSize,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinSize,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinSize,
          side: BorderSide(color: borderColor, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: buttonMinSize,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppTheme.minTouchTarget, AppTheme.minTouchTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? AppColors.mintAccent : AppColors.primary,
        foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        smallSizeConstraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceColor,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceRaised : AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceRaised : AppColors.lightSurface,
        modalBackgroundColor: isDark ? AppColors.darkSurfaceRaised : AppColors.lightSurface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: borderColor, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.mintAccent : AppColors.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceRaised : const Color(0xFF2C3432),
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.darkTextPrimary : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
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
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
      bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
}
