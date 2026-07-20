import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/writing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/audio_play_button.dart';
import '../widgets/audio_recorder_widget.dart';
import '../widgets/end_session_button.dart';
import '../widgets/feedback_box.dart';
import '../widgets/hideable_sentence.dart';

class WritingListeningScreen extends ConsumerStatefulWidget {
  const WritingListeningScreen({super.key});

  @override
  ConsumerState<WritingListeningScreen> createState() => _WritingListeningScreenState();
}

class _WritingListeningScreenState extends ConsumerState<WritingListeningScreen> {
  @override
  void initState() {
    super.initState();
    // A no-op unless the app restarted straight onto this screen (resuming
    // mid-listening) without WritingScreen having loaded the translation
    // into the shared view-model yet this session.
    Future.microtask(() => ref.read(writingViewModelProvider.notifier).resumeListeningIfNeeded());
  }

  Future<void> _onRecordingComplete(Uint8List bytes) {
    return ref.read(writingViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  void _retry() {
    ref.read(writingViewModelProvider.notifier).resetPronunciationAttempt();
  }

  void _toggleHideSentence() {
    ref.read(writingViewModelProvider.notifier).toggleSentenceHidden();
  }

  Future<void> _next() async {
    final limitReached = await ref
        .read(writingViewModelProvider.notifier)
        .completeTurnAndAdvanceToShadowing();
    if (!mounted) return;
    context.go(limitReached ? '/learning' : '/learning/shadowing/dictation');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(writingViewModelProvider);
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
          'Writing: Listen & Pronounce',
          progressLabel: progressLabel,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.loadError != null) {
      return Scaffold(
        appBar: buildAppBarWithSettings(
          context,
          'Writing: Listen & Pronounce',
          progressLabel: progressLabel,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/learning'),
                  child: const Text('Back to Start'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final result = state.pronunciationResult;
    final passed = result != null && result.accuracyPercent >= kPronunciationPassThreshold;

    return Scaffold(
      appBar: buildAppBarWithSettings(
        context,
        'Writing: Listen & Pronounce',
        progressLabel: progressLabel,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.lastUserTranslation != null)
                HideableSentence(
                  sentence: state.lastUserTranslation!,
                  hidden: state.sentenceHidden,
                ),
              const SizedBox(height: 24),
              if (state.lastUserTranslation != null)
                Center(
                  child: AudioPlayButton(
                    // Plays the learner's own final, fully-target-language
                    // submission, not a model answer — matches the sentence
                    // text above and `analyzePronunciation`'s comparison
                    // target below.
                    audioLoader: () =>
                        ref.read(geminiServiceProvider).speakCached(state.lastUserTranslation!),
                    tooltip: 'Play your translation',
                  ),
                ),
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
              OutlinedButton(onPressed: _retry, child: const Text('Try Again')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: passed ? _next : null,
                child: const Text('Continue'),
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
