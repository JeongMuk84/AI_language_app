import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/learning_constants.dart';
import '../models/conversation_turn.dart';
import '../models/dictation_result.dart';
import '../models/exercise_type.dart';
import '../models/pronunciation_result.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';
import '../utils/id_utils.dart';
import 'sentence_hidden_toggle_mixin.dart';

class ShadowingState {
  const ShadowingState({
    this.isLoadingSentence = true,
    this.loadError,
    this.turnId,
    this.sentence,
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
class ShadowingViewModel extends Notifier<ShadowingState>
    with SentenceHiddenToggleMixin<ShadowingState> {
  @override
  ShadowingState build() => const ShadowingState();

  /// Guards against two overlapping [loadSentence] calls both racing past
  /// the "does the persisted session already have a sentence" check before
  /// either has written its result — e.g. a duplicate `initState` trigger
  /// or a rebuild landing mid-flight. Without this, both could reach
  /// `generateNextSentence` and each get back a genuinely different
  /// sentence (Gemini isn't guaranteed to repeat itself), and whichever
  /// assignment lands last would silently become "the" sentence for this
  /// turn while anything that already captured the earlier one (e.g. an
  /// `AudioPlayButton` that already started loading audio for it) would be
  /// left referencing stale text — precisely the kind of TTS/grading
  /// mismatch this method exists to prevent. Not a full mutex, just enough
  /// to make re-entrant calls within this Notifier instance a no-op.
  bool _isLoadingSentence = false;

  /// Restores the in-progress sentence from the persisted session if one
  /// exists (resume case), otherwise requests a new one and persists it.
  /// [currentSentence]/[currentTurnId] end up as the single reference for
  /// this whole turn once this returns — see [ShadowingState.sentence]'s
  /// use in the TTS player, `submitDictation`'s grading call, and
  /// `analyzePronunciation`, all of which must read the exact same value.
  Future<void> loadSentence() async {
    if (_isLoadingSentence) return;
    _isLoadingSentence = true;
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
        final history = await ref.read(conversationHistoryServiceProvider).readAll();
        sentence = await gemini.generateNextSentence(direction: 'target', history: history);
        turnId = newTurnId();
        await sessionService.setCurrentSentence(session, sentence: sentence, turnId: turnId);
      }

      state = ShadowingState(isLoadingSentence: false, turnId: turnId, sentence: sentence);
    } catch (e) {
      state = ShadowingState(isLoadingSentence: false, loadError: _messageFor(e));
    } finally {
      _isLoadingSentence = false;
    }
  }

  /// Resumes into an in-progress sentence if this screen mounts without
  /// one already loaded (e.g. app restart landed directly on
  /// ShadowingPronunciationScreen) — a no-op otherwise, so it's safe to
  /// call unconditionally from that screen's `initState`.
  Future<void> ensureSentenceLoaded() async {
    if (state.sentence != null) return;
    await loadSentence();
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

  @override
  bool sentenceHiddenOf(ShadowingState state) => state.sentenceHidden;

  @override
  ShadowingState copyWithSentenceHidden(ShadowingState state, {required bool hidden}) {
    return hidden
        ? state.copyWith(
            sentenceHidden: true,
            clearPronunciationResult: true,
            clearPronunciationError: true,
          )
        : state.copyWith(sentenceHidden: false);
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
  ///
  /// Returns true if this turn just hit [kDailyTurnLimit] — the caller
  /// should return to the entry-routing screen instead of continuing to
  /// the next exercise, since the session was auto-finalized here exactly
  /// like "학습 종료" would.
  Future<bool> completeTurnAndAdvanceToWriting() async {
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
      nextType: ExerciseType.writing,
    );
    await ref.read(conversationHistoryServiceProvider).append(turn);

    // Track this sentence for spaced review — a no-op if it's already
    // tracked (e.g. a retried/re-encountered sentence).
    final dictationResult = state.dictationResult;
    if (state.sentence != null && dictationResult != null) {
      await ref
          .read(reviewHistoryServiceProvider)
          .recordIfNew(
            sentenceInTarget: state.sentence!,
            sentenceInNative: dictationResult.translation,
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

final shadowingViewModelProvider = NotifierProvider<ShadowingViewModel, ShadowingState>(
  ShadowingViewModel.new,
);
