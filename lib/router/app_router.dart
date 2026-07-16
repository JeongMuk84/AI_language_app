import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/exercise_type.dart';
import '../providers/service_providers.dart';
import '../screens/api_key_screen.dart';
import '../screens/language_select_screen.dart';
import '../screens/learning_screen.dart';
import '../screens/level_test_screen.dart';
import '../screens/review_placeholder_screen.dart';
import '../screens/shadowing_dictation_screen.dart';
import '../screens/shadowing_pronunciation_screen.dart';
import '../screens/writing_listening_screen.dart';
import '../screens/writing_screen.dart';
import '../services/history_service.dart';
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
      GoRoute(
        path: AppRoutes.review,
        builder: (context, state) => const ReviewPlaceholderScreen(),
      ),
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

/// Section 3 of the core-learning-loop spec: decides where to land when
/// entering `/learning`.
///
/// (A) An in-progress session exists: same local calendar day -> resume
///     straight into the persisted exercise type's entry screen. A
///     different day (midnight passed) -> finalize it exactly like
///     "학습 종료" would, then fall through to (B).
/// (B) No in-progress session: no history at all -> brand new session,
///     start at shadowing. Otherwise -> ReviewPlaceholderScreen.
Future<String> _resolveLearningEntryRoute({
  required SessionStateService sessionStateService,
  required HistoryService historyService,
}) async {
  final session = await sessionStateService.readState();

  if (session != null) {
    final now = DateTime.now();
    final startedAt = session.sessionStartedAt;
    final sameDay =
        startedAt.year == now.year && startedAt.month == now.month && startedAt.day == now.day;

    if (sameDay) {
      return session.currentExerciseType == ExerciseType.shadowing
          ? AppRoutes.shadowingDictation
          : AppRoutes.writing;
    }

    await historyService.finalizeSession();
  }

  final hasHistory = await historyService.hasAnyHistory();
  if (!hasHistory) {
    await sessionStateService.startNewSession(initialType: ExerciseType.shadowing);
    return AppRoutes.shadowingDictation;
  }

  return AppRoutes.review;
}
