import 'package:flutter/material.dart';

/// 프로젝트의 `DESIGN.md` 문서에서 그대로 옮겨 적은 원본(raw) 색상
/// 토큰 모음. `DESIGN.md`는 앱 자산(asset)이 아니라 정적인 참고 문서이기
/// 때문에, 런타임에 파싱하는 대신 순수 상수로 유지한다. `app_theme.dart`
/// 의 `themeDataFor`/`_buildTheme`이 이 색상들을 조합해 실제
/// `ThemeData`(라이트/다크 두 테마)를 만든다.
abstract final class DesignColors {
  static const primary = Color(0xFF5645D4);
  static const primaryPressed = Color(0xFF4534B3);
  static const primaryDeep = Color(0xFF3A2A99);
  static const onPrimary = Color(0xFFFFFFFF);

  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF6F5F4);
  static const surfaceSoft = Color(0xFFFAFAF9);

  /// `ReviewScreen`에만 쓰이는 배경색(white 테마) — `canvas`보다 어둡게
  /// 잡아, 지금 복습 중인지 학습 중인지 배경만으로 구분되게 한다. 최초
  /// 버전(`#F0EFEC`)은 `canvas`와의 차이가 거의 느껴지지 않는다는 피드백을
  /// 받아, `hairline`(#E5E3DF, 1px 테두리색)에 가까운 톤까지 한 단계 더
  /// 어둡게 내렸다 — `surface`(#F6F5F4, 카드/입력창 배경)보다는 여전히
  /// 확실히 어두워서 카드가 배경에 묻히지 않는다.
  static const reviewBackgroundLight = Color(0xFFE9E7E3);

  /// `ReviewScreen`에만 쓰이는 배경색(black 테마) — `inkDeep`(순검정,
  /// #000000)보다 밝게 잡아 구분되게 한다. 최초 버전(`#121212`)은
  /// `inkDeep`과의 차이가 거의 느껴지지 않는다는 피드백을 받아, 카드에
  /// 쓰이는 `ink`(#1A1A1A)와 거의 같은 밝기까지 한 단계 더 올렸다 — 순검정
  /// 대비 체감 차이를 카드 밝기 수준까지 끌어올리는 것을 우선했고, 그
  /// 결과 카드가 배경보다 아주 살짝만 더 밝거나 사실상 비슷해져 이전만큼
  /// "카드가 도드라져 보이는" 효과는 약해졌다(실사용 확인 필요).
  static const reviewBackgroundDark = Color(0xFF1C1C1C);

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

/// 모서리 둥글기(border radius) 값 토큰 모음. 카드, 버튼, 입력창, 다이얼로그
/// 등에서 일관된 둥글기를 쓰기 위해 `app_theme.dart`의 `_buildTheme`과
/// 여러 화면/위젯(`word_lookup_box.dart`, `sentence_analysis_box.dart`,
/// `mixed_language_box.dart`, `feedback_box.dart`,
/// `listening_history_screen.dart` 등)에서 참조한다.
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

/// 여백/간격(padding, margin, gap) 값 토큰 모음. 화면과 위젯 전반에서
/// 일관된 spacing을 위해 `app_theme.dart`의 `_buildTheme`(입력창/버튼
/// padding)과 여러 화면/위젯에서 참조한다.
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

/// 앱 전체에서 사용하는 기본 폰트 패밀리 이름. `app_theme.dart`의
/// `_buildTheme`이 `ThemeData.fontFamily`와 각 텍스트 스타일에 이 값을
/// 적용해, 앱 전체 텍스트가 동일한 폰트를 쓰도록 한다.
const designFontFamily = 'Notion Sans';
