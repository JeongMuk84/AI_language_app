import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/review_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/audio_play_button.dart';
import '../widgets/audio_recorder_widget.dart';
import '../widgets/feedback_box.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _controller = TextEditingController();
  int _lastIndexSeen = -1;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(reviewViewModelProvider.notifier).loadReviewSet());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() {
    return ref.read(reviewViewModelProvider.notifier).submitTranslation(_controller.text);
  }

  Future<void> _onRecordingComplete(Uint8List bytes) {
    return ref.read(reviewViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  Future<void> _advance() async {
    final route = await ref.read(reviewViewModelProvider.notifier).advance();
    if (mounted) context.go(route);
  }

  Future<void> _skip() async {
    final route = await ref.read(reviewViewModelProvider.notifier).skip();
    if (mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewViewModelProvider);

    // A new item is showing — clear the input left over from the last one,
    // or (resuming into an item that was already submitted before a
    // restart/remount) restore exactly what was submitted.
    if (state.currentIndex != _lastIndexSeen) {
      _lastIndexSeen = state.currentIndex;
      _controller.text = state.lastUserTranslation ?? '';
    }

    if (state.isLoading) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Review'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.loadError != null) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Review'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.read(reviewViewModelProvider.notifier).loadReviewSet(),
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _skip, child: const Text('Skip Review & Start Learning')),
              ],
            ),
          ),
        ),
      );
    }

    if (state.items.isEmpty || state.isExhausted) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Review'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nothing to review right now.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _skip, child: const Text('Start Learning')),
              ],
            ),
          ),
        ),
      );
    }

    final item = state.currentItem!;
    final canPractice = state.hasSubmittedTranslation;
    final result = state.pronunciationResult;
    final passed = result != null && result.accuracyPercent >= kPronunciationPassThreshold;

    return Scaffold(
      appBar: buildAppBarWithSettings(
        context,
        'Review',
        progressLabel: 'Reviewed: ${state.currentIndex}/${state.items.length}',
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.sentenceInNative,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      enabled: !state.isSubmittingTranslation && !canPractice,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Write the translation',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!canPractice)
                      FilledButton(
                        onPressed: state.isSubmittingTranslation ? null : _submit,
                        child: state.isSubmittingTranslation
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Submit'),
                      ),
                    if (state.translationError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.translationError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    if (state.translationResult != null) ...[
                      const SizedBox(height: 16),
                      // The original sentence, not a freshly-generated
                      // reference translation — this is exactly what gets
                      // played back and graded below, so it must match.
                      Text(
                        item.sentenceInTarget,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      FeedbackBox(
                        feedback: state.translationResult!.feedback,
                        isCorrect: state.translationResult!.isCorrect,
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    Center(
                      child: AudioPlayButton(
                        key: ValueKey('play-${state.currentIndex}'),
                        enabled: canPractice,
                        // Cache-only — never falls back to a fresh TTS
                        // call. `buildReviewSet` already guaranteed this
                        // sentence has cached audio; if it's since gone
                        // missing this returns null and the button shows
                        // its own error state rather than synthesizing.
                        audioLoader: () async {
                          final config = await ref.read(configServiceProvider).readConfig();
                          final hit = await ref
                              .read(ttsCacheServiceProvider)
                              .get(
                                sentence: item.sentenceInTarget,
                                language: config.targetLanguage ?? 'the target language',
                              );
                          if (hit == null) {
                            throw StateError('No cached audio for this review sentence.');
                          }
                          return hit.audioBytes;
                        },
                        tooltip: 'Play sentence',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: AudioRecorderWidget(
                        key: ValueKey('record-${state.currentIndex}'),
                        enabled: canPractice,
                        onRecordingComplete: _onRecordingComplete,
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
                          Text(result.recognizedText, style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 12),
                        ],
                        FeedbackBox(
                          feedback: result.feedback,
                          isCorrect: passed,
                          scorePercent: result.accuracyPercent,
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: state.canAdvance ? _advance : null,
                      child: Text(state.isLastItem ? 'Finish Review & Start Learning' : 'Next Sentence'),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: _skip,
                child: const Text('Skip Review & Start Learning'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
