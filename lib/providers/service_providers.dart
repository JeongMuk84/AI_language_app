import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_key_storage_service.dart';
import '../services/config_service.dart';
import '../services/conversation_history_service.dart';
import '../services/day_boundary_service.dart';
import '../services/gemini_service.dart';
import '../services/handoff_service.dart';
import '../services/history_service.dart';
import '../services/listening_history_service.dart';
import '../services/review_history_service.dart';
import '../services/review_session_service.dart';
import '../services/session_state_service.dart';
import '../services/storage_location_service.dart';
import '../services/tts_cache_service.dart';

/// 앱 저장소의 base directory를 결정하는 `StorageLocationService`를
/// 제공하는 provider. 의존성이 없는 가장 기초 provider로, 아래 대부분의
/// provider가 이 provider를 read해서 파일 경로를 구성한다.
final storageLocationServiceProvider =
    Provider<StorageLocationService>((ref) => StorageLocationService());

/// Pacific 시간대(America/Los_Angeles, DST 반영) 기준 "오늘 날짜"와 day
/// boundary 판정을 담당하는 `DayBoundaryService`를 제공하는 provider.
/// `sessionStateServiceProvider`, `historyServiceProvider`, 그리고
/// `app_router.dart`의 `_resolveLearningEntryRoute`(세션/복습이 같은
/// Pacific 날짜에 속하는지 판단)에서 사용된다.
final dayBoundaryServiceProvider = Provider<DayBoundaryService>((ref) => DayBoundaryService());

/// `config.json`(학습 언어, 난이도, 테마 모드 등 앱 설정)을 읽고 쓰는
/// `ConfigService`를 제공하는 provider. `storageLocationServiceProvider`에
/// 의존해 파일 경로를 구성한다. `app_router.dart`의 redirect 로직,
/// `themeModeProvider`, 각 화면의 view model 등 앱 전반에서 광범위하게
/// read된다.
final configServiceProvider = Provider<ConfigService>((ref) {
  return ConfigService(storageLocationService: ref.read(storageLocationServiceProvider));
});

/// `flutter_secure_storage`에 Gemini API 키를 저장/조회/삭제하는
/// `ApiKeyStorageService`를 제공하는 provider. `app_router.dart`의
/// redirect(온보딩 1단계 판정), `ApiKeyViewModel`, `SettingsViewModel`,
/// `ResetApiKeyButton` 등에서 사용된다.
final apiKeyStorageServiceProvider =
    Provider<ApiKeyStorageService>((ref) => ApiKeyStorageService());

/// 합성된 TTS 오디오를 언어별로 캐싱하는 `TtsCacheService`를 제공하는
/// provider. `storageLocationServiceProvider`와 `configServiceProvider`에
/// 의존한다. `geminiServiceProvider`, `reviewSessionServiceProvider`,
/// `listeningHistoryServiceProvider`가 이 provider를 read해 오디오 캐시에
/// 접근한다.
final ttsCacheServiceProvider = Provider<TtsCacheService>((ref) {
  return TtsCacheService(
    storageLocationService: ref.read(storageLocationServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

/// Gemini API 호출(문장 생성, 채점, 레벨 테스트, handoff 요약, TTS 합성
/// 등)을 담당하는 `GeminiService`를 제공하는 provider.
/// `apiKeyStorageServiceProvider`(인증), `configServiceProvider`(현재
/// 학습 언어/난이도), `ttsCacheServiceProvider`(합성 결과 캐싱)를
/// 의존성으로 주입받아 구성한다. `WritingViewModel`, `ShadowingViewModel`,
/// `LevelTestViewModel`, `SettingsViewModel`, `ApiKeyViewModel` 등 여러
/// 화면/view model에서 read해서 사용한다.
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService(
    apiKeyStorage: ref.read(apiKeyStorageServiceProvider),
    configService: ref.read(configServiceProvider),
    ttsCacheService: ref.read(ttsCacheServiceProvider),
  );
});

/// 언어를 바꿔서 다시 공부할 때를 위해 이전 학습 요약(handoff)을
/// 읽고 쓰는 `HandoffService`를 제공하는 provider.
/// `storageLocationServiceProvider`에 의존한다. `app_router.dart`의
/// redirect(난이도 미설정 시 이전 handoff 확인)와 `SettingsViewModel`
/// (세션 종료 시 handoff 저장, 초기화 시 handoff 파일 삭제)에서
/// 사용된다.
final handoffServiceProvider = Provider<HandoffService>((ref) {
  return HandoffService(storageLocationService: ref.read(storageLocationServiceProvider));
});

/// 진행 중인 학습 세션 상태(현재 exercise type, sub-step, 세션 시작
/// 시각), 일일 turn 카운트, 복습 진행 상태를 읽고 쓰는
/// `SessionStateService`를 제공하는 provider.
/// `storageLocationServiceProvider`와 `dayBoundaryServiceProvider`에
/// 의존한다. `app_router.dart`(세션/복습 재개 판단),
/// `historyServiceProvider`, `dailyTurnCountProvider`, `main.dart`의
/// reset 처리 등에서 사용된다.
final sessionStateServiceProvider = Provider<SessionStateService>((ref) {
  return SessionStateService(
    storageLocationService: ref.read(storageLocationServiceProvider),
    dayBoundaryService: ref.read(dayBoundaryServiceProvider),
  );
});

/// 대화 턴(문장 생성/채점 등) 이력을 언어별로 저장/조회하는
/// `ConversationHistoryService`를 제공하는 provider.
/// `storageLocationServiceProvider`와 `configServiceProvider`에 의존한다.
/// `WritingViewModel`/`ShadowingViewModel`(턴 기록 append, 최근 컨텍스트
/// 읽기), `historyServiceProvider`, `SettingsViewModel`(초기화 시 전체
/// 언어 삭제)에서 사용된다.
final conversationHistoryServiceProvider = Provider<ConversationHistoryService>((ref) {
  return ConversationHistoryService(
    storageLocationService: ref.read(storageLocationServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

/// 하루 학습 세션을 finalize(요약 저장)하고 이력 존재 여부를 판단하는
/// `HistoryService`를 제공하는 provider. `sessionStateServiceProvider`,
/// `conversationHistoryServiceProvider`, `storageLocationServiceProvider`,
/// `dayBoundaryServiceProvider`를 의존성으로 주입받아 구성한다.
/// `app_router.dart`(세션이 다른 날짜면 finalize, 마지막 exercise type
/// 조회)와 `main.dart`의 reset 처리(`clearHistory`)에서 사용된다.
final historyServiceProvider = Provider<HistoryService>((ref) {
  return HistoryService(
    sessionStateService: ref.read(sessionStateServiceProvider),
    conversationHistoryService: ref.read(conversationHistoryServiceProvider),
    storageLocationService: ref.read(storageLocationServiceProvider),
    dayBoundaryService: ref.read(dayBoundaryServiceProvider),
  );
});

/// 복습 대상 문장 이력(정답률, 마지막 복습 시각 등)을 언어별로
/// 관리하는 `ReviewHistoryService`를 제공하는 provider.
/// `storageLocationServiceProvider`와 `configServiceProvider`에 의존한다.
/// `reviewSessionServiceProvider`, `listeningHistoryServiceProvider`,
/// `ReviewViewModel`(복습 완료 표시), `SettingsViewModel`(초기화 시
/// 이력 삭제)에서 사용된다.
final reviewHistoryServiceProvider = Provider<ReviewHistoryService>((ref) {
  return ReviewHistoryService(
    storageLocationService: ref.read(storageLocationServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

/// 실제로 복습 가능한 문장들을 모아 복습 세트를 구성하는
/// `ReviewSessionService`를 제공하는 provider.
/// `reviewHistoryServiceProvider`(복습 대상 문장), `ttsCacheServiceProvider`
/// (캐시된 오디오 유무), `configServiceProvider`(현재 언어)를 의존성으로
/// 주입받는다. `app_router.dart`의 `_resolveLearningEntryRoute`(복습할
/// 것이 있는지 판단)와 `ReviewViewModel`에서 사용된다.
final reviewSessionServiceProvider = Provider<ReviewSessionService>((ref) {
  return ReviewSessionService(
    reviewHistoryService: ref.read(reviewHistoryServiceProvider),
    ttsCacheService: ref.read(ttsCacheServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

/// 듣기 기록 화면(`ListeningHistoryScreen`)에 표시할, 오디오가 있는
/// 과거 복습 항목 목록을 구성하는 `ListeningHistoryService`를 제공하는
/// provider. `reviewHistoryServiceProvider`, `ttsCacheServiceProvider`,
/// `configServiceProvider`에 의존한다. `ListeningHistoryScreen`에서
/// `buildHistory()` 호출에 사용된다.
final listeningHistoryServiceProvider = Provider<ListeningHistoryService>((ref) {
  return ListeningHistoryService(
    reviewHistoryService: ref.read(reviewHistoryServiceProvider),
    ttsCacheService: ref.read(ttsCacheServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

/// 오늘 완료한 turn 수(0~[kDailyTurnLimit])를 비동기로 제공하는
/// `FutureProvider`. 명시적으로 invalidate하기 전까지 결과가 캐싱되므로,
/// 카운트를 변경하는 호출부(turn 완료, reset 등)는 그 뒤에 반드시
/// `ref.invalidate(dailyTurnCountProvider)`를 호출해야 이 값을 watch하는
/// 화면들이 새 값을 받는다. `WritingViewModel`과 `ShadowingViewModel`이
/// turn 완료 시 invalidate하고, `ShadowingDictationScreen`,
/// `ShadowingPronunciationScreen`, `WritingScreen`,
/// `WritingListeningScreen`이 AppBar에 표시할 turn 번호를 위해 watch한다.
/// 내부적으로 `sessionStateServiceProvider`의 `readDailyTurnCount()`를
/// 읽는다.
final dailyTurnCountProvider = FutureProvider<int>((ref) {
  return ref.read(sessionStateServiceProvider).readDailyTurnCount();
});
