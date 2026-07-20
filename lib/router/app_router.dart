import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/exercise_type.dart';
import '../models/learning_sub_step.dart';
import '../models/review_progress.dart';
import '../providers/service_providers.dart';
import '../screens/api_key_screen.dart';
import '../screens/language_select_screen.dart';
import '../screens/learning_screen.dart';
import '../screens/level_test_screen.dart';
import '../screens/review_screen.dart';
import '../screens/shadowing_dictation_screen.dart';
import '../screens/shadowing_pronunciation_screen.dart';
import '../screens/writing_listening_screen.dart';
import '../screens/writing_screen.dart';
import '../services/day_boundary_service.dart';
import '../services/history_service.dart';
import '../services/review_session_service.dart';
import '../services/session_state_service.dart';
import '../viewmodels/conversation_session_view_model.dart';

abstract final class AppRoutes {
  static const apiKey = '/api-key';
  static const languageSelect = '/language-select';
  static const levelTest = '/level-test';

  /// Bootstrap-only entry point — never rendered for long. Redirect always
  /// resolves it into one of the routes below based on session/history
  /// state (see `_resolveLearningEntryRoute`).
  static const learning = '/learning';

  static const review = '/learning/review';
  static const shadowingDictation = '/learning/shadowing/dictation';
  static const shadowingPronunciation = '/learning/shadowing/pronunciation';
  static const writing = '/learning/writing';
  static const writingListening = '/learning/writing/listening';
}

/// The learning-loop screens manage their own step-to-step navigation
/// (dictation -> pronunciation -> writing -> listening -> dictation...) via
/// direct `context.go(...)` calls. Redirect must leave them alone — it only
/// decides where to *enter* the loop, at `/learning`.
const _learningSubRoutes = {
  AppRoutes.review,
  AppRoutes.shadowingDictation,
  AppRoutes.shadowingPronunciation,
  AppRoutes.writing,
  AppRoutes.writingListening,
};

/// Single source of truth for onboarding progress: on every navigation,
/// checks (in order) API key -> languages -> difficulty level, and redirects
/// to the first unmet step. Screens navigate to `/` after each step and let
/// this decide where to go next, instead of hard-coding the next screen.
final routerProvider = Provider<GoRouter>((ref) {
  final apiKeyStorage = ref.read(apiKeyStorageServiceProvider);
  final configService = ref.read(configServiceProvider);
  final handoffService = ref.read(handoffServiceProvider);
  final conversationSession = ref.read(conversationSessionProvider.notifier);
  final sessionStateService = ref.read(sessionStateServiceProvider);
  final historyService = ref.read(historyServiceProvider);
  final reviewSessionService = ref.read(reviewSessionServiceProvider);
  final dayBoundaryService = ref.read(dayBoundaryServiceProvider);

  return GoRouter(
    initialLocation: AppRoutes.apiKey,
    redirect: (context, state) async {
      final location = state.matchedLocation;

      final hasApiKey = await apiKeyStorage.hasApiKey();
      if (!hasApiKey) {
        return location == AppRoutes.apiKey ? null : AppRoutes.apiKey;
      }

      final config = await configService.readConfig();
      if (!config.hasLanguages) {
        return location == AppRoutes.languageSelect ? null : AppRoutes.languageSelect;
      }

      if (!config.hasDifficultyLevel) {
        // No level yet for this target language — check whether we have a
        // handoff file from a previous stint studying it before falling
        // back to a fresh level test.
        final targetLanguage = config.targetLanguage;
        final handoff = (targetLanguage != null && targetLanguage.isNotEmpty)
            ? await handoffService.read(targetLanguage)
            : null;

        if (handoff != null && (handoff.difficultyLevel?.isNotEmpty ?? false)) {
          conversationSession.seedWithContext(handoff.summary);
          await configService.updateConfig(
            (c) => c.copyWith(difficultyLevel: handoff.difficultyLevel),
          );
          return location == AppRoutes.learning ? null : AppRoutes.learning;
        }

        return location == AppRoutes.levelTest ? null : AppRoutes.levelTest;
      }

      // Onboarding is fully complete. Leave in-loop navigation to the
      // screens themselves; only bootstrap when landing on `/learning`.
      if (_learningSubRoutes.contains(location)) {
        return null;
      }

      return _resolveLearningEntryRoute(
        sessionStateService: sessionStateService,
        historyService: historyService,
        reviewSessionService: reviewSessionService,
        dayBoundaryService: dayBoundaryService,
      );
    },
    routes: [
      GoRoute(path: AppRoutes.apiKey, builder: (context, state) => const ApiKeyScreen()),
      GoRoute(
        path: AppRoutes.languageSelect,
        builder: (context, state) => const LanguageSelectScreen(),
      ),
      GoRoute(path: AppRoutes.levelTest, builder: (context, state) => const LevelTestScreen()),
      GoRoute(path: AppRoutes.learning, builder: (context, state) => const LearningScreen()),
      GoRoute(path: AppRoutes.review, builder: (context, state) => const ReviewScreen()),
      GoRoute(
        path: AppRoutes.shadowingDictation,
        builder: (context, state) => const ShadowingDictationScreen(),
      ),
      GoRoute(
        path: AppRoutes.shadowingPronunciation,
        builder: (context, state) => const ShadowingPronunciationScreen(),
      ),
      GoRoute(path: AppRoutes.writing, builder: (context, state) => const WritingScreen()),
      GoRoute(
        path: AppRoutes.writingListening,
        builder: (context, state) => const WritingListeningScreen(),
      ),
    ],
  );
});

/// Starts a new learning session continuing from whichever exercise type
/// the learner didn't finish on last time (shadowing, if none yet), and
/// returns the route for its entry screen. The single place this decision
/// is made — shared by the router (when there's nothing left to review)
/// and ReviewScreen (finishing/skipping review), so it exists in exactly
/// one place rather than being reimplemented at each call site.
Future<String> startNextLearningSession({
  required SessionStateService sessionStateService,
  required HistoryService historyService,
}) async {
  final lastType = await historyService.getLastExerciseType();
  final nextType = (lastType ?? ExerciseType.writing).other;
  await sessionStateService.startNewSession(initialType: nextType);
  return nextType == ExerciseType.shadowing
      ? AppRoutes.shadowingDictation
      : AppRoutes.writing;
}

/// Section 3 of the core-learning-loop spec: decides where to land when
/// entering `/learning`.
///
/// (A) An in-progress session exists: same Pacific calendar day (see
///     `DayBoundaryService`) -> resume straight into the persisted
///     exercise type + sub-step's screen (e.g. shadowing pronunciation,
///     not dictation, if that's where the learner was — see
///     `LearningSubStep`). A different day -> finalize it exactly like
///     "학습 종료" would, then fall through to (B).
/// (B) No in-progress session: an in-progress review exists (same Pacific
///     calendar day) -> resume it. Otherwise, build a fresh review set
///     directly from `ReviewSessionService` — empty (nothing reviewable,
///     including a genuinely brand-new learner with no history at all) ->
///     (C); otherwise persist it and go review.
/// (C) Start a new learning session (see `startNextLearningSession`).
Future<String> _resolveLearningEntryRoute({
  required SessionStateService sessionStateService,
  required HistoryService historyService,
  required ReviewSessionService reviewSessionService,
  required DayBoundaryService dayBoundaryService,
}) async {
  final now = DateTime.now();
  debugPrint(
    '[La Fly] Day boundary check - Pacific date: ${dayBoundaryService.currentPacificDate()}, '
    'device local date: $now',
  );

  final session = await sessionStateService.readState();

  if (session != null) {
    final sameDay = dayBoundaryService.isSamePacificDay(session.sessionStartedAt, now);
    debugPrint(
      '[La Fly] Session check - sessionStartedAt: ${session.sessionStartedAt}, '
      'same Pacific day as now: $sameDay',
    );

    if (sameDay) {
      final onSecondSubStep = session.currentSubStep == LearningSubStep.second;
      if (session.currentExerciseType == ExerciseType.shadowing) {
        return onSecondSubStep ? AppRoutes.shadowingPronunciation : AppRoutes.shadowingDictation;
      }
      return onSecondSubStep ? AppRoutes.writingListening : AppRoutes.writing;
    }

    await historyService.finalizeSession();
  }

  final reviewProgress = await sessionStateService.readReviewProgress();
  if (reviewProgress != null) {
    return AppRoutes.review;
  }

  // Deciding "is there anything to review" directly from the actual
  // review-eligible data (ReviewSessionService, backed by
  // ReviewHistoryService + TtsCacheService) rather than
  // `historyService.hasAnyHistory()` (whether a day-summary file happens
  // to exist) — the latter is a side artifact only written when
  // `finalizeSession` successfully runs with a non-empty conversation
  // history, so it can go stale/empty while real, reviewable learning
  // data already exists (observed live: history/ empty, but
  // review_history/<language>/review_history.json full of real entries
  // with cached audio) and incorrectly skip straight past review.
  // `buildReviewSet()` already returns an empty list cheaply (a single
  // empty-map read) for a genuinely brand-new learner, so this isn't a
  // meaningfully more expensive check for that case.
  final reviewSet = await reviewSessionService.buildReviewSet();
  if (reviewSet.isEmpty) {
    return startNextLearningSession(
      sessionStateService: sessionStateService,
      historyService: historyService,
    );
  }

  await sessionStateService.writeReviewProgress(
    ReviewProgress(reviewItemList: reviewSet, reviewCurrentIndex: 0, startedAt: now),
  );
  return AppRoutes.review;
}
