import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/service_providers.dart';
import '../router/app_router.dart';

/// "학습 종료" 버튼 — ShadowingDictationScreen, ShadowingPronunciationScreen,
/// WritingScreen, WritingListeningScreen 네 학습 화면에서 공통으로 쓰여,
/// "세션 종료"를 화면마다 네 번 따로 구현하지 않고 이 하나의 구현만
/// 두게 한다. 현재(진행 중이며 아직 완료되지 않은) 문장에 무엇이
/// 제출/채점되어 있는지와 무관하게 항상 활성화되어 있다 —
/// `HistoryService.finalizeSession`은 이미 "다음으로 넘어가기"를 통해
/// 완료된 턴만 저장하므로(`ShadowingViewModel.completeTurnAndAdvanceToWriting`
/// / `WritingViewModel.completeTurnAndAdvanceToShadowing` 참고), 지금 화면에
/// 떠 있는 미완료 내용은 그냥 버려질 뿐 절반만 저장되는 일은 없다.
class EndSessionButton extends ConsumerWidget {
  /// 파라미터 없이 위젯을 구성하는 생성자.
  const EndSessionButton({super.key});

  /// "End Session" 텍스트 버튼을 그리며, 탭하면 [_endSession]을 호출한다.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () => _endSession(context, ref),
      child: const Text('End Session'),
    );
  }

  /// `HistoryService.finalizeSession`으로 현재까지 완료된 세션 기록을
  /// 확정 저장한 뒤, (오늘 이미 복습을 했는지·`dailyTurnCount`가 몇인지와
  /// 무관하게) 항상 곧바로 [AppRoutes.review]로 이동한다 — 학습 도중
  /// 언제 "학습 종료"를 누르든 그다음은 항상 복습이라는 단순한 규칙이다.
  /// `/learning`을 거치지 않으므로 라우터의 일반 진입 분기(오늘 이미
  /// 복습을 마쳤으면 그냥 다음 학습을 또 시작하는 로직)를 타지 않는다.
  /// 부작용: history provider의 상태를 변경(세션 확정)하고, 라우터를 통해
  /// 화면을 전환한다.
  Future<void> _endSession(BuildContext context, WidgetRef ref) async {
    await ref.read(historyServiceProvider).finalizeSession();
    if (context.mounted) context.go(AppRoutes.review);
  }
}
