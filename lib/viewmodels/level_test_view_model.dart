import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/level_test_question.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';

/// LevelTestScreen이 화면을 어떤 단계로 그릴지 결정하는 값. `loading`이면
/// 로딩 인디케이터, `loadError`면 재시도 UI, `loaded`면 실제 문제 목록을
/// 보여준다.
enum LevelTestStage { loading, loaded, loadError }

/// LevelTestScreen이 watch하는 UI 상태. Gemini가 생성한 레벨 테스트 문제,
/// 학습자가 입력 중인 답안, 로딩/제출 진행 상태를 담는다.
class LevelTestState {
  const LevelTestState({
    this.stage = LevelTestStage.loading,
    this.questions = const [],
    this.answers = const [],
    this.isSubmitting = false,
    this.loadErrorMessage,
    this.submitErrorMessage,
  });

  /// 현재 화면 단계. [LevelTestViewModel.loadQuestions]의 성공/실패에 따라
  /// `loaded`/`loadError`로 바뀐다.
  final LevelTestStage stage;

  /// `GeminiService.generateLevelTest`가 생성한 문제 목록.
  final List<LevelTestQuestion> questions;

  /// [questions]와 동일한 길이의 답안 목록. [LevelTestViewModel.updateAnswer]로
  /// 개별 인덱스가 갱신된다.
  final List<String> answers;

  /// [LevelTestViewModel.submit]이 채점 요청을 보내는 동안 true가 되어,
  /// LevelTestScreen의 Submit 버튼을 비활성화하고 로딩 인디케이터를
  /// 보여주게 한다.
  final bool isSubmitting;

  /// 문제 로딩 실패 시 사용자에게 보여줄 에러 메시지.
  final String? loadErrorMessage;

  /// 채점(제출) 실패 시 사용자에게 보여줄 에러 메시지.
  final String? submitErrorMessage;

  /// [stage]/[questions]/[answers]/[isSubmitting]/[loadErrorMessage]/
  /// [submitErrorMessage]를 갱신한 새 LevelTestState를 반환한다. 두 에러
  /// 메시지 필드는 인자를 넘기지 않으면 항상 null로 초기화된다.
  LevelTestState copyWith({
    LevelTestStage? stage,
    List<LevelTestQuestion>? questions,
    List<String>? answers,
    bool? isSubmitting,
    String? loadErrorMessage,
    String? submitErrorMessage,
  }) {
    return LevelTestState(
      stage: stage ?? this.stage,
      questions: questions ?? this.questions,
      answers: answers ?? this.answers,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      loadErrorMessage: loadErrorMessage,
      submitErrorMessage: submitErrorMessage,
    );
  }
}

/// LevelTestScreen(라우트 `/level-test`, 온보딩 세 번째 단계)을 지원하는
/// 뷰모델. Gemini로 레벨 테스트 문제를 생성/채점하고, 결과 레벨을 config.json에
/// 저장한다. AppRouter의 redirect 로직은 `config.hasDifficultyLevel`이
/// false이고 handoff 파일도 없을 때 이 화면으로 보내며, 채점에 성공하면
/// 온보딩이 끝나고 `/learning`으로 넘어갈 수 있게 된다.
class LevelTestViewModel extends Notifier<LevelTestState> {
  /// 초기 상태(로딩 중, 문제 없음)를 생성한다. Riverpod이 이 provider가
  /// 처음 watch/read될 때 자동으로 호출한다.
  @override
  LevelTestState build() => const LevelTestState();

  /// LevelTestScreen의 `initState`에서 호출되어(재시도 버튼에서도 재호출),
  /// `configServiceProvider`에서 읽은 모국어/학습 언어로
  /// `GeminiService.generateLevelTest`를 호출해 문제 목록을 받아온다. 성공하면
  /// [LevelTestState.stage]를 `loaded`로, 실패하면 `loadError`로 바꾼다.
  Future<void> loadQuestions() async {
    state = const LevelTestState(stage: LevelTestStage.loading);
    try {
      final config = await ref.read(configServiceProvider).readConfig();
      final questions = await ref.read(geminiServiceProvider).generateLevelTest(
            config.nativeLanguage ?? '',
            config.targetLanguage ?? '',
          );
      state = LevelTestState(
        stage: LevelTestStage.loaded,
        questions: questions,
        answers: List.filled(questions.length, ''),
      );
    } catch (e) {
      state = LevelTestState(
        stage: LevelTestStage.loadError,
        loadErrorMessage: _messageFor(e),
      );
    }
  }

  /// LevelTestScreen이 Submit 직전에 각 TextEditingController의 최신 텍스트를
  /// 반영하기 위해 문항마다 호출한다(`_submit`의 for 루프 참고). [state.stage]가
  /// `loaded`가 아니거나 인덱스가 범위를 벗어나면 아무 것도 하지 않는다.
  void updateAnswer(int index, String value) {
    if (state.stage != LevelTestStage.loaded || index >= state.answers.length) return;
    final answers = [...state.answers];
    answers[index] = value;
    state = state.copyWith(answers: answers);
  }

  /// LevelTestScreen의 Submit 버튼이 눌리면(모든 답안이 [updateAnswer]로 먼저
  /// 반영된 뒤) 호출된다. `GeminiService.evaluateLevelTest`로 문제/답안을 채점해
  /// 난이도 레벨을 받아온 뒤 `configServiceProvider.updateConfig`로
  /// config.json에 저장한다.
  ///
  /// 레벨 평가와 저장이 모두 성공하면 true를 반환하며, 이때 LevelTestScreen은
  /// `context.go('/')`로 이동해 라우터의 redirect가 다음 단계(학습 화면)를
  /// 결정하도록 한다. 실패 시 [LevelTestState.submitErrorMessage]에 에러
  /// 메시지를 담고 false를 반환한다.
  Future<bool> submit() async {
    state = state.copyWith(isSubmitting: true, submitErrorMessage: null);
    try {
      final config = await ref.read(configServiceProvider).readConfig();
      final level = await ref.read(geminiServiceProvider).evaluateLevelTest(
            nativeLang: config.nativeLanguage ?? '',
            targetLang: config.targetLanguage ?? '',
            questions: state.questions,
            answers: state.answers,
          );
      await ref
          .read(configServiceProvider)
          .updateConfig((current) => current.copyWith(difficultyLevel: level));
      state = state.copyWith(isSubmitting: false, submitErrorMessage: null);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, submitErrorMessage: _messageFor(e));
      return false;
    }
  }

  /// 예외 [e]를 사용자에게 보여줄 메시지 문자열로 변환한다. `GeminiApiException`이면
  /// 실패 사유별 안내 메시지로, 그 외에는 일반적인 재시도 안내 메시지로 바꾼다.
  String _messageFor(Object e) {
    if (e is GeminiApiException) {
      return userMessageForFailure(e.reason, e.message);
    }
    return 'Something went wrong. Please try again.';
  }
}

/// [LevelTestViewModel]/[LevelTestState]를 노출하는 provider. LevelTestScreen에서
/// `ref.watch`(상태 렌더링)와 `ref.read(...notifier)`(loadQuestions/
/// updateAnswer/submit 호출)로 사용된다.
final levelTestViewModelProvider = NotifierProvider<LevelTestViewModel, LevelTestState>(
  LevelTestViewModel.new,
);
