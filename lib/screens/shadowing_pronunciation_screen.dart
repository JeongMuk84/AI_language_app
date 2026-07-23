import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/shadowing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/audio_play_button.dart';
import '../widgets/audio_recorder_widget.dart';
import '../widgets/end_session_button.dart';
import '../widgets/feedback_box.dart';
import '../widgets/hideable_sentence.dart';

/// Shadowing 학습 루프의 두 번째 단계 화면("문장 보고/듣고 발음 연습").
/// 라우트 `/learning/shadowing/pronunciation`
/// (`AppRoutes.shadowingPronunciation`)에 연결된다.
/// [ShadowingViewModel]을 통해(ShadowingDictationScreen과 상태를 공유)
/// 캐시된 오디오를 재생하고, 녹음된 발음을 분석하며, 통과하면 "Continue to
/// Writing" 버튼으로 WritingScreen(`/learning/writing`)으로 이동한다.
class ShadowingPronunciationScreen extends ConsumerStatefulWidget {
  const ShadowingPronunciationScreen({super.key});

  /// 이 위젯의 상태 객체([_ShadowingPronunciationScreenState])를 생성한다.
  @override
  ConsumerState<ShadowingPronunciationScreen> createState() =>
      _ShadowingPronunciationScreenState();
}

/// [ShadowingPronunciationScreen]의 State. 별도의 로컬 상태 없이,
/// [ShadowingViewModel]에 의존해 화면을 그린다.
class _ShadowingPronunciationScreenState extends ConsumerState<ShadowingPronunciationScreen> {
  /// 화면이 처음 마운트될 때
  /// [ShadowingViewModel.ensureSentenceLoaded]를 호출한다.
  @override
  void initState() {
    super.initState();
    // 앱이 이 화면으로 바로 재시작되어(발음 연습 도중 재개) 이번 세션에서
    // ShadowingDictationScreen이 아직 공유 view-model에 문장을 로드해두지
    // 않은 경우가 아니라면 이 호출은 아무 일도 하지 않는다.
    Future.microtask(() => ref.read(shadowingViewModelProvider.notifier).ensureSentenceLoaded());
  }

  /// AudioRecorderWidget 녹음이 끝나면 호출된다.
  /// [ShadowingViewModel.analyzePronunciation]으로 녹음된 [bytes]를 분석
  /// 요청으로 보낸다.
  Future<void> _onRecordingComplete(Uint8List bytes) {
    return ref.read(shadowingViewModelProvider.notifier).analyzePronunciation(bytes);
  }

  /// 문장 숨김/보이기 버튼이 눌리면 호출된다.
  /// [ShadowingViewModel.toggleSentenceHidden]으로 숨김 상태를 반전시킨다.
  void _toggleHideSentence() {
    ref.read(shadowingViewModelProvider.notifier).toggleSentenceHidden();
  }

  /// "Continue to Writing" 버튼이 눌리면 호출된다.
  /// [ShadowingViewModel.completeTurnAndAdvanceToWriting]으로 이번 턴을
  /// 기록하고, 일일 턴 한도에 도달했으면(`limitReached`) `/learning`으로,
  /// 아니면 `/learning/writing`으로 이동한다.
  Future<void> _next() async {
    final limitReached = await ref
        .read(shadowingViewModelProvider.notifier)
        .completeTurnAndAdvanceToWriting();
    if (!mounted) return;
    context.go(limitReached ? '/learning' : '/learning/writing');
  }

  /// [ShadowingViewModel]과 `dailyTurnCountProvider`를 watch해 발음 연습
  /// 화면 UI(문장 표시/숨김, 재생 버튼, 녹음 위젯, 분석 결과, 다음 단계
  /// 버튼)를 그린다.
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
                child: AudioPlayButton(
                  // Deliberately cache-only, unlike WritingListeningScreen's
                  // play button: by the time a learner reaches this screen
                  // they've already been through ShadowingDictationScreen,
                  // whose own play button (same sentence) would have
                  // synthesized and cached this audio already — no reason to
                  // ever spend a fresh TTS call here. If it's somehow not
                  // cached (e.g. they never pressed play there), this just
                  // shows the button's own error state rather than
                  // synthesizing — same policy as ReviewScreen's play button.
                  audioLoader: () async {
                    final config = await ref.read(configServiceProvider).readConfig();
                    final hit = await ref
                        .read(ttsCacheServiceProvider)
                        .get(
                          sentence: state.sentence!,
                          language: config.targetLanguage ?? 'the target language',
                        );
                    if (hit == null) {
                      throw StateError('No cached audio for this sentence.');
                    }
                    return hit.audioBytes;
                  },
                  tooltip: 'Play sentence',
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
