import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import 'restart_widget.dart';

/// Gemini 호출 로드 에러 화면(예: 만료/거부된 키, 또는 rate limit에 걸려
/// 멈춘 키)에서 "Retry"와 나란히 표시되는 복구 액션 — LevelTestScreen,
/// WritingScreen, ShadowingDictationScreen, ReviewScreen의 에러 화면에서
/// 쓰인다. 저장된 Gemini API 키를 지우고 앱을 재시작하여, 라우터의
/// 온보딩 리다이렉트(`app_router.dart` 참고)가 새 키 입력을 위해
/// [ApiKeyScreen]으로 다시 돌아가게 한다. config.json, history, review
/// history, TTS 캐시는 그대로 유지된다 — 새 키를 입력하고 나면 언어/레벨은
/// 이미 설정되어 있으므로, 온보딩은 language-select/level-test를
/// 건너뛴다. 다만 아래에 설명하듯 진행 중이던 학습 세션과 오늘의 문장
/// 세트는 함께 비워지므로, 학습 쪽은 곧바로 이전 지점으로 돌아가지 않고
/// [TopicInputDialog]를 다시 거쳐 새로 시작된다(복습은 영향받지 않는다).
///
/// [HoldToResetButton]이 아니라 의도적으로 단순한 한 번 탭 버튼이다 —
/// "Reset All Data"와 달리 여기서 파괴되는 것 중 즉시 다시 입력해서 복구할
/// 수 없는 것은 없으므로, 홀드 확인 안전장치까지는 필요 없다. 그래도
/// 에러 톤(채워진 버튼이 아니라 아웃라인 버튼)으로 스타일링되어, "Retry"
/// 같은 일상적인 액션보다는 한 단계 아래로 보이면서도 완전히 파괴적인
/// 액션만큼의 경고감은 주지 않는다.
///
/// API 키 삭제·재시작에 더해:
/// - 오늘의 `dailyTurnCount`를 0으로 되돌린다 — 새 프로젝트의 키는 새로운
///   TTS 할당량을 의미하므로, 로컬에 남아있는 "오늘 몇 턴 했음" 카운트를
///   그대로 두면 새 키로도 곧바로 다시 한도에 걸린 것처럼 보일 수 있다.
/// - 오늘 미리 생성해둔 10문장 세트(`sentence_queue.json`)와 진행 중이던
///   학습 세션(`session_state.json` — 현재 문장/turn/하위 단계 등)을 함께
///   비운다. 태평양 날짜가 아직 바뀌지 않은 상태로 키를 재발급하는 경우가
///   흔한데(예: 하루 중간에 TTS 할당량 초과), 이 둘을 비우지 않으면
///   라우터가 날짜만 보고 "오늘 세션이 아직 있다"고 판단해 `/learning`을
///   거치지 않고 곧장 이전 화면으로 재개해버려 — 결과적으로 오늘 세트가
///   그대로 재사용되고 [TopicInputDialog]가 다시는 뜨지 않는다. 세션
///   상태까지 지워야 라우터가 `/learning`으로 다시 진입하고,
///   `startNextLearningInteractive`가 "오늘 세트 없음"을 감지해
///   [TopicInputDialog]를 다시 띄운다(`topic_input_dialog.dart` 참고).
/// - `reviewedToday`(및 진행 중인 review)는 건드리지 않는다 — 복습은 TTS
///   할당량과 무관하므로 그대로 유지한다.
class ResetApiKeyButton extends ConsumerWidget {
  /// 파라미터 없이 위젯을 구성하는 생성자.
  const ResetApiKeyButton({super.key});

  /// 저장된 API 키를 지우고, 오늘의 학습 turn 카운터·문장 세트·진행 중이던
  /// 학습 세션을 리셋한 뒤 앱을 재시작한다. 부작용: `apiKeyStorageServiceProvider`를
  /// 통해 키를 삭제하고, `sessionStateServiceProvider`를 통해
  /// `daily_progress.json`/`sentence_queue.json`/`session_state.json`을
  /// 지우며, [RestartWidget.restartApp]으로 전체 위젯 트리(및 모든
  /// provider)를 재생성한다. `review_progress.json`/
  /// `review_completed_today.json`은 건드리지 않는다.
  Future<void> _resetApiKey(BuildContext context, WidgetRef ref) async {
    final sessionStateService = ref.read(sessionStateServiceProvider);
    await ref.read(apiKeyStorageServiceProvider).clearApiKey();
    await sessionStateService.clearDailyProgress();
    // 오늘 세트와 진행 중이던 세션을 함께 비워야, 재시작 후 라우터가
    // "오늘 세션이 아직 있다"며 이전 학습 화면으로 곧장 재개하지 않고
    // `/learning`을 거쳐 TopicInputDialog로 다시 진입한다(클래스 문서 참고).
    await sessionStateService.clearSentenceQueue();
    await sessionStateService.clearSession();
    if (!context.mounted) return;
    RestartWidget.restartApp(context);
  }

  /// 에러 톤으로 스타일링된 "Reset API Key" `OutlinedButton`을 그리며,
  /// 탭하면 [_resetApiKey]를 호출한다.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.error,
        side: BorderSide(color: colorScheme.error),
      ),
      onPressed: () => _resetApiKey(context, ref),
      child: const Text('Reset API Key'),
    );
  }
}
