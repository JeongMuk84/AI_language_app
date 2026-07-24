import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';
import '../models/handoff_data.dart';
import '../models/learning_session_snapshot.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import 'conversation_session_view_model.dart';
import 'theme_mode_view_model.dart';

/// [SettingsViewModel.save]의 결과. `validationFailed`는 입력값이 비어있는
/// 등 저장 자체를 시도하지 못한 경우, `saved`는 학습 언어(target language)를
/// 바꾸지 않고 저장이 끝난 경우, `savedWithRestart`는 학습 언어가 바뀌어
/// 세션 데이터를 정리한 뒤 앱을 재시작해야 하는 경우다. SettingsDialog는 이
/// 값에 따라 다이얼로그를 닫기만 할지, `RestartWidget.restartApp`까지
/// 호출할지를 결정한다.
enum SettingsSaveResult { validationFailed, saved, savedWithRestart }

/// SettingsDialog가 watch하는 UI 상태.
class SettingsState {
  const SettingsState({this.isSaving = false, this.errorMessage, this.infoMessage});

  /// [SettingsViewModel.save]가 진행되는 동안 true가 되어, SettingsDialog의
  /// Save 버튼을 비활성화하고 로딩 인디케이터를 보여주게 한다.
  final bool isSaving;

  /// 저장 실패(입력값 검증 실패 등) 시 사용자에게 보여줄 에러 메시지.
  final String? errorMessage;

  /// 에러는 아니지만 참고삼아 보여줄 안내 메시지. 예를 들어 언어 전환 시
  /// handoff 요약 생성에 실패했지만 전환 자체는 계속 진행된다는 안내에
  /// 쓰인다.
  final String? infoMessage;

  /// [isSaving]/[errorMessage]/[infoMessage]를 갱신한 새 SettingsState를
  /// 반환한다. `errorMessage`/`infoMessage`는 각각 [clearError]/[clearInfo]가
  /// true일 때만 명시적으로 null이 되고, 그 외에는 새 값이 없으면 이전 값을
  /// 유지한다.
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

/// SettingsDialog(모든 화면의 Settings 아이콘 버튼에서 모달로 열림)를
/// 지원하는 뷰모델. 모국어/학습 언어/테마 저장, 학습 언어 전환 시의 handoff
/// 처리, 그리고 전체 데이터 초기화(resetAllData)를 담당한다.
class SettingsViewModel extends Notifier<SettingsState> {
  /// 초기 상태(저장 중 아님, 메시지 없음)를 생성한다. Riverpod이 이 provider가
  /// 처음 watch/read될 때 자동으로 호출한다.
  @override
  SettingsState build() => const SettingsState();

  /// SettingsDialog의 Save 버튼이 눌리면 호출된다. [nativeLanguage]/
  /// [targetLanguage]/[themeMode]를 저장한다.
  ///
  /// 학습 언어([targetLanguage])가 기존 값과 다르지 않으면 언어/테마만 바로
  /// 저장하고 [SettingsSaveResult.saved]를 반환한다.
  ///
  /// 학습 언어가 바뀌는 경우에는 먼저 이전 언어의 학습 세션을 정리한다:
  /// 현재까지의 대화 기록([ConversationSessionViewModel.history])으로
  /// `GeminiService.generateHandoffSummary`를 호출해 요약을 만들고
  /// `handoffServiceProvider`에 저장해두었다가(실패해도 계속 진행하며
  /// [SettingsState.infoMessage]로 안내), 대화 세션을 리셋하고, 진행 중이던
  /// 학습/리뷰 세션 상태(session_state.json 등)를 지운 뒤 새 설정을 저장한다.
  /// 이 경우 [SettingsSaveResult.savedWithRestart]를 반환하며,
  /// SettingsDialog는 이를 받아 `RestartWidget.restartApp`으로 앱을
  /// 재시작시킨다.
  ///
  /// 두 언어 중 하나라도 비어 있으면 아무 것도 저장하지 않고
  /// [SettingsSaveResult.validationFailed]를 반환한다.
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

  /// SettingsDialog의 "초기화(Hold to reset)" 버튼([HoldToResetButton])이
  /// 눌리면 호출된다. 저장된 앱 상태를 언어 구분 없이 모조리 지운다: API 키,
  /// config.json, 진행 중이던 세션, 모든 history 파일, 언어별 handoff 파일,
  /// 일일 턴 카운터, 모든 언어의 TTS 캐시, 리뷰 히스토리, 대화 히스토리,
  /// 진행 중이던 리뷰, 오늘 복습을 마쳤다는 표시까지 전부 대상이다.
  /// 호출한 쪽(SettingsDialog)이 이후
  /// `RestartWidget`으로 앱을 재시작시켜 모든 상태가 처음부터 다시
  /// 계산되도록 해야 한다.
  ///
  /// 학습 언어 전환([save] 참고)과는 다르다 — 전환은 현재 진행 중인
  /// 세션/리뷰만 지우고 각 언어별 캐시/히스토리/대화 데이터는 그대로
  /// 남겨두지만, 이 메서드는 모든 언어의 데이터를 완전히 지운다.
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
    await sessionStateService.clearReviewedTodayFlag();
    await ref.read(conversationHistoryServiceProvider).clearAllLanguages();
  }
}

/// [SettingsViewModel]/[SettingsState]를 노출하는 provider. SettingsDialog에서
/// `ref.watch`(상태 렌더링)와 `ref.read(...notifier)`(save/resetAllData
/// 호출)로 사용된다.
final settingsViewModelProvider = NotifierProvider<SettingsViewModel, SettingsState>(
  SettingsViewModel.new,
);
