import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/shadowing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/audio_recorder_widget.dart';
import '../widgets/end_session_button.dart';
import '../widgets/feedback_box.dart';
import '../widgets/hideable_sentence.dart';

class ShadowingPronunciationScreen extends ConsumerStatefulWidget {
  const ShadowingPronunciationScreen({super.key});

  @override
  ConsumerState<ShadowingPronunciationScreen> createState() =>
      _ShadowingPronunciationScreenState();
}

class _ShadowingPronunciationScreenState extends ConsumerState<ShadowingPronunciationScreen> {
  @override
  void initState() {
    super.initState();
    // A no-op unless the app restarted straight onto this screen (resuming
    // mid-pronunciation) without ShadowingDictationScreen having loaded the
    // sentence into the shared view-model yet this session.
    Future.microtask(() => ref.read(shadowingViewModelProvider.notifier).ensureSentenceLoaded());
  }

  Future<void> _onRecordingComplete(Uint8List bytes) {
    return ref.read(shadowingViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  void _toggleHideSentence() {
    ref.read(shadowingViewModelProvider.notifier).toggleSentenceHidden();
  }

  Future<void> _next() async {
    final limitReached = await ref
        .read(shadowingViewModelProvider.notifier)
        .completeTurnAndAdvanceToWriting();
    if (!mounted) return;
    context.go(limitReached ? '/learning' : '/learning/writing');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shadowingViewModelProvider);
    final progressLabel = ref
        .watch(dailyTurnCountProvider)
        .maybeWhen(
          data: (count) => 'Today: ${displayedDailyTurnNumber(count)}/$kDailyTurnLimit',
          orElse: () => null,
        );

    if (state.isLoadingSentence) {
      return Scaffold(
        appBar: buildAppBarWithSettings(
          context,
          'Shadowing: Pronunciation',
          progressLabel: progressLabel,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final result = state.pronunciationResult;
    final passed = result != null && result.accuracyPercent >= kPronunciationPassThreshold;

    return Scaffold(
      appBar: buildAppBarWithSettings(
        context,
        'Shadowing: Pronunciation',
        progressLabel: progressLabel,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HideableSentence(sentence: state.sentence ?? '', hidden: state.sentenceHidden),
              const SizedBox(height: 24),
              Center(
                child: AudioRecorderWidget(onRecordingComplete: _onRecordingComplete),
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
              SentenceVisibilityButton(hidden: state.sentenceHidden, onPressed: _toggleHideSentence),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: passed ? _next : null,
                child: const Text('Continue to Writing'),
              ),
              const SizedBox(height: 12),
              const EndSessionButton(),
            ],
          ),
        ),
      ),
    );
  }
}
