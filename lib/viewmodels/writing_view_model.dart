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
  /// purposes (`ConversationTurn.userAnswer`/`sentenceInTarget`). Once
  /// [canProceedToListening] is true, this is guaranteed to be entirely in
  /// the target language (no native-language segments left) — it's also
  /// the exact sentence WritingListeningScreen displays, plays via TTS, and
  /// grades pronunciation against. There is deliberately no separate
  /// "completed"/auto-translated variant: a mixed-language submission is
  /// never auto-finished on the learner's behalf, they have to edit their
  /// own attempt and resubmit an entirely target-language sentence
  /// themselves (see `TranslationResult.hasNativeLanguageMixed`).
  final String? lastUserTranslation;

  final bool sentenceHidden;
  final bool isAnalyzingPronunciation;
  final PronunciationResult? pronunciationResult;
  final String? pronunciationError;

  /// A submission only counts as done when the target-language portion is
  /// correct AND nothing was left in the native language — a
  /// grammatically-fine attempt that still mixes languages is not enough;
  /// the learner has to fully rewrite it in the target language themselves
  /// (see `TranslationResult.hasNativeLanguageMixed`).
  bool get canProceedToListening =>
      translationResult != null &&
      translationResult!.isCorrect &&
      !translationResult!.hasNativeLanguageMixed;

  WritingState copyWith({
    bool? isSubmittingTranslation,
    TranslationResult? translationResult,
    bool clearTranslationResult = false,
    String? translationError,
    bool clearTranslationError = false,
    String? lastUserTranslation,
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

  /// Guards against two overlapping [loadSentence] calls both racing past
  /// the "does the persisted session already have a sentence" check before
  /// either has written its result — see the identical guard (and its full
  /// rationale) on `ShadowingViewModel.loadSentence`.
  bool _isLoadingSentence = false;

  /// [nativeSentence] ends up as the single reference for this whole turn
  /// once this returns — `submitTranslation`'s grading call reads it
  /// directly.
  Future<void> loadSentence() async {
    if (_isLoadingSentence) return;
    _isLoadingSentence = true;
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
        final history = await ref.read(conversationHistoryServiceProvider).readAll();
        sentence = await gemini.generateNextSentence(direction: 'native', history: history);
        turnId = newTurnId();
        await sessionService.setCurrentSentence(session, sentence: sentence, turnId: turnId);
      }

      state = WritingState(isLoadingSentence: false, turnId: turnId, nativeSentence: sentence);
    } catch (e) {
      state = WritingState(isLoadingSentence: false, loadError: _messageFor(e));
    } finally {
      _isLoadingSentence = false;
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
    // The learner's own final, fully-target-language submission — matches
    // whatever WritingListeningScreen just played them via `speakCached`.
    final target = state.lastUserTranslation;
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
      // The learner's own final (fully target-language, correct) answer —
      // never `referenceTranslation` (a model example they never actually
      // wrote themselves).
      sentenceInTarget: state.lastUserTranslation,
      userAnswer: state.lastUserTranslation,
      isCorrect: state.translationResult?.isCorrect,
      pronunciationScore: state.pronunciationResult?.accuracyPercent,
    );
    await sessionService.completeTurnAndSwitchType(
      session,
      nextType: ExerciseType.shadowing,
    );
    await ref.read(conversationHistoryServiceProvider).append(turn);

    // Track this sentence for spaced review — a no-op if it's already
    // tracked. `lastUserTranslation` is exactly what WritingListeningScreen
    // just cached as TTS audio via `speakCached`, so this is the string
    // ReviewSessionService.buildReviewSet()'s cache check needs to find a
    // hit under.
    final finalAnswer = state.lastUserTranslation;
    if (finalAnswer != null && finalAnswer.isNotEmpty && state.nativeSentence != null) {
      await ref
          .read(reviewHistoryServiceProvider)
          .recordIfNew(sentenceInTarget: finalAnswer, sentenceInNative: state.nativeSentence!);
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
