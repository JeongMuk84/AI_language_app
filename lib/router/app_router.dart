import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/service_providers.dart';
import '../screens/api_key_screen.dart';
import '../screens/language_select_screen.dart';
import '../screens/learning_screen.dart';
import '../screens/level_test_screen.dart';
import '../viewmodels/conversation_session_view_model.dart';

abstract final class AppRoutes {
  static const apiKey = '/api-key';
  static const languageSelect = '/language-select';
  static const levelTest = '/level-test';
  static const learning = '/learning';
}

/// Single source of truth for onboarding progress: on every navigation,
/// checks (in order) API key -> languages -> difficulty level, and redirects
/// to the first unmet step. Screens navigate to `/` after each step and let
/// this decide where to go next, instead of hard-coding the next screen.
final routerProvider = Provider<GoRouter>((ref) {
  final apiKeyStorage = ref.read(apiKeyStorageServiceProvider);
  final configService = ref.read(configServiceProvider);
  final handoffService = ref.read(handoffServiceProvider);
  final conversationSession = ref.read(conversationSessionProvider.notifier);

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

      return location == AppRoutes.learning ? null : AppRoutes.learning;
    },
    routes: [
      GoRoute(
        path: AppRoutes.apiKey,
        builder: (context, state) => const ApiKeyScreen(),
      ),
      GoRoute(
        path: AppRoutes.languageSelect,
        builder: (context, state) => const LanguageSelectScreen(),
      ),
      GoRoute(
        path: AppRoutes.levelTest,
        builder: (context, state) => const LevelTestScreen(),
      ),
      GoRoute(
        path: AppRoutes.learning,
        builder: (context, state) => const LearningScreen(),
      ),
    ],
  );
});
