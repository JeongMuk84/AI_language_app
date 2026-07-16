import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/shadowing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/audio_play_button.dart';
import '../widgets/end_session_button.dart';
import '../widgets/feedback_box.dart';
import '../widgets/sentence_analysis_box.dart';

class ShadowingDictationScreen extends ConsumerStatefulWidget {
  const ShadowingDictationScreen({super.key});

  @override
  ConsumerState<ShadowingDictationScreen> createState() => _ShadowingDictationScreenState();
}

class _ShadowingDictationScreenState extends ConsumerState<ShadowingDictationScreen> {
  final _controller = TextEditingController();

  /// Bumped on "Try Again" to force a fresh AudioPlayButton that autoplays
  /// from the start.
  int _audioInstanceKey = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shadowingViewModelProvider.notifier).loadSentence());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() {
    return ref.read(shadowingViewModelProvider.notifier).submitDictation(_controller.text);
  }

  void _retry() {
    _controller.clear();
    ref.read(shadowingViewModelProvider.notifier).resetDictationAttempt();
    setState(() => _audioInstanceKey++);
  }

  Future<void> _goToPronunciation() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    final session = await sessionService.readState();
    if (session != null) {
      await sessionService.advanceToSecondSubStep(session);
    }
    if (mounted) context.go('/learning/shadowing/pronunciation');
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
          'Shadowing: Listen & Write',
          progressLabel: progressLabel,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.loadError != null) {
      return Scaffold(
        appBar: buildAppBarWithSettings(
          context,
          'Shadowing: Listen & Write',
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
                  onPressed: () => ref.read(shadowingViewModelProvider.notifier).loadSentence(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: buildAppBarWithSettings(
        context,
        'Shadowing: Listen & Write',
        progressLabel: progressLabel,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AudioPlayButton(
                  key: ValueKey(_audioInstanceKey),
                  audioLoader: () => ref.read(geminiServiceProvider).speakCached(state.sentence!),
                  autoPlay: _audioInstanceKey > 0,
                  tooltip: 'Play sentence',
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                enabled: !state.isSubmittingDictation,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write what you hear',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: state.isSubmittingDictation ? null : _submit,
                child: state.isSubmittingDictation
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit'),
              ),
              if (state.dictationError != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.dictationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (state.dictationResult != null) ...[
                const SizedBox(height: 16),
                FeedbackBox(
                  feedback: state.dictationResult!.feedback,
                  isCorrect: state.dictationResult!.isCorrect,
                ),
                const SizedBox(height: 16),
                SentenceAnalysisBox(
                  translation: state.dictationResult!.translation,
                  analysis: state.dictationResult!.analysis,
                ),
              ],
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _retry, child: const Text('Try Again')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: state.canProceedToPronunciation ? _goToPronunciation : null,
                child: const Text('Continue to Pronunciation Practice'),
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
