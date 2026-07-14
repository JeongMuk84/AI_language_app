import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/level_test_question.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';

enum LevelTestStage { loading, loaded, loadError }

class LevelTestState {
  const LevelTestState({
    this.stage = LevelTestStage.loading,
    this.questions = const [],
    this.answers = const [],
    this.isSubmitting = false,
    this.loadErrorMessage,
    this.submitErrorMessage,
  });

  final LevelTestStage stage;
  final List<LevelTestQuestion> questions;
  final List<String> answers;
  final bool isSubmitting;
  final String? loadErrorMessage;
  final String? submitErrorMessage;

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

class LevelTestViewModel extends Notifier<LevelTestState> {
  @override
  LevelTestState build() => const LevelTestState();

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

  void updateAnswer(int index, String value) {
    if (state.stage != LevelTestStage.loaded || index >= state.answers.length) return;
    final answers = [...state.answers];
    answers[index] = value;
    state = state.copyWith(answers: answers);
  }

  /// Returns true if the level was evaluated and saved successfully.
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

  String _messageFor(Object e) {
    if (e is GeminiApiException) {
      return userMessageForFailure(e.reason, e.message);
    }
    return 'Something went wrong. Please try again.';
  }
}

final levelTestViewModelProvider = NotifierProvider<LevelTestViewModel, LevelTestState>(
  LevelTestViewModel.new,
);
