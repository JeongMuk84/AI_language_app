import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/learning_constants.dart';
import '../models/pronunciation_result.dart';
import '../models/review_item.dart';
import '../models/review_progress.dart';
import '../models/translation_result.dart';
import '../providers/service_providers.dart';
import '../router/app_router.dart';
import '../services/gemini_service.dart';

class ReviewState {
  const ReviewState({
    this.isLoading = true,
    this.loadError,
    this.items = const [],
    this.currentIndex = 0,
    this.startedAt,
    this.isSubmittingTranslation = false,
    this.translationResult,
    this.translationError,
    this.translationWarning,
    this.lastUserTranslation,
    this.isAnalyzingPronunciation = false,
    this.pronunciationResult,
    this.pronunciationError,
  });

  final bool isLoading;
  final String? loadError;
  final List<ReviewItem> items;
  final int currentIndex;
  final DateTime? startedAt;

  final bool isSubmittingTranslation;
  final TranslationResult? translationResult;
  final String? translationError;

  /// Client-side-only guard message (e.g. "write a complete sentence")
  /// shown when Submit was tapped with an empty/whitespace-only textbox —
  /// deliberately never sends that to `validateTranslation`, so it costs
  /// no API call. Distinct from [translationResult]: this never represents
  /// an actual graded attempt, so it doesn't affect [isTranslationCorrect]
  /// or get persisted into review progress.
  final String? translationWarning;
  final String? lastUserTranslation;

  final bool isAnalyzingPronunciation;
  final PronunciationResult? pronunciationResult;
  final String? pronunciationError;

  ReviewItem? get currentItem => currentIndex < items.length ? items[currentIndex] : null;

  /// True once every item has been shown (including the edge case where
  /// the last few were skipped for missing cached audio) — ReviewScreen
  /// treats this the same as "nothing to review" rather than rendering a
  /// blank per-item view.
  bool get isExhausted => items.isNotEmpty && currentIndex >= items.length;

  /// True only once a *correctly*-graded translation has been submitted —
  /// not just "submitted at least once". Drives both the textbox/Submit
  /// button lock (ReviewScreen) and [canAdvance] below.
  bool get isTranslationCorrect => translationResult?.isCorrect ?? false;

  bool get isLastItem => items.isNotEmpty && currentIndex == items.length - 1;

  /// "Next Sentence" / "Finish Review & Start Learning" unlocks only once
  /// the translation has been graded *correct* and pronunciation has
  /// passed — a wrong translation can't be advanced past, however good the
  /// pronunciation attempt was.
  bool get canAdvance =>
      isTranslationCorrect &&
      pronunciationResult != null &&
      pronunciationResult!.accuracyPercent >= kPronunciationPassThreshold;

  ReviewState copyWith({
    bool? isLoading,
    String? loadError,
    List<ReviewItem>? items,
    int? currentIndex,
    DateTime? startedAt,
    bool? isSubmittingTranslation,
    TranslationResult? translationResult,
    bool clearTranslationResult = false,
    String? translationError,
    bool clearTranslationError = false,
    String? translationWarning,
    bool clearTranslationWarning = false,
    String? lastUserTranslation,
    bool? isAnalyzingPronunciation,
    PronunciationResult? pronunciationResult,
    bool clearPronunciationResult = false,
    String? pronunciationError,
    bool clearPronunciationError = false,
  }) {
    return ReviewState(
      isLoading: isLoading ?? this.isLoading,
      loadError: loadError,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      startedAt: startedAt ?? this.startedAt,
      isSubmittingTranslation: isSubmittingTranslation ?? this.isSubmittingTranslation,
      translationResult: clearTranslationResult
          ? null
          : (translationResult ?? this.translationResult),
      translationError: clearTranslationError
          ? null
          : (translationError ?? this.translationError),
      translationWarning: clearTranslationWarning
          ? null
          : (translationWarning ?? this.translationWarning),
      lastUserTranslation: lastUserTranslation ?? this.lastUserTranslation,
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

/// Backs ReviewScreen. Never calls `GeminiService.synthesizeSpeech`/
/// `speakCached` anywhere in this file — playback goes straight through
/// `TtsCacheService.get`, which only ever reads what's already cached and
/// never falls back to a fresh TTS call. That's deliberate: review must
/// never spend TTS quota (see `kMaxReviewSetSize` / `buildReviewSet`).
class ReviewViewModel extends Notifier<ReviewState> {
  @override
  ReviewState build() => const ReviewState();

  Future<void> loadReviewSet() async {
    state = const ReviewState();
    try {
      final sessionStateService = ref.read(sessionStateServiceProvider);
      var progress = await sessionStateService.readReviewProgress();

      if (progress == null) {
        // The router normally builds+persists this before ever navigating
        // here — this only runs if the screen is somehow reached without
        // that (e.g. a hot restart straight into this route in dev).
        final items = await ref.read(reviewSessionServiceProvider).buildReviewSet();
        if (items.isEmpty) {
          state = state.copyWith(isLoading: false, items: const []);
          return;
        }
        progress = ReviewProgress(
          reviewItemList: items,
          reviewCurrentIndex: 0,
          startedAt: DateTime.now(),
        );
        await sessionStateService.writeReviewProgress(progress);
      }

      state = ReviewState(
        isLoading: false,
        items: progress.reviewItemList,
        currentIndex: progress.reviewCurrentIndex,
        startedAt: progress.startedAt,
        // Restores whatever progress was already made on the *current*
        // item (submitted translation, its grading, and — if attempted —
        // the pronunciation result) so a screen remount (most commonly an
        // app restart mid-item) doesn't wipe it and re-lock Play/Record
        // behind "submit again", even though the learner already did.
        translationResult: progress.currentTranslationResult,
        lastUserTranslation: progress.currentUserTranslation,
        pronunciationResult: progress.currentPronunciationResult,
      );
      await _skipUnplayableItems();
    } catch (e) {
      state = ReviewState(isLoading: false, loadError: _messageFor(e));
    }
  }

  /// Defensive re-check: `buildReviewSet()` already filtered to sentences
  /// with cached audio, but if the cache somehow changed since (it
  /// shouldn't — review never writes to it), skip past any item that's no
  /// longer playable rather than getting stuck, logging each skip.
  Future<void> _skipUnplayableItems() async {
    final config = await ref.read(configServiceProvider).readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final ttsCache = ref.read(ttsCacheServiceProvider);

    var index = state.currentIndex;
    while (index < state.items.length) {
      final item = state.items[index];
      final location = await ttsCache.peek(sentence: item.sentenceInTarget, language: targetLanguage);
      if (location != null) break;
      // ignore: avoid_print
      print('[Review] Skipping "${item.sentenceInTarget}" — cached audio no longer available.');
      index++;
    }
    if (index != state.currentIndex) {
      state = state.copyWith(currentIndex: index);
      if (state.startedAt != null) {
        await ref
            .read(sessionStateServiceProvider)
            .writeReviewProgress(
              ReviewProgress(
                reviewItemList: state.items,
                reviewCurrentIndex: index,
                startedAt: state.startedAt!,
              ),
            );
      }
    }
  }

  Future<void> submitTranslation(String userTranslation) async {
    final item = state.currentItem;
    if (item == null) return;

    final trimmed = userTranslation.trim();
    if (trimmed.isEmpty) {
      // Never spends a validateTranslation call on nothing — this is a
      // pure client-side guard, not a graded attempt, so it doesn't touch
      // translationResult (Submit/the textbox stay unlocked either way
      // since isTranslationCorrect only looks at translationResult).
      state = state.copyWith(
        clearTranslationError: true,
        translationWarning: 'Please write a complete sentence.',
      );
      return;
    }

    state = state.copyWith(
      isSubmittingTranslation: true,
      clearTranslationError: true,
      clearTranslationWarning: true,
    );
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .validateTranslation(nativeSentence: item.sentenceInNative, userTranslation: trimmed);
      state = state.copyWith(
        isSubmittingTranslation: false,
        translationResult: result,
        lastUserTranslation: trimmed,
      );
      await _persistCurrentItemSnapshot();
    } catch (e) {
      state = state.copyWith(isSubmittingTranslation: false, translationError: _messageFor(e));
    }
  }

  /// Pronunciation is graded against the item's fixed, canonical
  /// [ReviewItem.sentenceInTarget], not whatever the learner is currently
  /// attempting to translate — so unlike the old (now-removed) gate here,
  /// this doesn't require a translation to already be submitted, matching
  /// Play/Record being available from screen entry (see ReviewScreen).
  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    final item = state.currentItem;
    if (item == null) return;
    state = state.copyWith(isAnalyzingPronunciation: true, clearPronunciationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .analyzePronunciation(audioBytes: audioBytes, targetSentence: item.sentenceInTarget);
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationResult: result);
      await _persistCurrentItemSnapshot();
    } catch (e) {
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationError: _messageFor(e));
    }
  }

  void resetPronunciationAttempt() {
    state = state.copyWith(clearPronunciationResult: true, clearPronunciationError: true);
    unawaited(_persistCurrentItemSnapshot());
  }

  /// Persists the current item's submitted translation, its grading, and
  /// (if attempted) its pronunciation result — the snapshot
  /// `loadReviewSet()` restores from if this screen is remounted before the
  /// learner advances past this item. A no-op before the review set itself
  /// has been persisted at least once (`state.startedAt == null`).
  Future<void> _persistCurrentItemSnapshot() async {
    if (state.startedAt == null) return;
    await ref.read(sessionStateServiceProvider).writeReviewProgress(
          ReviewProgress(
            reviewItemList: state.items,
            reviewCurrentIndex: state.currentIndex,
            startedAt: state.startedAt!,
            currentUserTranslation: state.lastUserTranslation,
            currentTranslationResult: state.translationResult,
            currentPronunciationResult: state.pronunciationResult,
          ),
        );
  }

  /// "Next Sentence" / "Finish Review & Start Learning". Marks the current
  /// item reviewed, then either advances in place or — on the last item —
  /// clears review progress and starts the next learning session. Returns
  /// the route the caller should navigate to.
  Future<String> advance() async {
    final item = state.currentItem;
    if (item != null) {
      await ref.read(reviewHistoryServiceProvider).markReviewed(item.sentenceInTarget);
    }

    final sessionStateService = ref.read(sessionStateServiceProvider);
    if (state.isLastItem) {
      await sessionStateService.clearReviewProgress();
      return startNextLearningSession(
        sessionStateService: sessionStateService,
        historyService: ref.read(historyServiceProvider),
      );
    }

    final nextIndex = state.currentIndex + 1;
    await sessionStateService.writeReviewProgress(
      ReviewProgress(
        reviewItemList: state.items,
        reviewCurrentIndex: nextIndex,
        startedAt: state.startedAt ?? DateTime.now(),
      ),
    );
    state = ReviewState(
      isLoading: false,
      items: state.items,
      currentIndex: nextIndex,
      startedAt: state.startedAt,
    );
    await _skipUnplayableItems();
    return AppRoutes.review;
  }

  /// "Skip Review & Start Learning": leaves already-reviewed items' marks
  /// alone (never rewound), just abandons whatever's left.
  Future<String> skip() async {
    final sessionStateService = ref.read(sessionStateServiceProvider);
    await sessionStateService.clearReviewProgress();
    return startNextLearningSession(
      sessionStateService: sessionStateService,
      historyService: ref.read(historyServiceProvider),
    );
  }

  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }
}

final reviewViewModelProvider = NotifierProvider<ReviewViewModel, ReviewState>(
  ReviewViewModel.new,
);
