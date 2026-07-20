import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';
import '../models/handoff_data.dart';
import '../models/learning_session_snapshot.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import 'conversation_session_view_model.dart';
import 'theme_mode_view_model.dart';

enum SettingsSaveResult { validationFailed, saved, savedWithRestart }

class SettingsState {
  const SettingsState({this.isSaving = false, this.errorMessage, this.infoMessage});

  final bool isSaving;
  final String? errorMessage;
  final String? infoMessage;

  SettingsState copyWith({
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    String? infoMessage,
    bool clearInfo = false,
  }) {
    return SettingsState(
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    );
  }
}

class SettingsViewModel extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  Future<SettingsSaveResult> save({
    required String nativeLanguage,
    required String targetLanguage,
    required AppThemeMode themeMode,
  }) async {
    final native = nativeLanguage.trim();
    final target = targetLanguage.trim();
    if (native.isEmpty || target.isEmpty) {
      state = state.copyWith(errorMessage: 'Please fill in both languages.');
      return SettingsSaveResult.validationFailed;
    }

    state = state.copyWith(isSaving: true, clearError: true, clearInfo: true);

    final configService = ref.read(configServiceProvider);
    final current = await configService.readConfig();
    final targetChanged =
        (current.targetLanguage?.isNotEmpty ?? false) && current.targetLanguage != target;

    if (!targetChanged) {
      await configService.updateConfig(
        (c) => c.copyWith(nativeLanguage: native, targetLanguage: target),
      );
      // Persists themeMode to config.json AND updates the in-memory
      // provider so MaterialApp picks up the new theme immediately —
      // writing to config.json alone left the live app on the old theme
      // until the next full restart.
      await ref.read(themeModeProvider.notifier).setThemeMode(themeMode);
      state = state.copyWith(isSaving: false);
      return SettingsSaveResult.saved;
    }

    // Target language changed: hand off the old language before switching.
    final oldTarget = current.targetLanguage!;

    String? summary;
    try {
      final snapshot = LearningSessionSnapshot(
        nativeLanguage: current.nativeLanguage ?? native,
        targetLanguage: oldTarget,
        difficultyLevel: current.difficultyLevel,
        conversationHistory: ref.read(conversationSessionProvider).history,
      );
      summary = await ref.read(geminiServiceProvider).generateHandoffSummary(snapshot);
    } catch (_) {
      summary = null;
    }

    if (summary != null && summary.isNotEmpty) {
      await ref.read(handoffServiceProvider).write(
            oldTarget,
            HandoffData(
              language: oldTarget,
              summary: summary,
              generatedAt: DateTime.now().toIso8601String(),
              difficultyLevel: current.difficultyLevel,
            ),
          );
    } else {
      state = state.copyWith(
        infoMessage: "Couldn't save a learning summary for $oldTarget, but continuing.",
      );
    }

    // Local multi-turn history only lives in this session provider — Gemini
    // itself keeps no memory between requests — so switching languages just
    // means clearing it.
    ref.read(conversationSessionProvider.notifier).reset();

    // The in-progress "what am I doing right this second" state
    // (current sentence/turn/sub-step, in-progress review) belongs to
    // whichever language was active when it was written — resuming it
    // under the NEW language is exactly the bug this fixes (switching
    // Vietnamese -> Spanish -> Vietnamese was showing a leftover Spanish
    // sentence, because nothing here ever cleared session_state.json).
    // `RestartWidget` only remounts the widget tree; it does not touch
    // these persisted files, so they must be cleared explicitly.
    //
    // This must NOT clear each language's own `audio_cache`/
    // `review_history`/`conversation_history` (see those services'
    // `clear*` docs) — switching back to a language the learner already
    // studied should find that language's own data exactly as they left
    // it, not wiped. Only `resetAllData` wipes those, for every language.
    final sessionStateService = ref.read(sessionStateServiceProvider);
    await sessionStateService.clearSession();
    await sessionStateService.clearReviewProgress();

    await configService.writeConfig(
      AppConfig(
        nativeLanguage: native,
        targetLanguage: target,
        themeMode: themeMode.configValue,
      ),
    );
    // Keep the in-memory theme in sync too, in case anything renders in the
    // brief window before RestartWidget actually tears the tree down.
    await ref.read(themeModeProvider.notifier).setThemeMode(themeMode);

    state = state.copyWith(isSaving: false);
    return SettingsSaveResult.savedWithRestart;
  }

  /// Wipes every piece of saved app state, for every language: the API
  /// key, config.json, the in-progress session, all history files, all
  /// per-language handoff files, the daily turn counter, every language's
  /// TTS cache, review history, and conversation history, and any
  /// in-progress review. The caller is responsible for restarting the app
  /// afterward (via `RestartWidget`) so everything re-derives from scratch.
  ///
  /// Distinct from a target-language switch (see [save]), which clears
  /// only the current in-progress session/review and leaves every
  /// language's cache/history/conversation data intact.
  Future<void> resetAllData() async {
    final sessionStateService = ref.read(sessionStateServiceProvider);
    await ref.read(apiKeyStorageServiceProvider).clearApiKey();
    await ref.read(configServiceProvider).clearConfig();
    await sessionStateService.clearSession();
    await ref.read(historyServiceProvider).clearHistory();
    await ref.read(handoffServiceProvider).clearHandoffFiles();
    await sessionStateService.clearDailyProgress();
    await ref.read(ttsCacheServiceProvider).clearCache();
    await ref.read(reviewHistoryServiceProvider).clearHistory();
    await sessionStateService.clearReviewProgress();
    await ref.read(conversationHistoryServiceProvider).clearAllLanguages();
  }
}

final settingsViewModelProvider = NotifierProvider<SettingsViewModel, SettingsState>(
  SettingsViewModel.new,
);
