import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/shadowing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/audio_recorder_widget.dart';
import '../widgets/feedback_box.dart';

class ShadowingPronunciationScreen extends ConsumerWidget {
  const ShadowingPronunciationScreen({super.key});

  Future<void> _onRecordingComplete(WidgetRef ref, Uint8List bytes) {
    return ref.read(shadowingViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  void _toggleHideSentence(WidgetRef ref) {
    ref.read(shadowingViewModelProvider.notifier).toggleSentenceHidden();
  }

  Future<void> _next(BuildContext context, WidgetRef ref) async {
    await ref.read(shadowingViewModelProvider.notifier).completeTurnAndAdvanceToWriting();
    if (context.mounted) context.go('/learning/writing');
  }

  Future<void> _endSession(BuildContext context, WidgetRef ref) async {
    await ref.read(historyServiceProvider).finalizeSession();
    if (context.mounted) context.go('/learning');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shadowingViewModelProvider);
    final result = state.pronunciationResult;
    final passed = result != null && result.accuracyPercent >= kPronunciationPassThreshold;

    return Scaffold(
      appBar: buildAppBarWithSettings(context, 'Shadowing: Pronunciation'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!state.sentenceHidden)
                Text(
                  state.sentence ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                )
              else
                const SizedBox(height: 32),
              const SizedBox(height: 24),
              Center(
                child: AudioRecorderWidget(
                  onRecordingComplete: (bytes) => _onRecordingComplete(ref, bytes),
                ),
              ),
              const SizedBox(height: 24),
              if (state.isAnalyzingPronunciation)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (state.pronunciationError != null)
                  Text(
                    state.pronunciationError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                if (result != null) ...[
                  if (result.recognizedText.isNotEmpty) ...[
                    Text('Recognized:', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    // Target-language transcript of what was actually
                    // heard — never translated, so the learner can see
                    // exactly what their pronunciation sounded like.
                    Text(result.recognizedText, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 12),
                  ],
                  // `feedback` already comes back from Gemini in the
                  // learner's native language, including retry guidance
                  // when below kPronunciationPassThreshold — no English
                  // text is composed here.
                  FeedbackBox(
                    feedback: result.feedback,
                    isCorrect: passed,
                    scorePercent: result.accuracyPercent,
                  ),
                ],
              ],
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => _toggleHideSentence(ref),
                child: Text(
                  state.sentenceHidden ? 'Show Sentence' : 'Record Without Seeing the Sentence',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: passed ? () => _next(context, ref) : null,
                child: const Text('Continue to Writing'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _endSession(context, ref),
                child: const Text('End Session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
