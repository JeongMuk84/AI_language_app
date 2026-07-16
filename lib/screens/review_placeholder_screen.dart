import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/exercise_type.dart';
import '../providers/service_providers.dart';
import '../widgets/app_bar_with_settings.dart';

/// Shown when there's history but no in-progress session. Review isn't
/// built yet — this just lets the user start a fresh session, continuing
/// from whichever exercise type they didn't finish on last time.
class ReviewPlaceholderScreen extends ConsumerWidget {
  const ReviewPlaceholderScreen({super.key});

  Future<void> _startLearning(BuildContext context, WidgetRef ref) async {
    final lastType = await ref.read(historyServiceProvider).getLastExerciseType() ??
        ExerciseType.writing;
    final nextType = lastType.other;

    await ref.read(sessionStateServiceProvider).startNewSession(initialType: nextType);

    if (!context.mounted) return;
    context.go(
      nextType == ExerciseType.shadowing
          ? '/learning/shadowing/dictation'
          : '/learning/writing',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: buildAppBarWithSettings(context, 'Learning'),
      body: Center(
        child: FilledButton(
          onPressed: () => _startLearning(context, ref),
          child: const Text('Start Learning'),
        ),
      ),
    );
  }
}
