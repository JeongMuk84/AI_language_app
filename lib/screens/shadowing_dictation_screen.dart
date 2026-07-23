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
import '../widgets/reset_api_key_button.dart';
import '../widgets/sentence_analysis_box.dart';

/// Shadowing 학습 루프의 첫 단계 화면("문장 듣고 받아쓰기"). 라우트
/// `/learning/shadowing/dictation`(`AppRoutes.shadowingDictation`)에
/// 연결된다. [ShadowingViewModel]을 통해 문장을 불러와 TTS로 재생하고,
/// 받아쓴 내용을 채점한다. 통과하면 "Continue to Pronunciation Practice"
/// 버튼으로 [ShadowingPronunciationScreen](`/learning/shadowing/pronunciation`)으로
/// 이동한다.
class ShadowingDictationScreen extends ConsumerStatefulWidget {
  const ShadowingDictationScreen({super.key});

  /// 이 위젯의 상태 객체([_ShadowingDictationScreenState])를 생성한다.
  @override
  ConsumerState<ShadowingDictationScreen> createState() => _ShadowingDictationScreenState();
}

/// [ShadowingDictationScreen]의 State. 받아쓰기 입력 텍스트필드 컨트롤러와,
/// 재생 버튼을 처음부터 다시 자동재생시키기 위한 인스턴스 키를 로컬로
/// 관리한다.
class _ShadowingDictationScreenState extends ConsumerState<ShadowingDictationScreen> {
  final _controller = TextEditingController();

  /// "Try Again"을 누를 때마다 증가시켜, 처음부터 자동재생하는 새
  /// AudioPlayButton을 강제로 다시 만들게 한다.
  int _audioInstanceKey = 0;

  /// 화면이 처음 마운트될 때 [ShadowingViewModel.loadSentence]를 호출해
  /// 문장을 불러오기 시작한다.
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shadowingViewModelProvider.notifier).loadSentence());
  }

  /// 위젯이 트리에서 제거될 때 [_controller]를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Submit 버튼이 눌리면 호출된다. [ShadowingViewModel.submitDictation]으로
  /// 현재 입력값을 채점 요청으로 보낸다.
  Future<void> _submit() {
    return ref.read(shadowingViewModelProvider.notifier).submitDictation(_controller.text);
  }

  /// "Try Again" 버튼이 눌리면 호출된다. 입력값을 지우고
  /// [ShadowingViewModel.resetDictationAttempt]로 시도를 초기화한 뒤,
  /// [_audioInstanceKey]를 증가시켜 재생 버튼을 처음부터 다시 자동재생하게
  /// 한다.
  void _retry() {
    _controller.clear();
    ref.read(shadowingViewModelProvider.notifier).resetDictationAttempt();
    setState(() => _audioInstanceKey++);
  }

  /// "Continue to Pronunciation Practice" 버튼이 눌리면 호출된다. 세션의
  /// 하위 단계를 두 번째 단계로 진행시킨 뒤(재시작 시 발음 연습 단계로
  /// 재개할 수 있도록), `context.go('/learning/shadowing/pronunciation')`로
  /// 이동한다.
  Future<void> _goToPronunciation() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    final session = await sessionService.readState();
    if (session != null) {
      await sessionService.advanceToSecondSubStep(session);
    }
    if (mounted) context.go('/learning/shadowing/pronunciation');
  }

  /// [ShadowingViewModel]과 `dailyTurnCountProvider`를 watch해 받아쓰기
  /// 화면 UI(로딩, 로드 에러+재시도, 또는 재생 버튼+입력+채점 결과+다음
  /// 단계 버튼)를 그린다.
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
                const SizedBox(height: 12),
                const ResetApiKeyButton(),
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
                  errors: state.dictationResult!.errors,
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
