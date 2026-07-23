import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 이 앱이 지원하는 두 가지 테마. `config.json`에 `'white'` / `'black'`
/// 문자열로 저장/영속화된다. `ThemeModeViewModel`이 `config.json`을 읽어
/// 현재 값을 노출하고, `ApiKeyScreen`과 `SettingsDialog`의 테마 선택
/// `SegmentedButton`이 이 두 값을 옵션으로 보여준다.
enum AppThemeMode {
  /// 밝은 배경의 테마.
  white,

  /// 어두운 배경의 테마. `config.json`에 아직 `themeMode` 필드가 없는
  /// 신규 사용자에게 적용되는 기본값이기도 하다
  /// (`ThemeModeViewModel` 참고).
  black;

  /// `config.json`에 저장된 문자열 [value]를 [AppThemeMode]로 되돌린다.
  /// `'white'`가 아니면 무조건 [AppThemeMode.black]으로 취급한다(값이
  /// 없거나 손상된 경우에도 안전하게 동작하도록). `ThemeModeViewModel`이
  /// 설정을 읽을 때, `SettingsDialog`가 초기 선택값을 정할 때 사용한다.
  static AppThemeMode fromConfigValue(String value) {
    return value == 'white' ? AppThemeMode.white : AppThemeMode.black;
  }

  /// `config.json`에 그대로 저장할 문자열 값(enum의 이름, 즉 `'white'`
  /// 또는 `'black'`). `SettingsViewModel`이 테마를 변경할 때 이 값을
  /// 기록한다.
  String get configValue => name;
}

/// 주어진 [mode]에 대응하는 `ThemeData`를 만들어 반환한다.
/// `main.dart`의 `MyApp`이 `MaterialApp.router`의 `theme`에 이 함수의
/// 결과를 전달해 앱 전체 테마를 적용한다. 실제 팔레트/스타일 구성은
/// [_buildTheme]에 위임한다.
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

/// [themeDataFor]가 white/black 두 모드 각각에 맞는 색상 값들을 넘겨
/// 실제 `ThemeData`(색상 scheme, AppBar/Card/입력창/버튼/다이얼로그/
/// 텍스트 스타일 등)를 조립하는 내부 헬퍼. `design_tokens.dart`의
/// `DesignColors`/`DesignRadii`/`DesignSpacing`/`designFontFamily`를
/// 기반으로 Material 3 `ColorScheme`과 각 위젯 테마를 구성한다.
///
/// [brightness]는 밝기(light/dark), [scaffoldBackground]는 화면 배경색,
/// [surface]/[surfaceVariant]는 카드·입력창 등에 쓰이는 표면 색,
/// [onSurface]/[onSurfaceMuted]는 표면 위 텍스트 색(기본/보조),
/// [outline]/[outlineStrong]은 테두리 색(기본/강조)을 의미한다.
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
