import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The app's two themes. Persisted in config.json as `'white'` / `'black'`.
enum AppThemeMode {
  white,
  black;

  static AppThemeMode fromConfigValue(String value) {
    return value == 'white' ? AppThemeMode.white : AppThemeMode.black;
  }

  String get configValue => name;
}

ThemeData themeDataFor(AppThemeMode mode) {
  return switch (mode) {
    AppThemeMode.white => _buildTheme(
        brightness: Brightness.light,
        scaffoldBackground: DesignColors.canvas,
        surface: DesignColors.canvas,
        surfaceVariant: DesignColors.surface,
        onSurface: DesignColors.ink,
        onSurfaceMuted: DesignColors.slate,
        outline: DesignColors.hairline,
        outlineStrong: DesignColors.hairlineStrong,
      ),
    AppThemeMode.black => _buildTheme(
        brightness: Brightness.dark,
        scaffoldBackground: DesignColors.inkDeep,
        surface: DesignColors.ink,
        surfaceVariant: DesignColors.charcoal,
        onSurface: DesignColors.onDark,
        onSurfaceMuted: DesignColors.onDarkMuted,
        outline: DesignColors.steel,
        outlineStrong: DesignColors.stone,
      ),
  };
}

ThemeData _buildTheme({
  required Brightness brightness,
  required Color scaffoldBackground,
  required Color surface,
  required Color surfaceVariant,
  required Color onSurface,
  required Color onSurfaceMuted,
  required Color outline,
  required Color outlineStrong,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: DesignColors.primary,
    brightness: brightness,
  ).copyWith(
    primary: DesignColors.primary,
    onPrimary: DesignColors.onPrimary,
    error: DesignColors.semanticError,
    onError: DesignColors.onPrimary,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: surfaceVariant,
    onSurfaceVariant: onSurfaceMuted,
    outline: outline,
    outlineVariant: outlineStrong,
  );

  final borderRadius = BorderRadius.circular(DesignRadii.md);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: designFontFamily,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBackground,
      foregroundColor: onSurface,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignRadii.lg),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignSpacing.md,
        vertical: DesignSpacing.sm,
      ),
      border: OutlineInputBorder(borderRadius: borderRadius, borderSide: BorderSide(color: outline)),
      enabledBorder:
          OutlineInputBorder(borderRadius: borderRadius, borderSide: BorderSide(color: outline)),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DesignColors.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DesignColors.primary,
        foregroundColor: DesignColors.onPrimary,
        disabledBackgroundColor: outline,
        disabledForegroundColor: onSurfaceMuted,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        textStyle: const TextStyle(
          fontFamily: designFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: BorderSide(color: outlineStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        textStyle: const TextStyle(
          fontFamily: designFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DesignColors.primary,
        textStyle: const TextStyle(
          fontFamily: designFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignRadii.lg)),
    ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.30,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.40,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.50,
        color: onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: designFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.40,
        color: onSurfaceMuted,
      ),
    ),
  );
}
