import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/learning_constants.dart';
import '../models/conversation_turn.dart';
import '../models/exercise_type.dart';
import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';
import '../utils/id_utils.dart';
import 'sentence_hidden_toggle_mixin.dart';

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
    this.completedSentence,
    this.sentenceHidden = false,
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

  /// The learner's own final submitted translation, exactly as typed
  /// (whatever they last submitted, if they retried) — stored for history
  /// purposes (`ConversationTurn.userAnswer`). NOT what gets
  /// spoken/displayed/practiced on WritingListeningScreen when the
  /// submission mixed in native-language segments; see [completedSentence]
  /// for that.
  final String? lastUserTranslation;

  /// [lastUserTranslation] with any native-language segments replaced by
  /// their target-language equivalent (`TranslationResult.completedSentence`)
  /// — this is the sentence WritingListeningScreen displays, plays via TTS,
  /// and grades pronunciation against. Equal to [lastUserTranslation] when
  /// the submission was already entirely in the target language.
  final String? completedSentence;

  final bool sentenceHidden;
  final bool isAnalyzingPronunciation;
  final PronunciationResult? pronunciationResult;
  final String? pronunciationError;

  bool get canProceedToListening => translationResult != null;

  WritingState copyWith({
    bool? isSubmittingTranslation,
    TranslationResult? translationResult,
    bool clearTranslationResult = false,
    String? translationError,
    bool clearTranslationError = false,
    String? lastUserTranslation,
    String? completedSentence,
    bool? sentenceHidden,
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
      completedSentence: completedSentence ?? this.completedSentence,
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

/// Backs both WritingScreen and WritingListeningScreen — they work on the
/// same sentence/turn, so they share one view-model instance rather than
/// round-tripping data through navigation arguments.
class WritingViewModel extends Notifier<WritingState> with SentenceHiddenToggleMixin<WritingState> {
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

  /// Resumes WritingListeningScreen after an app restart lands directly on
  /// it (mid-listening, per `LearningSubStep.second`) — a no-op if this
  /// session's translation is already loaded. `loadSentence()` is for the
  /// *first* sub-step (a fresh writing prompt) and doesn't restore the
  /// learner's own submitted translation, so it can't be reused here: this
  /// restores just enough (sentence + the learner's answer) for listening
  /// and pronunciation grading to work, without re-running grading itself.
  Future<void> resumeListeningIfNeeded() async {
    if (state.lastUserTranslation != null) return;
    final session = await ref.read(sessionStateServiceProvider).readState();
    final userAnswer = session?.currentUserAnswer;
    if (session == null || userAnswer == null) {
      // Shouldn't normally happen (this screen is only reachable with a
      // submitted translation), but avoid stranding the learner on a
      // permanent spinner if the persisted state is ever missing/corrupt.
      state = const WritingState(
        isLoadingSentence: false,
        loadError: 'Could not resume this session. Please start again.',
      );
      return;
    }
    state = WritingState(
      isLoadingSentence: false,
      turnId: session.currentTurnId,
      nativeSentence: session.currentSentence,
      lastUserTranslation: userAnswer,
      // Falls back to the raw answer for sessions persisted before this
      // field existed, where it's absent from session_state.json.
      completedSentence: session.currentCompletedSentence ?? userAnswer,
    );
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
      state = state.copyWith(
        isSubmittingTranslation: false,
        translationResult: result,
        lastUserTranslation: userTranslation,
        completedSentence: result.completedSentence.isNotEmpty
            ? result.completedSentence
            : userTranslation,
      );
    } catch (e) {
      state = state.copyWith(isSubmittingTranslation: false, translationError: _messageFor(e));
    }
  }

  /// "다시 시도" on WritingScreen: same sentence/turnId, clears the attempt.
  void resetTranslationAttempt() {
    state = state.copyWith(clearTranslationResult: true, clearTranslationError: true);
  }

  @override
  bool sentenceHiddenOf(WritingState state) => state.sentenceHidden;

  @override
  WritingState copyWithSentenceHidden(WritingState state, {required bool hidden}) {
    return hidden
        ? state.copyWith(
            sentenceHidden: true,
            clearPronunciationResult: true,
            clearPronunciationError: true,
          )
        : state.copyWith(sentenceHidden: false);
  }

  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    // The completed (fully target-language) form of the learner's own
    // submission, not the model answer — matches whatever
    // WritingListeningScreen just played them via `speakCached`.
    final target = state.completedSentence;
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

  /// "다시 시도" on WritingListeningScreen: just clears the last recording
  /// attempt.
  void resetPronunciationAttempt() {
    state = state.copyWith(clearPronunciationResult: true, clearPronunciationError: true);
  }

  /// "다음으로 넘어가기": records this writing turn and switches the active
  /// exercise type to shadowing.
  ///
  /// Returns true if this turn just hit [kDailyTurnLimit] — the caller
  /// should return to the entry-routing screen instead of continuing to
  /// the next exercise, since the session was auto-finalized here exactly
  /// like "학습 종료" would.
  Future<bool> completeTurnAndAdvanceToShadowing() async {
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
      completedSentence: state.completedSentence,
      isCorrect: state.translationResult?.isCorrect,
      pronunciationScore: state.pronunciationResult?.accuracyPercent,
    );
    await sessionService.completeTurnAndSwitchType(
      session,
      turn: turn,
      nextType: ExerciseType.shadowing,
    );

    // Track this sentence for spaced review — a no-op if it's already
    // tracked. Uses `completedSentence` (the learner's own submission,
    // completed into the target language), NOT `referenceTranslation` (a
    // model example the learner never actually said) — `completedSentence`
    // is exactly what WritingListeningScreen just cached as TTS audio via
    // `speakCached`, so this is the string ReviewSessionService.buildReviewSet()'s
    // cache check needs to find a hit under.
    final completedSentence = state.completedSentence;
    if (completedSentence != null && completedSentence.isNotEmpty && state.nativeSentence != null) {
      await ref
          .read(reviewHistoryServiceProvider)
          .recordIfNew(
            sentenceInTarget: completedSentence,
            sentenceInNative: state.nativeSentence!,
          );
    }

    final newCount = await sessionService.incrementDailyTurnCount();
    ref.invalidate(dailyTurnCountProvider);
    if (newCount >= kDailyTurnLimit) {
      await ref.read(historyServiceProvider).finalizeSession();
      return true;
    }
    return false;
  }

  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }
}

final writingViewModelProvider = NotifierProvider<WritingViewModel, WritingState>(
  WritingViewModel.new,
);
