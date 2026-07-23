import 'package:flutter/material.dart';

import 'dictionary_icon_button.dart';
import 'listening_history_icon_button.dart';
import 'settings_icon_button.dart';

/// ApiKeyScreen을 제외한 모든 화면(LevelTestScreen, LanguageSelectScreen,
/// WritingScreen, ShadowingDictationScreen, ShadowingPronunciationScreen,
/// WritingListeningScreen, ReviewScreen 등)에서 공통으로 사용하는 표준 AppBar
/// 형태를 만든다: 제목과 함께 공용 [ListeningHistoryIconButton],
/// [DictionaryIconButton], [SettingsIconButton] 액션을 붙여준다.
/// `AppBar(actions: [ListeningHistoryIconButton(), DictionaryIconButton(), SettingsIconButton()])`
/// 를 직접 손으로 작성하는 대신 이 함수를 사용해야, 모든 화면에서 이 버튼들의
/// 모양과 동작이 항상 동일하게 유지된다.
///
/// [progressLabel]이 주어지면(예: "Today: 3/10") title 왼쪽에 단순한 `Text`
/// 액션 하나로 표시된다 — 여러 줄짜리 `title` `Column`으로 접어 넣지 않는다.
/// 이 화면 자신의 route 전환 도중 새로 mount되는, 자체 parentData를 가진
/// 위젯(`Column` 같은)은 실제로 Flutter 프레임워크의
/// `!semantics.parentDataDirty` 버그를 유발한 적이 있다(`HoldToResetButton`의
/// 히스토리 참고) — 단순 `Text` 하나만 쓰면 이 위험을 완전히 피할 수 있다.
AppBar buildAppBarWithSettings(BuildContext context, String title, {String? progressLabel}) {
  return AppBar(
    title: Text(title),
    actions: [
      if (progressLabel != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(progressLabel, style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      const ListeningHistoryIconButton(),
      const DictionaryIconButton(),
      const SettingsIconButton(),
    ],
  );
}
