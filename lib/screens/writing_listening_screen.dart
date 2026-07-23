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

/// Writing 학습 루프의 두 번째 단계 화면("자신의 번역을 듣고 발음 연습").
/// 라우트 `/learning/writing/listening`(`AppRoutes.writingListening`)에
/// 연결된다. [WritingViewModel]을 통해(WritingScreen과 상태를 공유)
/// 학습자 본인이 제출한 번역을 TTS로 재생하고, 녹음된 발음을 분석하며,
/// 통과하면 "Continue" 버튼으로
/// ShadowingDictationScreen(`/learning/shadowing/dictation`)으로 이동한다.
class WritingListeningScreen extends ConsumerStatefulWidget {
  const WritingListeningScreen({super.key});

  /// 이 위젯의 상태 객체([_WritingListeningScreenState])를 생성한다.
  @override
  ConsumerState<WritingListeningScreen> createState() => _WritingListeningScreenState();
}

/// [WritingListeningScreen]의 State. 별도의 로컬 상태 없이,
/// [WritingViewModel]에 의존해 화면을 그린다.
class _WritingListeningScreenState extends ConsumerState<WritingListeningScreen> {
  /// 화면이 처음 마운트될 때 [WritingViewModel.resumeListeningIfNeeded]를
  /// 호출한다.
  @override
  void initState() {
    super.initState();
    // 앱이 이 화면으로 바로 재시작되어(듣기 단계 도중 재개) 이번 세션에서
    // WritingScreen이 아직 공유 view-model에 번역을 로드해두지 않은
    // 경우가 아니라면 이 호출은 아무 일도 하지 않는다.
    Future.microtask(() => ref.read(writingViewModelProvider.notifier).resumeListeningIfNeeded());
  }

  /// AudioRecorderWidget 녹음이 끝나면 호출된다.
  /// [WritingViewModel.analyzePronunciation]으로 녹음된 [bytes]를 분석
  /// 요청으로 보낸다.
  Future<void> _onRecordingComplete(Uint8List bytes) {
    return ref.read(writingViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  /// "Try Again" 버튼이 눌리면 호출된다.
  /// [WritingViewModel.resetPronunciationAttempt]로 마지막 발음 시도를
  /// 초기화한다.
  void _retry() {
    ref.read(writingViewModelProvider.notifier).resetPronunciationAttempt();
  }

  /// 문장 숨김/보이기 버튼이 눌리면 호출된다.
  /// [WritingViewModel.toggleSentenceHidden]으로 숨김 상태를 반전시킨다.
  void _toggleHideSentence() {
    ref.read(writingViewModelProvider.notifier).toggleSentenceHidden();
  }

  /// "Continue" 버튼이 눌리면 호출된다.
  /// [WritingViewModel.completeTurnAndAdvanceToShadowing]으로 이번 턴을
  /// 기록하고, 일일 턴 한도에 도달했으면(`limitReached`) `/learning`으로,
  /// 아니면 `/learning/shadowing/dictation`으로 이동한다.
  Future<void> _next() async {
    final limitReached = await ref
        .read(writingViewModelProvider.notifier)
        .completeTurnAndAdvanceToShadowing();
    if (!mounted) return;
    context.go(limitReached ? '/learning' : '/learning/shadowing/dictation');
  }

  /// [WritingViewModel]과 `dailyTurnCountProvider`를 watch해 듣기/발음 연습
  /// 화면 UI(번역 문장 표시/숨김, 재생 버튼, 녹음 위젯, 분석 결과, 다음 단계
  /// 버튼)를 그린다.
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
