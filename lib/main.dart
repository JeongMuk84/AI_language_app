import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'router/app_router.dart';
import 'services/api_key_storage_service.dart';
import 'services/config_service.dart';
import 'services/conversation_history_service.dart';
import 'services/day_boundary_service.dart';
import 'services/handoff_service.dart';
import 'services/history_service.dart';
import 'services/review_history_service.dart';
import 'services/session_state_service.dart';
import 'services/storage_location_service.dart';
import 'services/tts_cache_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/theme_mode_view_model.dart';
import 'widgets/restart_widget.dart';

/// 개발/테스트 편의를 위한 플래그들로, 정상적인 시작 라우팅이 실행되기
/// 전에 적용된다(`--dart-define=RESET_APP=true`처럼 빌드/실행 시
/// 지정). 사용 예시는 README.md의 "Development" 절 참고.
///
/// `RESET_APP=true`이면 모든 것을 지운다(API 키, config.json, 세션
/// 상태, history, handoff 파일들, 일일 turn 카운터, TTS 캐시, 복습
/// 이력, 진행 중이던 복습까지) — 아래 세 플래그를 합친 것과 동등하며,
/// 거기에 더해 config.json, handoff 파일, 일일 진행도, TTS 캐시, 복습
/// 데이터까지 지운다(이 항목들은 각자의 개별 플래그가 없는데, native/
/// target language를 지우는 부분 초기화나 일일 한도/캐시/복습 상태만
/// 오래된 채로 남기는 초기화는 의미 있는 "완전" 초기화가 아니기
/// 때문이다).
const _resetApp = bool.fromEnvironment('RESET_APP');

/// secure storage에 저장된 API 키만 지운다.
const _resetKey = bool.fromEnvironment('RESET_KEY');

/// 진행 중이던 세션 상태만 지운다.
const _resetSession = bool.fromEnvironment('RESET_SESSION');

/// 저장된 history 파일만 지운다.
const _resetHistory = bool.fromEnvironment('RESET_HISTORY');

/// 앱의 진입점(entry point). Flutter 바인딩과 timezone 데이터베이스를
/// 초기화하고, 저장 위치/설정 서비스를 준비한 뒤 마이그레이션을
/// 수행하고, dev/test용 `RESET_*` 플래그를 적용한 다음 위젯 트리를
/// 띄운다. 각 단계가 이 순서로 실행되어야 하는 이유는 아래 각 줄의
/// 주석 참고(예: timezone 초기화는 `DayBoundaryService`가 Pacific
/// 날짜를 계산하기 전에 끝나야 하고, storage/config 마이그레이션은
/// reset 플래그 적용이나 라우팅보다 먼저 끝나야 한다).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // IANA 시간대 데이터베이스를 로드해 DayBoundaryService가
  // "America/Los_Angeles"를 (DST를 반영해) 해석할 수 있게 한다 — 어떤
  // 코드든 day boundary를 읽기 전에 반드시 먼저 실행돼야 한다.
  tz_data.initializeTimeZones();

  final dayBoundaryService = DayBoundaryService();
  debugPrint(
    '[La Fly] Day boundary check - Pacific date: ${dayBoundaryService.currentPacificDate()}, '
    'device local date: ${DateTime.now()}',
  );

  final storageLocationService = StorageLocationService();
  final baseDir = await storageLocationService.baseDirectory();
  debugPrint('[La Fly] Storage directory: ${baseDir.path}');
  await storageLocationService.migrateLegacyDataIfNeeded();

  final configService = ConfigService(storageLocationService: storageLocationService);
  debugPrint('[La Fly] config.json path: ${await configService.configFilePath()}');
  await storageLocationService.migrateToPerLanguageStorageIfNeeded(configService: configService);

  await applyResetFlags(
    configService: configService,
    storageLocationService: storageLocationService,
    dayBoundaryService: dayBoundaryService,
  );

  runApp(
    const RestartWidget(
      child: ProviderScope(child: MyApp()),
    ),
  );
}

/// 전달된 `RESET_*` dart-define 플래그들을, 정상적인 라우팅 로직이
/// 실행되기 전에 적용한다. 각 자원은 그것을 소유한 서비스 자신의
/// `clear*` 메서드로 지워지며 — 이는 Settings 화면의 "Reset All Data"
/// 버튼이 사용하는 메서드와 동일하다 — 따라서 이 함수는 초기화 로직을
/// 다시 구현한 것이 아니라, 단지 플래그를 읽어 해당 메서드를 호출해
/// 주는 접착 코드(glue)일 뿐이다.
///
/// [configService], [storageLocationService], [dayBoundaryService]는
/// 각 서비스 인스턴스를 재구성하지 않고 재사용하기 위해 `main()`으로부터
/// 전달받는다. 부작용으로 `_resetApp`/`_resetKey`/`_resetSession`/
/// `_resetHistory` 값에 따라 API 키, config.json, 세션 상태, history,
/// handoff 파일, 일일 진행도, TTS 캐시, 복습 이력/진행상태, 대화 이력을
/// 실제로 삭제하고, 어떤 항목을 지우고 어떤 항목을 보존했는지
/// `debugPrint`로 로그를 남긴다.
Future<void> applyResetFlags({
  required ConfigService configService,
  required StorageLocationService storageLocationService,
  required DayBoundaryService dayBoundaryService,
}) async {
  final targets = <String, bool>{
    'API Key': _resetApp || _resetKey,
    'config.json': _resetApp,
    'session state': _resetApp || _resetSession,
    'history': _resetApp || _resetHistory,
    'handoff files': _resetApp,
    'daily progress': _resetApp,
    'TTS cache (all languages)': _resetApp,
    'review history (all languages)': _resetApp,
    'review progress': _resetApp,
    'conversation history (all languages)': _resetApp,
  };

  if (!targets.values.any((shouldClear) => shouldClear)) {
    return;
  }

  if (targets['API Key']!) {
    await ApiKeyStorageService().clearApiKey();
  }
  if (targets['config.json']!) {
    await configService.clearConfig();
  }
  final sessionStateService = SessionStateService(
    storageLocationService: storageLocationService,
    dayBoundaryService: dayBoundaryService,
  );
  if (targets['session state']!) {
    await sessionStateService.clearSession();
  }
  if (targets['history']!) {
    await HistoryService(
      storageLocationService: storageLocationService,
      sessionStateService: sessionStateService,
      dayBoundaryService: dayBoundaryService,
      conversationHistoryService: ConversationHistoryService(
        storageLocationService: storageLocationService,
        configService: configService,
      ),
    ).clearHistory();
  }
  if (targets['handoff files']!) {
    await HandoffService(storageLocationService: storageLocationService).clearHandoffFiles();
  }
  if (targets['daily progress']!) {
    await sessionStateService.clearDailyProgress();
  }
  if (targets['TTS cache (all languages)']!) {
    await TtsCacheService(
      storageLocationService: storageLocationService,
      configService: configService,
    ).clearCache();
  }
  if (targets['review history (all languages)']!) {
    await ReviewHistoryService(
      storageLocationService: storageLocationService,
      configService: configService,
    ).clearHistory();
  }
  if (targets['review progress']!) {
    await sessionStateService.clearReviewProgress();
  }
  if (targets['conversation history (all languages)']!) {
    await ConversationHistoryService(
      storageLocationService: storageLocationService,
      configService: configService,
    ).clearAllLanguages();
  }

  final cleared = targets.entries.where((e) => e.value).map((e) => e.key).join(', ');
  final preserved = targets.entries.where((e) => !e.value).map((e) => e.key).join(', ');
  debugPrint(
    '[RESET] Cleared: $cleared.'
    '${preserved.isEmpty ? '' : ' Preserved: $preserved.'}',
  );
}

/// 앱의 루트 위젯. `routerProvider`(`go_router` 설정)와
/// `themeModeProvider`(현재 테마 모드)를 watch해서, 그 값에 맞는
/// `MaterialApp.router`를 구성한다. `main()`에서 `RestartWidget`과
/// `ProviderScope`로 감싸져 `runApp`에 전달된다.
class MyApp extends ConsumerWidget {
  /// `MyApp`을 생성한다. `super.key`를 그대로 전달하는 것 외에 별도
  /// 로직은 없다.
  const MyApp({super.key});

  /// 현재 [router]와 [themeModeAsync](테마 모드 로딩 상태에 따라
  /// data/loading/error)를 기반으로 위젯 트리를 만든다. 테마 로딩이
  /// 끝나면 실제 `MaterialApp.router`를, 로딩 중에는 스피너를, 에러
  /// 발생 시에는 에러 메시지를 보여주는 `MaterialApp`을 반환한다.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeModeAsync = ref.watch(themeModeProvider);

    return themeModeAsync.when(
      data: (mode) => MaterialApp.router(
        title: 'La Fly',
        theme: themeDataFor(mode),
        routerConfig: router,
      ),
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (error, stackTrace) => MaterialApp(
        home: Scaffold(body: Center(child: Text('Failed to load settings: $error'))),
      ),
    );
  }
}
