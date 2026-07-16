import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation_turn.dart';
import '../models/dictation_result.dart';
import '../models/exercise_type.dart';
import '../models/pronunciation_result.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';
import '../utils/id_utils.dart';

class ShadowingState {
  const ShadowingState({
    this.isLoadingSentence = true,
    this.loadError,
    this.turnId,
    this.sentence,
    this.ttsAudio,
    this.isSubmittingDictation = false,
    this.dictationResult,
    this.dictationError,
    this.lastDictationInput,
    this.sentenceHidden = false,
    this.isAnalyzingPronunciation = false,
    this.pronunciationResult,
    this.pronunciationError,
  });

  final bool isLoadingSentence;
  final String? loadError;
  final String? turnId;
  final String? sentence;
  final Uint8List? ttsAudio;

  final bool isSubmittingDictation;
  final DictationResult? dictationResult;
  final String? dictationError;
  final String? lastDictationInput;

  final bool sentenceHidden;
  final bool isAnalyzingPronunciation;
  final PronunciationResult? pronunciationResult;
  final String? pronunciationError;

  bool get canProceedToPronunciation => dictationResult != null;

  ShadowingState copyWith({
    bool? isSubmittingDictation,
    DictationResult? dictationResult,
    bool clearDictationResult = false,
    String? dictationError,
    bool clearDictationError = false,
    String? lastDictationInput,
    bool? sentenceHidden,
    bool? isAnalyzingPronunciation,
    PronunciationResult? pronunciationResult,
    bool clearPronunciationResult = false,
    String? pronunciationError,
    bool clearPronunciationError = false,
  }) {
    return ShadowingState(
      isLoadingSentence: isLoadingSentence,
      loadError: loadError,
      turnId: turnId,
      sentence: sentence,
      ttsAudio: ttsAudio,
      isSubmittingDictation: isSubmittingDictation ?? this.isSubmittingDictation,
      dictationResult: clearDictationResult ? null : (dictationResult ?? this.dictationResult),
      dictationError: clearDictationError ? null : (dictationError ?? this.dictationError),
      lastDictationInput: lastDictationInput ?? this.lastDictationInput,
      sentenceHidden: sentenceHidden ?? this.sentenceHidden,
      isAnalyzingPronunciation: isAnalyzingPronunciation ?? this.isAnalyzingPronunciation,
      pronunciationResult: clearPronunciationResult
          ? null
          : (pronunciationResult ?? this.pronunciationResult),
      pronunciationError: clearPronunciationError
          ? null
          : (pronunciationError ?? this.pronunciationError),
    );
  }
}

/// Backs both ShadowingDictationScreen and ShadowingPronunciationScreen —
/// they work on the same sentence/turn, so they share one view-model
/// instance rather than round-tripping data through navigation arguments.
class ShadowingViewModel extends Notifier<ShadowingState> {
  @override
  ShadowingState build() => const ShadowingState();

  /// Restores the in-progress sentence from the persisted session if one
  /// exists (resume case), otherwise requests a new one and persists it.
  Future<void> loadSentence() async {
    state = const ShadowingState();
    try {
      final sessionService = ref.read(sessionStateServiceProvider);
      final gemini = ref.read(geminiServiceProvider);

      var session = await sessionService.readState();
      session ??= await sessionService.startNewSession(initialType: ExerciseType.shadowing);

      String sentence;
      String turnId;
      if (session.currentSentence != null && session.currentTurnId != null) {
        sentence = session.currentSentence!;
        turnId = session.currentTurnId!;
      } else {
        sentence = await gemini.generateNextSentence(
          direction: 'target',
          history: session.conversationHistory,
        );
        turnId = newTurnId();
        await sessionService.setCurrentSentence(session, sentence: sentence, turnId: turnId);
      }

      final audio = await gemini.synthesizeSpeech(sentence);

      state = ShadowingState(
        isLoadingSentence: false,
        turnId: turnId,
        sentence: sentence,
        ttsAudio: audio,
      );
    } catch (e) {
      state = ShadowingState(isLoadingSentence: false, loadError: _messageFor(e));
    }
  }

  Future<void> submitDictation(String userInput) async {
    if (state.sentence == null) return;
    state = state.copyWith(isSubmittingDictation: true, clearDictationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .validateDictation(original: state.sentence!, userInput: userInput);
      state = state.copyWith(
        isSubmittingDictation: false,
        dictationResult: result,
        lastDictationInput: userInput,
      );
    } catch (e) {
      state = state.copyWith(isSubmittingDictation: false, dictationError: _messageFor(e));
    }
  }

  /// "다시 시도": same sentence/turnId, just clears the attempt so far.
  void resetDictationAttempt() {
    state = state.copyWith(clearDictationResult: true, clearDictationError: true);
  }

  /// "문장 보지 않고 녹음하기" / "문장 보기" toggle. Hiding starts a fresh
  /// pronunciation attempt; revealing again doesn't touch it.
  void toggleSentenceHidden() {
    if (!state.sentenceHidden) {
      state = state.copyWith(
        sentenceHidden: true,
        clearPronunciationResult: true,
        clearPronunciationError: true,
      );
    } else {
      state = state.copyWith(sentenceHidden: false);
    }
  }

  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    if (state.sentence == null) return;
    state = state.copyWith(isAnalyzingPronunciation: true, clearPronunciationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .analyzePronunciation(audioBytes: audioBytes, targetSentence: state.sentence!);
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationResult: result);
    } catch (e) {
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationError: _messageFor(e));
    }
  }

  /// "다음으로 넘어가기": records this shadowing turn and switches the active
  /// exercise type to writing.
  Future<void> completeTurnAndAdvanceToWriting() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    var session = await sessionService.readState();
    session ??= await sessionService.startNewSession(initialType: ExerciseType.shadowing);

    final turn = ConversationTurn(
      turnId: state.turnId ?? newTurnId(),
      type: ExerciseType.shadowing,
      timestamp: DateTime.now(),
      sentenceInTarget: state.sentence,
      userAnswer: state.lastDictationInput,
      isCorrect: state.dictationResult?.isCorrect,
      pronunciationScore: state.pronunciationResult?.accuracyPercent,
    );
    await sessionService.completeTurnAndSwitchType(
      session,
      turn: turn,
      nextType: ExerciseType.writing,
    );
  }

  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }
}

final shadowingViewModelProvider = NotifierProvider<ShadowingViewModel, ShadowingState>(
  ShadowingViewModel.new,
);
