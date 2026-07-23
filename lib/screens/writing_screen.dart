import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/learning_constants.dart';
import '../providers/service_providers.dart';
import '../viewmodels/writing_view_model.dart';
import '../widgets/app_bar_with_settings.dart';
import '../widgets/end_session_button.dart';
import '../widgets/feedback_box.dart';
import '../widgets/mixed_language_box.dart';
import '../widgets/reset_api_key_button.dart';

/// Writing 학습 루프의 첫 단계 화면("모국어 문장을 목표 언어로 번역해서
/// 쓰기"). 라우트 `/learning/writing`(`AppRoutes.writing`)에 연결된다.
/// [WritingViewModel]을 통해 모국어 문장을 불러오고, 학습자가 입력한 번역을
/// 채점한다. 통과하면(완전히 목표 언어로만 되어 있으면) "Continue to
/// Listening Practice" 버튼으로
/// WritingListeningScreen(`/learning/writing/listening`)으로 이동한다.
class WritingScreen extends ConsumerStatefulWidget {
  const WritingScreen({super.key});

  /// 이 위젯의 상태 객체([_WritingScreenState])를 생성한다.
  @override
  ConsumerState<WritingScreen> createState() => _WritingScreenState();
}

/// [WritingScreen]의 State. 번역 입력 텍스트필드 컨트롤러를 로컬로 관리한다.
class _WritingScreenState extends ConsumerState<WritingScreen> {
  final _controller = TextEditingController();

  /// 화면이 처음 마운트될 때 [WritingViewModel.loadSentence]를 호출해
  /// 문장을 불러오기 시작한다.
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(writingViewModelProvider.notifier).loadSentence());
  }

  /// 위젯이 트리에서 제거될 때 [_controller]를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Submit 버튼이 눌리면 호출된다. [WritingViewModel.submitTranslation]으로
  /// 현재 입력값을 채점 요청으로 보낸다.
  Future<void> _submit() {
    return ref.read(writingViewModelProvider.notifier).submitTranslation(_controller.text);
  }

  /// "Try Again" 버튼이 눌리면 호출된다. 입력값을 지우고
  /// [WritingViewModel.resetTranslationAttempt]로 시도를 초기화한다.
  void _retry() {
    _controller.clear();
    ref.read(writingViewModelProvider.notifier).resetTranslationAttempt();
  }

  /// "Continue to Listening Practice" 버튼이 눌리면 호출된다. 세션의 하위
  /// 단계를 두 번째 단계로 진행시키면서 학습자의 최종 번역을 함께 저장한
  /// 뒤(재시작 시 듣기 단계로 재개할 수 있도록),
  /// `context.go('/learning/writing/listening')`로 이동한다.
  Future<void> _goToListening() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    final session = await sessionService.readState();
    if (session != null) {
      final vmState = ref.read(writingViewModelProvider);
      await sessionService.advanceToSecondSubStep(
        session,
        userAnswer: vmState.lastUserTranslation,
      );
    }
    if (mounted) context.go('/learning/writing/listening');
  }

  /// [WritingViewModel]과 `dailyTurnCountProvider`를 watch해 번역 화면
  /// UI(로딩, 로드 에러+재시도, 또는 모국어 문장+입력+채점 결과+다음 단계
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
        appBar: buildAppBarWithSettings(context, 'Writing: Translate', progressLabel: progressLabel),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.loadError != null) {
      return Scaffold(
        appBar: buildAppBarWithSettings(context, 'Writing: Translate', progressLabel: progressLabel),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.read(writingViewModelProvider.notifier).loadSentence(),
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
      appBar: buildAppBarWithSettings(context, 'Writing: Translate', progressLabel: progressLabel),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                state.nativeSentence ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                enabled: !state.isSubmittingTranslation,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write your translation',
                ),
              ),
              const SizedBox(height: 16),
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
                FeedbackBox(
                  feedback: state.translationResult!.feedback,
                  // Reflects the actual turn-completion gate
                  // (`canProceedToListening`), not just the target-language
                  // portion's grammar — a grammatically-correct attempt
                  // that still mixes in native-language words must not show
                  // as "done" here, since it still needs the learner to
                  // finish rewriting it entirely in the target language.
                  isCorrect: state.canProceedToListening,
                  errors: state.translationResult!.errors,
                ),
                if (state.translationResult!.mixedLanguageSegments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  MixedLanguageBox(segments: state.translationResult!.mixedLanguageSegments),
                ],
              ],
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _retry, child: const Text('Try Again')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: state.canProceedToListening ? _goToListening : null,
                child: const Text('Continue to Listening Practice'),
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
