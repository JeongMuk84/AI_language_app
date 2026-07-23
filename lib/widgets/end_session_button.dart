import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/service_providers.dart';

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
  /// 확정 저장한 뒤 `/learning` 라우트로 이동한다. 부작용: history
  /// provider의 상태를 변경(세션 확정)하고, 라우터를 통해 화면을 전환한다.
  Future<void> _endSession(BuildContext context, WidgetRef ref) async {
    await ref.read(historyServiceProvider).finalizeSession();
    if (context.mounted) context.go('/learning');
  }
}
