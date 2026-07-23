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

/// 앱에서 사용하는 모든 route 경로 문자열을 한곳에 모아둔 상수 모음.
/// `GoRouter`의 `routes` 목록과 `redirect` 로직, 그리고 각 화면의
/// `context.go(...)` 호출부가 모두 이 상수를 참조해 경로 문자열을
/// 중복 하드코딩하지 않도록 한다.
abstract final class AppRoutes {
  /// API 키 입력 화면(`ApiKeyScreen`) 경로. 온보딩의 첫 단계이며,
  /// `redirect`에서 API 키가 없을 때 항상 이 경로로 보낸다.
  static const apiKey = '/api-key';

  /// 언어 선택 화면(`LanguageSelectScreen`) 경로. API 키는 있지만
  /// 학습 언어가 설정되지 않았을 때 `redirect`가 이곳으로 보낸다.
  static const languageSelect = '/language-select';

  /// 레벨 테스트 화면(`LevelTestScreen`) 경로. 언어는 정해졌지만
  /// 난이도(`difficultyLevel`)가 없고, 이어받을 handoff 기록도 없을 때
  /// `redirect`가 이곳으로 보낸다.
  static const levelTest = '/level-test';

  /// 부트스트랩 전용 진입점 경로 — 오래 렌더링되는 일이 없다. redirect가
  /// 세션/이력 상태를 기반으로 항상 아래 route들 중 하나로 다시
  /// 결정해 보낸다(`_resolveLearningEntryRoute` 참고).
  static const learning = '/learning';

  /// 복습 화면(`ReviewScreen`) 경로.
  static const review = '/learning/review';

  /// 쉐도잉(받아쓰기) 화면(`ShadowingDictationScreen`) 경로.
  static const shadowingDictation = '/learning/shadowing/dictation';

  /// 쉐도잉(발음 연습) 화면(`ShadowingPronunciationScreen`) 경로.
  static const shadowingPronunciation = '/learning/shadowing/pronunciation';

  /// 작문 화면(`WritingScreen`) 경로.
  static const writing = '/learning/writing';

  /// 작문에 이어지는 듣기/발음 연습 화면(`WritingListeningScreen`) 경로.
  static const writingListening = '/learning/writing/listening';
}

/// 학습 루프에 속한 화면들(dictation -> pronunciation -> writing ->
/// listening -> dictation...)은 각 화면이 직접 `context.go(...)`를 호출해
/// 스텝 간 이동을 스스로 관리한다. `redirect`는 이 화면들에는 관여하지
/// 않아야 하며, 오직 `/learning`으로 진입할 때 루프의 어디로 들어갈지만
/// 결정한다. `routerProvider`의 `redirect` 로직에서 현재 위치가 이
/// 집합에 속하는지 확인해 리다이렉트를 건너뛰는 데 사용된다.
const _learningSubRoutes = {
  AppRoutes.review,
  AppRoutes.shadowingDictation,
  AppRoutes.shadowingPronunciation,
  AppRoutes.writing,
  AppRoutes.writingListening,
};

/// 온보딩 진행 상태를 판단하는 단일 진실 원천(single source of truth) provider.
/// 매 내비게이션마다 (순서대로) API 키 -> 언어 설정 -> 난이도 레벨을
/// 확인해서, 아직 충족되지 않은 첫 단계로 redirect한다. 각 화면은 각
/// 단계를 마친 뒤 `/`(정확히는 `AppRoutes.learning`)로 이동하기만 하고,
/// 다음에 어디로 갈지는 이 redirect 로직이 결정한다 — 다음 화면을
/// 화면 쪽에 하드코딩하지 않기 위함이다. `main.dart`의 `MyApp`에서
/// `ref.watch(routerProvider)`로 읽어 `MaterialApp.router`의
/// `routerConfig`에 연결한다.
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
        // 이 target language에 대한 레벨이 아직 없다 — 새로 레벨 테스트로
        // 넘어가기 전에, 예전에 이 언어를 공부하다 남긴 handoff 파일이
        // 있는지 먼저 확인한다.
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

      // 온보딩이 완전히 끝난 상태. 루프 내부 내비게이션은 각 화면 자신에게
      // 맡기고, `/learning`에 진입했을 때만 부트스트랩(진입 지점 결정)한다.
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

/// 새 학습 세션을 시작한다 — 지난번에 끝내지 못했던 exercise type을
/// 이어서 진행하며(기록이 없으면 shadowing부터), 그 진입 화면의 route를
/// 반환한다. 이 결정을 내리는 곳은 이 함수 하나뿐이며, `router`(더 이상
/// 복습할 것이 없을 때)와 `ReviewScreen`(복습을 끝내거나 건너뛸 때)이
/// 이 함수를 공유해서 호출한다 — 호출부마다 같은 로직을 재구현하지
/// 않기 위함이다.
///
/// [sessionStateService]로 새 세션 상태를 기록(`startNewSession`)하고,
/// [historyService]에서 마지막으로 완료한 exercise type을 읽어와 다음에
/// 무엇을 할지 정한다. 반환값은 `AppRoutes.shadowingDictation` 또는
/// `AppRoutes.writing` 중 하나다.
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

/// core-learning-loop 스펙 3번 항목: `/learning`으로 진입할 때 실제로
/// 어디에 착지할지 결정한다. `routerProvider`의 `redirect`에서, 온보딩이
/// 끝난 상태로 학습 서브 route가 아닌 곳(주로 `/learning` 자체)에
/// 도달했을 때 호출된다.
///
/// (A) 진행 중인 세션이 있는 경우: 세션 시작 시각이 지금과 같은 Pacific
///     달력 날짜라면(`DayBoundaryService` 참고) 저장돼 있던 exercise
///     type + sub-step의 화면으로 곧장 재개한다(예: 학습자가 있던 곳이
///     dictation이 아니라 shadowing pronunciation이었다면 그쪽으로 —
///     `LearningSubStep` 참고). 날짜가 다르면 "학습 종료"를 눌렀을 때와
///     동일하게 세션을 finalize한 뒤 (B)로 넘어간다.
/// (B) 진행 중인 세션이 없는 경우: 진행 중인 복습이 있으면(같은 Pacific
///     달력 날짜) 그 복습을 재개한다. 없으면 `ReviewSessionService`로
///     새 복습 세트를 직접 만든다 — 결과가 비어 있으면(복습할 것이
///     전혀 없는 경우, 이력이 아예 없는 신규 학습자 포함) (C)로,
///     아니면 그 세트를 저장하고 복습으로 이동한다.
/// (C) 새 학습 세션을 시작한다(`startNextLearningSession` 참고).
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

  // "복습할 것이 있는가"를 `historyService.hasAnyHistory()`(day-summary
  // 파일이 우연히 존재하는지 여부)가 아니라, 실제로 복습 가능한 데이터인
  // ReviewSessionService(내부적으로 ReviewHistoryService +
  // TtsCacheService에 기반)로 직접 판단한다 — 전자는 `finalizeSession`이
  // 비어 있지 않은 대화 이력으로 성공적으로 실행됐을 때만 기록되는
  // 부산물(side artifact)이라서, 실제로는 복습 가능한 데이터가 이미
  // 존재하는데도 값이 오래되거나 비어 있을 수 있다(실제 관측 사례:
  // history/ 는 비어 있지만 review_history/<language>/review_history.json
  // 에는 캐시된 오디오까지 포함된 실제 항목들이 가득 차 있었음) — 이 경우
  // 복습을 잘못 건너뛰게 된다. `buildReviewSet()`은 완전히 새로운
  // 학습자처럼 진짜 비어 있는 경우에도 이미 저비용으로(맵 하나를 한 번
  // 읽는 정도) 빈 리스트를 반환하므로, 이 경우를 위해 유의미하게 더
  // 비싼 검사를 추가하는 것도 아니다.
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
