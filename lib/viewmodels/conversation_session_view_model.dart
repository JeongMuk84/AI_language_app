import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gemini_message.dart';

/// 현재 학습 세션 동안 주고받은 Gemini 대화 기록을 담는 State 클래스.
class ConversationSessionState {
  const ConversationSessionState({this.history = const []});

  /// 지금까지 주고받은 [GeminiMessage] 목록. Gemini는 요청 사이에 아무것도
  /// 기억하지 못하므로, 매 요청마다 이 리스트를 함께 다시 보내 문맥을
  /// 유지한다.
  final List<GeminiMessage> history;
}

/// 현재 학습 세션의 멀티턴 대화 기록(local)을 들고 있는 뷰모델. Gemini는
/// 요청과 요청 사이에 아무것도 기억하지 못하므로 — 이 리스트가 매번 다시
/// 전송해서 문맥을 유지시켜주는 대상이다 — 그래서 [reset](비우기)이 곧 여기서
/// "대화를 잊는다"는 의미가 된다.
class ConversationSessionViewModel extends Notifier<ConversationSessionState> {
  /// 빈 history로 초기 상태를 만든다.
  @override
  ConversationSessionState build() => const ConversationSessionState();

  /// [state.history] 끝에 [message] 하나를 덧붙인 새 상태로 갱신한다.
  void addMessage(GeminiMessage message) {
    state = ConversationSessionState(history: [...state.history, message]);
  }

  /// history를 완전히 비운다. SettingsViewModel.save에서 학습 언어(target
  /// language)를 바꿀 때 호출되어, 이전 언어의 대화 문맥이 새 언어 세션으로
  /// 넘어가지 않도록 한다("대화를 잊는다"는 것은 곧 이 리스트를 비우는 것을
  /// 의미한다).
  void reset() {
    state = const ConversationSessionState();
  }

  /// handoff 요약([contextSummary])을 기존 문맥인 것처럼 새 세션에 심어준다.
  /// 이전에 학습했던 언어로 다시 돌아왔을 때(handoff 파일이 존재하는 경우),
  /// AppRouter의 redirect 로직이 이 메서드를 호출해 대화를 완전히 새로 시작하는
  /// 대신 이전 요약에서부터 이어가도록 한다.
  void seedWithContext(String contextSummary) {
    state = ConversationSessionState(
      history: [GeminiMessage(role: 'model', text: contextSummary)],
    );
  }
}

/// [ConversationSessionViewModel]/[ConversationSessionState]를 노출하는
/// provider. AppRouter의 redirect 로직(`_resolveLearningEntryRoute` 진입 전
/// handoff 처리 부분)에서 `seedWithContext`를 호출하고, SettingsViewModel에서
/// `history`를 읽어 handoff 요약을 생성한 뒤 `reset()`으로 비운다.
final conversationSessionProvider =
    NotifierProvider<ConversationSessionViewModel, ConversationSessionState>(
  ConversationSessionViewModel.new,
);
