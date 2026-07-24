import 'dart:convert';
import 'dart:io';

import '../models/exercise_type.dart';
import '../models/learning_sub_step.dart';
import '../models/review_progress.dart';
import '../models/session_state.dart';
import 'day_boundary_service.dart';
import 'storage_location_service.dart';

/// Reads/writes the in-progress learning session to `session_state.json` in
/// the app's storage directory (see `StorageLocationService`), so it
/// survives an app restart. Cleared on "학습 종료" or a detected Pacific-day
/// rollover (see `HistoryService.finalizeSession`, `DayBoundaryService`).
/// (진행 중인 학습 세션을 앱의 저장 디렉터리(`StorageLocationService` 참고)
/// 안의 `session_state.json`에 읽고 써서, 앱을 재시작해도 살아남게 한다.
/// "학습 종료"를 누르거나 태평양 날짜가 바뀐 것이 감지되면 지워진다
/// (`HistoryService.finalizeSession`, `DayBoundaryService` 참고).)
///
/// 이 클래스는 언어와 무관하게 "지금 당장 무엇을 하고 있는가"(현재 문장/
/// turn/하위 단계, 오늘의 turn 카운트, 진행 중인 review)라는 단일 상태를
/// 소유한다 — 언어별로 분리되어 살아남는 대화 맥락은
/// `ConversationHistoryService`가 별도로 관리한다.
/// `sessionStateServiceProvider`(`service_providers.dart`)를 통해
/// 노출되며, `app_router.dart`의 세션 재개/복습 라우팅 판단,
/// `ShadowingViewModel`/`WritingViewModel`의 세션 진행,
/// `SettingsViewModel`의 세션 종료/리셋, `ReviewViewModel`의 복습 진행
/// 등 학습 흐름 전반에서 사용된다.
class SessionStateService {
  /// 필요한 하위 서비스들을 주입받아 생성한다(테스트에서 모킹 가능하도록).
  /// 모두 생략하면 각각 기본 구현을 새로 만들어 사용한다.
  SessionStateService({
    StorageLocationService? storageLocationService,
    DayBoundaryService? dayBoundaryService,
  }) : _storageLocationService = storageLocationService ?? StorageLocationService(),
       _dayBoundaryService = dayBoundaryService ?? DayBoundaryService();

  final StorageLocationService _storageLocationService;
  final DayBoundaryService _dayBoundaryService;

  /// 진행 중인 세션 상태가 저장되는 `session_state.json` 파일 핸들을
  /// 반환한다. [readState], [writeState], [clearSession]이 내부적으로
  /// 사용하는 헬퍼다.
  Future<File> _stateFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/session_state.json');
  }

  /// 오늘의 turn 카운터가 저장되는 `daily_progress.json` 파일 핸들을
  /// 반환한다. [readDailyTurnCount], [incrementDailyTurnCount],
  /// [clearDailyProgress]가 내부적으로 사용하는 헬퍼다.
  Future<File> _dailyProgressFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/daily_progress.json');
  }

  /// 진행 중인 복습 세션이 저장되는 `review_progress.json` 파일 핸들을
  /// 반환한다. [readReviewProgress], [writeReviewProgress],
  /// [clearReviewProgress]가 내부적으로 사용하는 헬퍼다.
  Future<File> _reviewProgressFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/review_progress.json');
  }

  /// "오늘 이미 복습을 마쳤는지" 여부가 저장되는
  /// `review_completed_today.json` 파일 핸들을 반환한다. [hasReviewedToday],
  /// [markReviewedToday], [clearReviewedTodayFlag]가 내부적으로 사용하는
  /// 헬퍼다.
  Future<File> _reviewedTodayFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/review_completed_today.json');
  }

  /// Returns null when there's no active session.
  /// (활성 세션이 없으면 null을 반환한다.)
  ///
  /// `app_router.dart`가 앱 시작/화면 이동 시 재개할 세션이 있는지 확인할
  /// 때, `ShadowingViewModel`/`WritingViewModel`이 화면 로드 시 기존
  /// 세션을 이어서 쓸지 판단할 때, `HistoryService.finalizeSession`이
  /// 마무리할 세션이 있는지 확인할 때 호출한다.
  /// 반환값: 저장된 [SessionState], 없으면 `null`.
  Future<SessionState?> readState() async {
    final file = await _stateFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return SessionState.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  /// [state]를 그대로 session_state.json에 직렬화해 저장한다. 이 클래스의
  /// 다른 상태 변경 메서드([setCurrentSentence] 등)들이 내부적으로 호출하는
  /// 저수준 저장 헬퍼다.
  /// [state]: 저장할 전체 세션 상태.
  /// 부작용: session_state.json 파일을 덮어쓴다.
  Future<void> writeState(SessionState state) async {
    final file = await _stateFile();
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  /// Deletes the persisted session, if any. Used by "학습 종료", the
  /// midnight-rollover recovery path, and the `RESET_APP`/`RESET_SESSION`
  /// dev/test flags and Settings' "Reset All Data".
  /// (저장되어 있는 세션이 있으면 삭제한다. "학습 종료", 자정 롤오버 복구
  /// 경로, `main.dart`의 `RESET_APP`/`RESET_SESSION` 개발/테스트용
  /// 플래그, Settings 화면의 "Reset All Data"에서 사용된다.)
  /// 부작용: session_state.json 파일이 있으면 삭제한다.
  Future<void> clearSession() async {
    final file = await _stateFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Starts a brand new session at [initialType], with no current sentence
  /// yet — the entry screen for that exercise type is responsible for
  /// requesting the first sentence.
  /// ([initialType]으로 새 세션을 시작한다. 아직 현재 문장은 없는 상태이며
  /// — 해당 연습 유형의 진입 화면이 첫 문장을 요청할 책임을 진다.)
  ///
  /// `app_router.dart`, `ShadowingViewModel`, `WritingViewModel`이
  /// [readState]가 `null`을 반환했을 때(활성 세션이 없을 때) 새 세션을
  /// 시작하기 위해 호출한다.
  /// [initialType]: 새 세션이 시작할 연습 유형(shadowing 또는 writing).
  /// 반환값: 새로 만들어진 [SessionState].
  /// 부작용: session_state.json에 새 세션 상태를 저장한다.
  Future<SessionState> startNewSession({required ExerciseType initialType}) async {
    final state = SessionState(
      currentExerciseType: initialType,
      sessionStartedAt: DateTime.now(),
    );
    await writeState(state);
    return state;
  }

  /// Records the sentence/turn currently being worked on, for the "resume
  /// into the exact same sentence" case. A freshly-requested sentence is
  /// always the *first* screen of its pair (dictation/writing) — resuming
  /// mid-pronunciation or mid-listening never re-requests a sentence, it
  /// resumes via [currentSubStep] instead (see `advanceToSecondSubStep`).
  /// (지금 진행 중인 문장/turn을 기록한다 — "정확히 같은 문장으로
  /// 재개하기" 케이스를 위함이다. 새로 요청된 문장은 항상 그 쌍의 *첫
  /// 번째* 화면(dictation/writing)에 해당한다 — 발음/듣기 도중 재개하는
  /// 경우는 절대 문장을 새로 요청하지 않고, 대신 [currentSubStep]을 통해
  /// 재개한다([advanceToSecondSubStep] 참고).)
  ///
  /// `ShadowingViewModel`과 `WritingViewModel`이 Gemini로부터 새 문장을
  /// 받아온 직후, 그 문장을 현재 세션의 문장으로 기록하기 위해 호출한다.
  /// [current]: 갱신할 기존 세션 상태.
  /// [sentence]: 새로 받아온 문장.
  /// [turnId]: 이 turn을 식별하는 ID.
  /// 반환값: 갱신되어 저장된 [SessionState].
  /// 부작용: session_state.json을 갱신한다.
  Future<SessionState> setCurrentSentence(
    SessionState current, {
    required String sentence,
    required String turnId,
  }) async {
    final updated = current.copyWith(
      currentSentence: sentence,
      currentTurnId: turnId,
      currentSubStep: LearningSubStep.first,
      clearCurrentUserAnswer: true,
    );
    await writeState(updated);
    return updated;
  }

  /// Marks the session as being on the *second* screen of the current
  /// pair (ShadowingPronunciationScreen / WritingListeningScreen) — called
  /// when the learner moves past dictation/writing, so a restart resumes
  /// into that screen instead of dictation/writing's blank first screen.
  /// [userAnswer], for the writing pair only, is the learner's own final
  /// fully-target-language submitted translation — WritingListeningScreen
  /// needs it to resume (it's the exact sentence displayed/played/graded).
  /// (세션이 현재 쌍의 *두 번째* 화면(ShadowingPronunciationScreen /
  /// WritingListeningScreen)에 있는 상태임을 표시한다 — 학습자가
  /// dictation/writing을 지나갈 때 호출되어, 재시작 시 dictation/writing의
  /// 빈 첫 화면이 아니라 이 화면으로 재개되게 한다. [userAnswer]는
  /// writing 쌍에서만 쓰이며, 학습자가 최종 제출한 완전히 대상 언어로 된
  /// 번역이다 — WritingListeningScreen이 재개할 때 필요하다(화면에
  /// 표시/재생/채점되는 바로 그 문장이기 때문).)
  ///
  /// `shadowing_dictation_screen.dart`와 `writing_screen.dart`가 각각
  /// dictation/writing 채점을 마치고 다음(발음/듣기) 화면으로 넘어갈 때
  /// 호출한다.
  /// [current]: 갱신할 기존 세션 상태.
  /// [userAnswer]: (writing 쌍에서만) 학습자가 제출한 최종 번역.
  /// 반환값: 갱신되어 저장된 [SessionState].
  /// 부작용: session_state.json을 갱신한다.
  Future<SessionState> advanceToSecondSubStep(
    SessionState current, {
    String? userAnswer,
  }) async {
    final updated = current.copyWith(
      currentSubStep: LearningSubStep.second,
      currentUserAnswer: userAnswer,
    );
    await writeState(updated);
    return updated;
  }

  /// Switches the active exercise type, clearing the current sentence so
  /// the next screen requests a fresh one. This is turn *completion* —
  /// always resets to the first sub-step of the new type, since the very
  /// next screen the learner lands on is always dictation/writing, never
  /// pronunciation/listening. Distinct from [advanceToSecondSubStep], which
  /// handles the in-progress (not-yet-completed) resume case within the
  /// same pair.
  ///
  /// Does NOT record the completed turn into conversation history itself —
  /// callers append it via `ConversationHistoryService` (kept per target
  /// language; see its doc comment) separately.
  /// (활성 연습 유형을 전환하면서 현재 문장을 지워 다음 화면이 새 문장을
  /// 요청하게 한다. 이것은 turn의 *완료*를 뜻한다 — 학습자가 다음에
  /// 도착하는 화면은 항상 dictation/writing이지 발음/듣기가 아니므로,
  /// 항상 새 유형의 첫 번째 하위 단계로 리셋한다. 같은 쌍 안에서 아직
  /// 완료되지 않은 진행 중 재개를 처리하는 [advanceToSecondSubStep]과는
  /// 다르다.
  ///
  /// 완료된 turn을 대화 history에 직접 기록하지는 않는다 — 호출자가
  /// 별도로 `ConversationHistoryService`(대상 언어별로 유지됨; 해당
  /// 클래스의 문서 참고)를 통해 추가해야 한다.)
  ///
  /// `ShadowingViewModel`이 발음 채점까지 마쳤을 때
  /// `nextType: ExerciseType.writing`으로, `WritingViewModel`이 듣기/발음
  /// 채점까지 마쳤을 때 `nextType: ExerciseType.shadowing`으로 호출해 다음
  /// turn으로 넘어간다.
  /// [current]: 갱신할 기존 세션 상태.
  /// [nextType]: 다음에 시작할 연습 유형.
  /// 반환값: 갱신되어 저장된 [SessionState].
  /// 부작용: session_state.json을 갱신한다.
  Future<SessionState> completeTurnAndSwitchType(
    SessionState current, {
    required ExerciseType nextType,
  }) async {
    final updated = current.copyWith(
      currentExerciseType: nextType,
      clearCurrentSentence: true,
      clearCurrentTurnId: true,
      currentSubStep: LearningSubStep.first,
      clearCurrentUserAnswer: true,
    );
    await writeState(updated);
    return updated;
  }

  /// Turns (shadowing + writing) completed today (Pacific calendar day —
  /// see `DayBoundaryService`, which matches when Gemini's free-tier daily
  /// quota actually resets), 0-[kDailyTurnLimit]. Resets automatically once
  /// the stored date no longer matches today — same comparison used for
  /// session rollover in `app_router.dart`. Persisted separately from
  /// `session_state.json` since it must survive "학습 종료"/session
  /// finalization (which clears that file) and keep counting across
  /// however many sessions happen today.
  /// (오늘(태평양 달력 날짜 - `DayBoundaryService` 참고, Gemini 무료
  /// 등급의 일일 quota가 실제로 리셋되는 시점과 일치) 완료된 turn
  /// (shadowing + writing) 수, 0~`kDailyTurnLimit` 범위. 저장된 날짜가
  /// 더 이상 오늘과 일치하지 않으면 자동으로 0으로 리셋된다 —
  /// `app_router.dart`의 세션 롤오버 판단과 동일한 비교 방식을 쓴다.
  /// `session_state.json`과는 별도로 저장되는데, "학습 종료"/세션
  /// 마무리(그 파일을 지우는 동작)와 무관하게 살아남아야 하고, 오늘 몇
  /// 번의 세션이 있었든 계속 누적해서 세야 하기 때문이다.)
  ///
  /// `service_providers.dart`의 provider가 남은 일일 turn 수를 계산할
  /// 때, `ShadowingViewModel`/`WritingViewModel`이 turn 완료 시
  /// [incrementDailyTurnCount] 이전에 현재 카운트를 조회할 때 호출한다.
  /// 반환값: 오늘 완료된 turn 수(날짜가 바뀌었으면 0).
  Future<int> readDailyTurnCount() async {
    final file = await _dailyProgressFile();
    if (!await file.exists()) return 0;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return 0;
    final json = jsonDecode(content) as Map<String, dynamic>;
    final date = DateTime.parse(json['date'] as String);
    if (!_dayBoundaryService.isSamePacificDay(date, DateTime.now())) return 0;
    return json['count'] as int? ?? 0;
  }

  /// Increments (rolling over to 1 first if the date has changed) and
  /// persists today's turn count. Returns the new count.
  /// (오늘의 turn 카운트를 증가시키고(날짜가 바뀌었으면 먼저 1로
  /// 리셋한 뒤 증가) 저장한다. 새 카운트를 반환한다.)
  ///
  /// `ShadowingViewModel`과 `WritingViewModel`이 한 turn(shadowing 또는
  /// writing)을 완료했을 때 호출해 일일 turn 제한 카운트를 갱신한다.
  /// 반환값: 갱신된 오늘의 turn 수.
  /// 부작용: daily_progress.json을 갱신한다.
  Future<int> incrementDailyTurnCount() async {
    final newCount = await readDailyTurnCount() + 1;
    final file = await _dailyProgressFile();
    await file.writeAsString(
      jsonEncode({'date': DateTime.now().toIso8601String(), 'count': newCount}),
    );
    return newCount;
  }

  /// Deletes the daily turn counter. Used by the `RESET_APP` dev/test flag
  /// and Settings' "Reset All Data".
  /// (일일 turn 카운터를 삭제한다. `main.dart`의 `RESET_APP` 개발/테스트용
  /// 플래그와 Settings 화면의 "Reset All Data"(`SettingsViewModel`)에서
  /// 사용된다.)
  /// 부작용: daily_progress.json 파일이 있으면 삭제한다.
  Future<void> clearDailyProgress() async {
    final file = await _dailyProgressFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// The in-progress review session, if any — its mere presence *is*
  /// "isInReviewMode". Null if there's none, or if the stored one started
  /// on an earlier Pacific calendar day (that one is discarded here so a
  /// stale review is never silently resumed into a new day; the caller is
  /// responsible for building a fresh set in that case).
  /// (진행 중인 복습 세션이 있다면 반환한다 — 이 값이 존재한다는 사실
  /// 자체가 곧 "isInReviewMode"다. 없거나, 저장된 것이 이전 태평양 날짜에
  /// 시작된 것이면 null을 반환한다(그 경우 여기서 폐기하여, 낡은 복습이
  /// 새 날짜로 조용히 이어지는 일이 없도록 한다; 이 경우 새 세트를 만드는
  /// 것은 호출자의 책임이다).)
  ///
  /// `app_router.dart`가 복습 화면으로 라우팅할지 판단할 때,
  /// `ReviewViewModel`이 복습 화면 진입/재개 시 기존 진행 상황을 이어받을
  /// 수 있는지 확인할 때 호출한다.
  /// 반환값: 오늘 시작된 진행 중인 [ReviewProgress], 없거나 낡았으면 `null`.
  /// 부작용: 저장된 진행 상황이 낡았으면(다른 날짜) [clearReviewProgress]를
  /// 호출해 지운다.
  Future<ReviewProgress?> readReviewProgress() async {
    final file = await _reviewProgressFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final progress = ReviewProgress.fromJson(jsonDecode(content) as Map<String, dynamic>);
    if (!_dayBoundaryService.isSamePacificDay(progress.startedAt, DateTime.now())) {
      await clearReviewProgress();
      return null;
    }
    return progress;
  }

  /// [progress]를 review_progress.json에 직렬화해 저장한다.
  /// `ReviewViewModel`이 복습 세트를 새로 시작하거나 한 문항을 진행할
  /// 때마다 진행 상황을 저장하기 위해, `app_router.dart`가 새 복습
  /// 세션을 시작할 때 호출한다.
  /// [progress]: 저장할 진행 중인 복습 상태.
  /// 부작용: review_progress.json 파일을 덮어쓴다.
  Future<void> writeReviewProgress(ReviewProgress progress) async {
    final file = await _reviewProgressFile();
    await file.writeAsString(jsonEncode(progress.toJson()));
  }

  /// Deletes the in-progress review session. Called when review finishes,
  /// is skipped, or rolls over to a new day, and by the `RESET_APP`
  /// dev/test flag and Settings' "Reset All Data".
  /// (진행 중인 복습 세션을 삭제한다. 복습이 끝나거나, 건너뛰거나, 새
  /// 날짜로 넘어갈 때, 그리고 `main.dart`의 `RESET_APP` 개발/테스트용
  /// 플래그와 Settings 화면의 "Reset All Data"(`SettingsViewModel`)에서
  /// 호출된다.)
  /// 부작용: review_progress.json 파일이 있으면 삭제한다.
  Future<void> clearReviewProgress() async {
    final file = await _reviewProgressFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 오늘(태평양 달력 날짜 — `DayBoundaryService` 참고) 이미 복습을 마쳤거나
  /// 건너뛴 적이 있는지 반환한다. 저장된 날짜가 오늘이 아니면(날짜가
  /// 바뀌었으면) 자동으로 `false`를 반환한다 — `readDailyTurnCount`와 동일한
  /// 방식이다.
  ///
  /// `app_router.dart`의 `_resolveLearningEntryRoute`가 "새로 복습 세트를
  /// 만들어 복습 화면으로 보낼지" 판단하기 직전에 호출한다. 이 값이
  /// `true`이면, `ReviewSessionService.buildReviewSet()`이 여전히 항목을
  /// 반환하더라도(예: 오늘 새로 학습을 시작해 방금 완료한 문장이 TTS까지
  /// 캐시되어 복습 가능 상태가 된 경우) 복습으로 보내지 않고 곧바로 다음
  /// 학습으로 넘어가야 한다 — `buildReviewSet()` 자체는 "오늘 이미 복습을
  /// 했는지"를 모르고 단순히 "복습 가능한 문장이 있는지"만 보기 때문이다.
  /// 반환값: 오늘 이미 복습을 마쳤으면(또는 건너뛰었으면) `true`.
  Future<bool> hasReviewedToday() async {
    final file = await _reviewedTodayFile();
    if (!await file.exists()) return false;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return false;
    final json = jsonDecode(content) as Map<String, dynamic>;
    final date = DateTime.parse(json['date'] as String);
    return _dayBoundaryService.isSamePacificDay(date, DateTime.now());
  }

  /// 오늘 복습을 마쳤다고(또는 건너뛰었다고) 표시한다.
  ///
  /// `ReviewViewModel`의 `advance()`(마지막 문항을 넘어갈 때)와 `skip()`이
  /// 복습을 끝내고 다음 학습 세션으로 넘어가기 직전에 호출한다.
  /// 부작용: review_completed_today.json에 오늘 날짜를 기록한다.
  Future<void> markReviewedToday() async {
    final file = await _reviewedTodayFile();
    await file.writeAsString(jsonEncode({'date': DateTime.now().toIso8601String()}));
  }

  /// Deletes the "reviewed today" flag. Used by the `RESET_APP` dev/test
  /// flag and Settings' "Reset All Data" — a stale flag left behind by
  /// either would otherwise make `_resolveLearningEntryRoute` keep skipping
  /// review even after every other piece of state has been wiped.
  /// ("오늘 복습을 마쳤음" 플래그를 삭제한다. `main.dart`의 `RESET_APP`
  /// 개발/테스트용 플래그와 Settings 화면의 "Reset All Data"
  /// (`SettingsViewModel`)에서 사용된다 — 이 플래그가 낡은 채로 남아있으면,
  /// 다른 모든 상태를 지웠는데도 `_resolveLearningEntryRoute`가 계속 복습을
  /// 건너뛰게 된다.)
  /// 부작용: review_completed_today.json 파일이 있으면 삭제한다.
  Future<void> clearReviewedTodayFlag() async {
    final file = await _reviewedTodayFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
