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
import '../widgets/reset_api_key_button.dart';

/// 스페이스드 리뷰(spaced review) 화면. 라우트 `/learning/review`
/// (`AppRoutes.review`)에 연결된다. AppRouter의 redirect 로직은 온보딩이
/// 끝난 뒤 진행 중이던 리뷰가 있거나 새로 만든 리뷰 세트가 비어있지 않을 때
/// 이 화면으로 보내며, ReviewViewModel(`advance`/`skip`)이 반환하는 라우트를
/// 통해 다음 학습 화면(Writing 또는 Shadowing Dictation)으로 이어진다.
/// [ReviewViewModel]을 통해 문항별 번역 제출/채점과 발음 분석을 처리한다.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  /// 이 위젯의 상태 객체([_ReviewScreenState])를 생성한다.
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

/// [ReviewScreen]의 State. 번역 입력 텍스트필드 컨트롤러와, 문항이 바뀌었는지
/// 감지하기 위한 마지막으로 본 인덱스를 로컬로 관리한다.
class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _controller = TextEditingController();
  int _lastIndexSeen = -1;

  /// 화면이 처음 마운트될 때 [ReviewViewModel.loadReviewSet]을 호출해 리뷰
  /// 세트를 불러오기 시작한다.
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(reviewViewModelProvider.notifier).loadReviewSet());
  }

  /// 위젯이 트리에서 제거될 때 [_controller]를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Submit 버튼이 눌리면 호출된다. [ReviewViewModel.submitTranslation]으로
  /// 현재 입력값을 채점 요청으로 보낸다.
  Future<void> _submit() {
    return ref.read(reviewViewModelProvider.notifier).submitTranslation(_controller.text);
  }

  /// AudioRecorderWidget 녹음이 끝나면 호출된다.
  /// [ReviewViewModel.analyzePronunciation]으로 녹음된 [bytes]를 분석
  /// 요청으로 보낸다.
  Future<void> _onRecordingComplete(Uint8List bytes) {
    return ref.read(reviewViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  /// "Next Sentence" / "Finish Review & Start Learning" 버튼이 눌리면
  /// 호출된다. [ReviewViewModel.advance]를 호출해 다음 문항으로 넘어가거나
  /// 리뷰를 끝내고, 반환된 라우트로 `context.go`한다.
  Future<void> _advance() async {
    final route = await ref.read(reviewViewModelProvider.notifier).advance();
    if (mounted) context.go(route);
  }

  /// "Skip Review & Start Learning" 버튼이 눌리면 호출된다.
  /// [ReviewViewModel.skip]을 호출해 남은 리뷰를 포기하고, 반환된 라우트로
  /// `context.go`한다.
  Future<void> _skip() async {
    final route = await ref.read(reviewViewModelProvider.notifier).skip();
    if (mounted) context.go(route);
  }

  /// [ReviewViewModel]을 watch해 리뷰 화면 UI를 그린다: 로딩/로드 에러/빈
  /// 목록(복습할 것 없음)/실제 문항(문장 재생, 번역 입력+채점, 발음
  /// 녹음+분석, 다음/건너뛰기 버튼)까지 리뷰 흐름의 각 단계를 담당한다.
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewViewModelProvider);

    // 새 문항이 표시되는 시점 — 이전 문항에 남아있던 입력값을 지우거나,
    // (재시작/재마운트 이전에 이미 제출된 적 있는 문항으로 재개하는
    // 경우라면) 그때 제출했던 내용을 그대로 복원한다.
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
                const ResetApiKeyButton(),
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
    // Once the learner has actually gotten the translation right, there's
    // no reason to let them edit/resubmit it — a wrong (or not-yet-
    // attempted) translation keeps both editable so they can correct it.
    final isTranslationCorrect = state.isTranslationCorrect;
    final result = state.pronunciationResult;
    final passed = result != null && result.accuracyPercent >= kPronunciationPassThreshold;

    return Scaffold(
      appBar: buildAppBarWithSettings(
        context,
        'Review',
        // 1-indexed, matching the "Today: X/Y" daily turn counter elsewhere —
        // currentIndex is 0 while the first item is in progress, so this
        // shows "1" for it rather than "0".
        progressLabel: 'Reviewed: ${state.currentIndex + 1}/${state.items.length}',
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
                    Center(
                      child: AudioPlayButton(
                        key: ValueKey('play-${state.currentIndex}'),
                        // Always enabled from screen entry — unlike
                        // submission/pronunciation, there's no reason
                        // hearing the sentence needs to wait on anything.
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
                    TextField(
                      controller: _controller,
                      enabled: !state.isSubmittingTranslation && !isTranslationCorrect,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Write the translation',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: (state.isSubmittingTranslation || isTranslationCorrect)
                          ? null
                          : _submit,
                      child: state.isSubmittingTranslation
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit'),
                    ),
                    if (state.translationWarning != null) ...[
                      const SizedBox(height: 16),
                      FeedbackBox(feedback: state.translationWarning!),
                    ],
                    if (state.translationError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        state.translationError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    if (state.translationResult != null) ...[
                      const SizedBox(height: 16),
                      // Grading feedback only — deliberately never shows
                      // the correct/model sentence itself (that used to be
                      // `item.sentenceInTarget` here); the learner has to
                      // recall it themselves.
                      FeedbackBox(
                        feedback: state.translationResult!.feedback,
                        isCorrect: state.translationResult!.isCorrect,
                        errors: state.translationResult!.errors,
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    Center(
                      child: AudioRecorderWidget(
                        key: ValueKey('record-${state.currentIndex}'),
                        // Always enabled from screen entry — see
                        // AudioPlayButton above.
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
