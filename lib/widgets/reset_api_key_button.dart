import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import 'restart_widget.dart';

/// Gemini 호출 로드 에러 화면(예: 만료/거부된 키, 또는 rate limit에 걸려
/// 멈춘 키)에서 "Retry"와 나란히 표시되는 복구 액션 — LevelTestScreen,
/// WritingScreen, ShadowingDictationScreen, ReviewScreen의 에러 화면에서
/// 쓰인다. 저장된 Gemini API 키만 지우고 앱을 재시작하여, 라우터의
/// 온보딩 리다이렉트(`app_router.dart` 참고)가 새 키 입력을 위해
/// [ApiKeyScreen]으로 다시 돌아가게 한다. 그 외의 모든 것(config.json,
/// 세션 상태, history, review history, TTS 캐시)은 그대로 유지된다 — 새
/// 키를 입력하고 나면 언어/레벨은 이미 설정되어 있으므로, 온보딩은
/// language-select/level-test를 건너뛰고 학습자가 있던 학습/복습 지점으로
/// 곧바로 돌아간다.
///
/// [HoldToResetButton]이 아니라 의도적으로 단순한 한 번 탭 버튼이다 —
/// "Reset All Data"와 달리 여기서 파괴되는 것 중 즉시 다시 입력해서 복구할
/// 수 없는 것은 없으므로, 홀드 확인 안전장치까지는 필요 없다. 그래도
/// 에러 톤(채워진 버튼이 아니라 아웃라인 버튼)으로 스타일링되어, "Retry"
/// 같은 일상적인 액션보다는 한 단계 아래로 보이면서도 완전히 파괴적인
/// 액션만큼의 경고감은 주지 않는다.
///
/// API 키 삭제·재시작에 더해, 오늘의 `dailyTurnCount`도 함께 풀어준다 —
/// 새 프로젝트의 키는 새로운 TTS 할당량을 의미하므로, 로컬에 남아있는
/// "오늘 몇 턴 했음" 카운트를 그대로 두면 새 키로도 곧바로 다시 한도에
/// 걸린 것처럼 보일 수 있다. `reviewedToday`는 건드리지 않는다 — 복습은
/// TTS 할당량과 무관하므로 그대로 유지한다.
class ResetApiKeyButton extends ConsumerWidget {
  /// 파라미터 없이 위젯을 구성하는 생성자.
  const ResetApiKeyButton({super.key});

  /// 저장된 API 키를 지우고, 오늘의 학습 turn 카운터를 리셋한 뒤 앱을
  /// 재시작한다. 부작용: `apiKeyStorageServiceProvider`를 통해 키를
  /// 삭제하고, `sessionStateServiceProvider`를 통해 `daily_progress.json`을
  /// 지우며, [RestartWidget.restartApp]으로 전체 위젯 트리(및 모든
  /// provider)를 재생성한다.
  Future<void> _resetApiKey(BuildContext context, WidgetRef ref) async {
    await ref.read(apiKeyStorageServiceProvider).clearApiKey();
    await ref.read(sessionStateServiceProvider).clearDailyProgress();
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
