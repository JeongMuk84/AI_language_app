import 'package:flutter/material.dart';

/// Raw design tokens transcribed from the project's `DESIGN.md`. Kept as
/// plain constants (rather than parsed at runtime) since `DESIGN.md` is a
/// static reference document, not an app asset.
abstract final class DesignColors {
  static const primary = Color(0xFF5645D4);
  static const primaryPressed = Color(0xFF4534B3);
  static const primaryDeep = Color(0xFF3A2A99);
  static const onPrimary = Color(0xFFFFFFFF);

  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF6F5F4);
  static const surfaceSoft = Color(0xFFFAFAF9);
  static const hairline = Color(0xFFE5E3DF);
  static const hairlineSoft = Color(0xFFEDE9E4);
  static const hairlineStrong = Color(0xFFC8C4BE);

  static const inkDeep = Color(0xFF000000);
  static const ink = Color(0xFF1A1A1A);
  static const charcoal = Color(0xFF37352F);
  static const slate = Color(0xFF5D5B54);
  static const steel = Color(0xFF787671);
  static const stone = Color(0xFFA4A097);
  static const muted = Color(0xFFBBB8B1);

  static const onDark = Color(0xFFFFFFFF);
  static const onDarkMuted = Color(0xFFA4A097);

  static const semanticSuccess = Color(0xFF1AAE39);
  static const semanticWarning = Color(0xFFDD5B00);
  static const semanticError = Color(0xFFE03131);
}

abstract final class DesignRadii {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const xxl = 20.0;
  static const xxxl = 24.0;
  static const full = 9999.0;
}

abstract final class DesignSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
}

const designFontFamily = 'Notion Sans';
