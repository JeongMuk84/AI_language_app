import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/service_providers.dart';

/// "학습 종료" — shared by all four learning screens (ShadowingDictation,
/// ShadowingPronunciation, Writing, WritingListening) so there's exactly
/// one implementation of "end the session" instead of four copies. Always
/// enabled, regardless of whatever's been submitted/scored on the current
/// (in-progress, not-yet-completed) sentence — `HistoryService.finalizeSession`
/// only ever persists turns that were already completed via "다음으로
/// 넘어가기" (see `ShadowingViewModel.completeTurnAndAdvanceToWriting` /
/// `WritingViewModel.completeTurnAndAdvanceToShadowing`), so whatever's on
/// screen right now is simply dropped, never half-saved.
class EndSessionButton extends ConsumerWidget {
  const EndSessionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () => _endSession(context, ref),
      child: const Text('End Session'),
    );
  }

  Future<void> _endSession(BuildContext context, WidgetRef ref) async {
    await ref.read(historyServiceProvider).finalizeSession();
    if (context.mounted) context.go('/learning');
  }
}
