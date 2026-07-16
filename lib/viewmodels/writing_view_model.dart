import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation_turn.dart';
import '../models/exercise_type.dart';
import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';
import '../utils/id_utils.dart';

class WritingState {
  const WritingState({
    this.isLoadingSentence = true,
    this.loadError,
    this.turnId,
    this.nativeSentence,
    this.isSubmittingTranslation = false,
    this.translationResult,
    this.translationError,
    this.lastUserTranslation,
    this.referenceAudio,
    this.isAnalyzingPronunciation = false,
    this.pronunciationResult,
    this.pronunciationError,
  });

  final bool isLoadingSentence;
  final String? loadError;
  final String? turnId;
  final String? nativeSentence;

  final bool isSubmittingTranslation;
  final TranslationResult? translationResult;
  final String? translationError;
  final String? lastUserTranslation;

  /// TTS of `translationResult.referenceTranslation`, prepared as soon as
  /// grading succeeds so WritingListeningScreen has it ready immediately.
  final Uint8List? referenceAudio;

  final bool isAnalyzingPronunciation;
  final PronunciationResult? pronunciationResult;
  final String? pronunciationError;

  bool get canProceedToListening => translationResult != null && referenceAudio != null;

  WritingState copyWith({
    bool? isSubmittingTranslation,
    TranslationResult? translationResult,
    bool clearTranslationResult = false,
    String? translationError,
    bool clearTranslationError = false,
    String? lastUserTranslation,
    Uint8List? referenceAudio,
    bool clearReferenceAudio = false,
    bool? isAnalyzingPronunciation,
    PronunciationResult? pronunciationResult,
    bool clearPronunciationResult = false,
    String? pronunciationError,
    bool clearPronunciationError = false,
  }) {
    return WritingState(
      isLoadingSentence: isLoadingSentence,
      loadError: loadError,
      turnId: turnId,
      nativeSentence: nativeSentence,
      isSubmittingTranslation: isSubmittingTranslation ?? this.isSubmittingTranslation,
      translationResult: clearTranslationResult
          ? null
          : (translationResult ?? this.translationResult),
      translationError: clearTranslationError
          ? null
          : (translationError ?? this.translationError),
      lastUserTranslation: lastUserTranslation ?? this.lastUserTranslation,
      referenceAudio: clearReferenceAudio ? null : (referenceAudio ?? this.referenceAudio),
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

/// Backs both WritingScreen and WritingListeningScreen — they work on the
/// same sentence/turn, so they share one view-model instance rather than
/// round-tripping data through navigation arguments.
class WritingViewModel extends Notifier<WritingState> {
  @override
  WritingState build() => const WritingState();

  Future<void> loadSentence() async {
    state = const WritingState();
    try {
      final sessionService = ref.read(sessionStateServiceProvider);
      final gemini = ref.read(geminiServiceProvider);

      var session = await sessionService.readState();
      session ??= await sessionService.startNewSession(initialType: ExerciseType.writing);

      String sentence;
      String turnId;
      if (session.currentSentence != null && session.currentTurnId != null) {
        sentence = session.currentSentence!;
        turnId = session.currentTurnId!;
      } else {
        sentence = await gemini.generateNextSentence(
          direction: 'native',
          history: session.conversationHistory,
        );
        turnId = newTurnId();
        await sessionService.setCurrentSentence(session, sentence: sentence, turnId: turnId);
      }

      state = WritingState(isLoadingSentence: false, turnId: turnId, nativeSentence: sentence);
    } catch (e) {
      state = WritingState(isLoadingSentence: false, loadError: _messageFor(e));
    }
  }

  Future<void> submitTranslation(String userTranslation) async {
    if (state.nativeSentence == null) return;
    state = state.copyWith(isSubmittingTranslation: true, clearTranslationError: true);
    try {
      final gemini = ref.read(geminiServiceProvider);
      final result = await gemini.validateTranslation(
        nativeSentence: state.nativeSentence!,
        userTranslation: userTranslation,
      );
      final audio = await gemini.synthesizeSpeech(result.referenceTranslation);
      state = state.copyWith(
        isSubmittingTranslation: false,
        translationResult: result,
        lastUserTranslation: userTranslation,
        referenceAudio: audio,
      );
    } catch (e) {
      state = state.copyWith(isSubmittingTranslation: false, translationError: _messageFor(e));
    }
  }

  /// "다시 시도" on WritingScreen: same sentence/turnId, clears the attempt.
  void resetTranslationAttempt() {
    state = state.copyWith(
      clearTranslationResult: true,
      clearTranslationError: true,
      clearReferenceAudio: true,
    );
  }

  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    final target = state.translationResult?.referenceTranslation;
    if (target == null) return;
    state = state.copyWith(isAnalyzingPronunciation: true, clearPronunciationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .analyzePronunciation(audioBytes: audioBytes, targetSentence: target);
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationResult: result);
    } catch (e) {
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationError: _messageFor(e));
    }
  }

  /// "다시 시도" on WritingListeningScreen: keeps the reference audio, just
  /// clears the last recording attempt.
  void resetPronunciationAttempt() {
    state = state.copyWith(clearPronunciationResult: true, clearPronunciationError: true);
  }

  /// "다음으로 넘어가기": records this writing turn and switches the active
  /// exercise type to shadowing.
  Future<void> completeTurnAndAdvanceToShadowing() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    var session = await sessionService.readState();
    session ??= await sessionService.startNewSession(initialType: ExerciseType.writing);

    final turn = ConversationTurn(
      turnId: state.turnId ?? newTurnId(),
      type: ExerciseType.writing,
      timestamp: DateTime.now(),
      sentenceInNative: state.nativeSentence,
      sentenceInTarget: state.translationResult?.referenceTranslation,
      userAnswer: state.lastUserTranslation,
      isCorrect: state.translationResult?.isCorrect,
      pronunciationScore: state.pronunciationResult?.accuracyPercent,
    );
    await sessionService.completeTurnAndSwitchType(
      session,
      turn: turn,
      nextType: ExerciseType.shadowing,
    );
  }

  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }
}

final writingViewModelProvider = NotifierProvider<WritingViewModel, WritingState>(
  WritingViewModel.new,
);
