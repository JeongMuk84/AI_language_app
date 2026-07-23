import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [ShadowingViewModel](ShadowingPronunciationScreen)과
/// [WritingViewModel](WritingListeningScreen)이 공유하는 "문장을 가렸다가
/// 다시 보여주기" 토글 동작을 담은 mixin이다. 두 화면 모두 학습자가 문장을
/// 먼저 읽지 않고 발음을 시도해볼 수 있게 해준다. 문장을 가릴 때는 항상 새로운
/// 발음 시도로 취급하지만, 다시 보이게 할 때는 기존 시도를 건드리지 않는다.
mixin SentenceHiddenToggleMixin<S> on Notifier<S> {
  /// 주어진 [state]에서 현재 문장이 가려져 있는지(`sentenceHidden`)를
  /// 꺼내온다. 각 뷰모델(ShadowingViewModel/WritingViewModel)이 자신의
  /// State 클래스에 맞게 구현한다.
  bool sentenceHiddenOf(S state);

  /// [state]를 복사하되 `sentenceHidden`을 [hidden]으로 바꾸고, [hidden]이
  /// true일 때만 발음 분석 시도(결과 + 에러)를 초기화한 새 State를 반환한다.
  S copyWithSentenceHidden(S state, {required bool hidden});

  /// ShadowingPronunciationScreen/WritingListeningScreen의 문장 숨김/보이기
  /// 버튼이 눌리면 호출되어 현재 숨김 상태를 반전시킨다. 문장을 새로 숨길
  /// 때는 [copyWithSentenceHidden]을 통해 이전 발음 분석 시도가 함께
  /// 초기화되어, 문장을 다시 가리면 항상 새로운 발음 시도로 취급된다.
  void toggleSentenceHidden() {
    final hidden = sentenceHiddenOf(state);
    state = copyWithSentenceHidden(state, hidden: !hidden);
  }
}
