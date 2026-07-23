import 'dart:convert';
import 'dart:io';

import '../models/conversation_turn.dart';
import '../models/exercise_type.dart';
import '../models/history_summary.dart';
import 'conversation_history_service.dart';
import 'day_boundary_service.dart';
import 'session_state_service.dart';
import 'storage_location_service.dart';

/// Reads/writes per-day history files (`history/history_<yyyy-MM-dd>.json`,
/// dated by Pacific calendar day — see `DayBoundaryService`) summarizing
/// finalized learning sessions, under the app's storage directory (see
/// `StorageLocationService`).
/// (마무리된 학습 세션을 요약하는 날짜별 history 파일
/// (`history/history_<yyyy-MM-dd>.json`, `DayBoundaryService`가 정의하는
/// 태평양 달력 날짜로 이름 붙여짐)을 앱의 저장 디렉터리
/// (`StorageLocationService` 참고) 아래에 읽고 쓰는 서비스.)
///
/// `historyServiceProvider`(`service_providers.dart`)를 통해 노출되며,
/// `end_session_button.dart`의 "학습 종료" 버튼, `app_router.dart`의 자정
/// 롤오버 복구 경로, `ShadowingViewModel`/`WritingViewModel`의 세션 종료
/// 처리, `SettingsViewModel`의 "Reset All Data"에서 사용된다.
class HistoryService {
  /// 필요한 하위 서비스들을 주입받아 생성한다(테스트에서 모킹 가능하도록).
  /// 모두 생략하면 각각 기본 구현을 새로 만들어 사용한다.
  HistoryService({
    SessionStateService? sessionStateService,
    ConversationHistoryService? conversationHistoryService,
    StorageLocationService? storageLocationService,
    DayBoundaryService? dayBoundaryService,
  }) : _sessionStateService = sessionStateService ?? SessionStateService(),
       _conversationHistoryService = conversationHistoryService ?? ConversationHistoryService(),
       _storageLocationService = storageLocationService ?? StorageLocationService(),
       _dayBoundaryService = dayBoundaryService ?? DayBoundaryService();

  final SessionStateService _sessionStateService;
  final ConversationHistoryService _conversationHistoryService;
  final StorageLocationService _storageLocationService;
  final DayBoundaryService _dayBoundaryService;

  /// history 파일들이 저장되는 `history` 디렉터리 핸들을 반환하고, 없으면
  /// 새로 만든다. 이 클래스의 다른 메서드들이 내부적으로 사용하는 헬퍼다.
  /// 부작용: 디렉터리가 없으면 생성한다.
  Future<Directory> _historyDir() async {
    final dir = await _storageLocationService.baseDirectory();
    final historyDir = Directory('${dir.path}/history');
    if (!await historyDir.exists()) {
      await historyDir.create(recursive: true);
    }
    return historyDir;
  }

  /// [date]를 `DayBoundaryService`가 정의하는 태평양 달력 날짜로 변환해
  /// `yyyy-MM-dd` 형식의 파일명용 키 문자열을 만든다. [_fileForDate]와
  /// [_buildSummary]가 호출한다.
  /// [date]: 변환할 임의의 시각.
  /// 반환값: `"2026-07-21"` 형식의 날짜 키 문자열.
  String _dateKey(DateTime date) {
    final pacificDate = _dayBoundaryService.pacificDateOf(date);
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pacificDate.year}-${pad2(pacificDate.month)}-${pad2(pacificDate.day)}';
  }

  /// [date]가 속한 태평양 날짜의 history 파일 핸들을 반환한다.
  /// [finalizeSession]이 세션을 저장할 파일 경로를 얻기 위해 호출한다.
  Future<File> _fileForDate(DateTime date) async {
    final dir = await _historyDir();
    return File('${dir.path}/history_${_dateKey(date)}.json');
  }

  /// history 디렉터리 안의 모든 `.json` 파일을 경로순(=날짜순)으로 정렬해
  /// 반환한다. [hasAnyHistory]와 [getLastExerciseType]이 내부적으로
  /// 사용하는 헬퍼다.
  /// 반환값: 정렬된 history 파일 목록.
  Future<List<File>> _allHistoryFiles() async {
    final dir = await _historyDir();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 저장된 history 파일이 하나라도 있는지 확인한다.
  ///
  /// 현재 코드베이스에서 실제로 호출하는 곳은 없다 — `app_router.dart`는
  /// 이 값 대신 `ReviewSessionService.buildReviewSet()`으로 review 가능
  /// 데이터를 직접 확인한다. 그 이유는 이 메서드가 보는 day-summary 파일이
  /// `finalizeSession`이 비어있지 않은 대화 history로 성공적으로 실행됐을
  /// 때만 쓰이는 부산물이라, 실제로는 리뷰할 학습 데이터(review_history 등)가
  /// 있는데도 `history/`가 비어 있어 이 메서드가 거짓으로 "기록 없음"을
  /// 반환하는 사례가 실제로 관측되었기 때문이다(`app_router.dart`의 관련
  /// 주석 참고). 다만 향후 필요할 수 있어 남겨둔 유틸리티 메서드다.
  /// 반환값: history 파일이 하나 이상 있으면 `true`.
  Future<bool> hasAnyHistory() async {
    final files = await _allHistoryFiles();
    return files.isNotEmpty;
  }

  /// Deletes every saved history file. Used by the `RESET_APP`/
  /// `RESET_HISTORY` dev/test flags and Settings' "Reset All Data".
  /// (저장된 모든 history 파일을 삭제한다. `main.dart`의 `RESET_APP`/
  /// `RESET_HISTORY` 개발/테스트용 플래그와 Settings 화면의 "Reset All
  /// Data"(`SettingsViewModel`)에서 호출된다.)
  /// 부작용: `history` 디렉터리 전체를 재귀적으로 삭제한다.
  Future<void> clearHistory() async {
    final dir = await _historyDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// The `lastExerciseType` of the most recently saved history file, or
  /// null if there's no history yet.
  /// (가장 최근에 저장된 history 파일의 `lastExerciseType`을 반환하며,
  /// 아직 history가 없으면 null을 반환한다.)
  ///
  /// `app_router.dart`가 세션이 없거나 이미 다른 날짜로 넘어갔을 때, 어떤
  /// 연습 유형(shadowing/writing)으로 이어서 시작할지 결정하기 위해
  /// 호출한다.
  /// 반환값: 가장 최근 history 파일의 마지막 연습 유형, 없으면 `null`.
  Future<ExerciseType?> getLastExerciseType() async {
    final files = await _allHistoryFiles();
    if (files.isEmpty) return null;
    final content = await files.last.readAsString();
    if (content.trim().isEmpty) return null;
    final summary = HistorySummary.fromJson(jsonDecode(content) as Map<String, dynamic>);
    return summary.lastExerciseType;
  }

  /// Deduplicates the current session's turns (keeping, per `turnId`, only
  /// the one with the latest `timestamp` — covers sentences retried via
  /// "다시 시도"), saves the result under the day the session *started*, and
  /// clears the session. Used by both the "학습 종료" button and the
  /// midnight-rollover recovery path.
  /// (현재 세션의 turn들을 중복 제거하고(`turnId`별로 가장 최근
  /// `timestamp`를 가진 것만 남긴다 - "다시 시도"로 재시도된 문장을
  /// 처리하기 위함), 그 결과를 세션이 *시작된* 날짜 밑에 저장한 뒤 세션을
  /// 지운다. "학습 종료" 버튼과 자정 롤오버 복구 경로 양쪽에서 사용된다.)
  ///
  /// `end_session_button.dart`(사용자가 "학습 종료"를 누를 때),
  /// `app_router.dart`(자정이 지나 이전 날짜의 세션을 발견했을 때),
  /// `ShadowingViewModel`/`WritingViewModel`(세션 완료 처리 시)이 호출한다.
  /// 부작용: `SessionStateService`에서 세션 상태를 읽고, 비어있지 않으면
  /// 날짜별 history 파일을 새로 쓰며, 세션 상태와 현재 언어의 대화
  /// history(`ConversationHistoryService`)를 지운다.
  Future<void> finalizeSession() async {
    final session = await _sessionStateService.readState();
    if (session == null) return;

    final conversationHistory = await _conversationHistoryService.readAll();
    final deduped = _dedupeByLatestTurnId(conversationHistory);

    if (deduped.isNotEmpty) {
      final summary = _buildSummary(sessionDate: session.sessionStartedAt, turns: deduped);
      final file = await _fileForDate(session.sessionStartedAt);
      await file.writeAsString(jsonEncode(summary.toJson()));
    }

    await _sessionStateService.clearSession();
    // Finalizing (day rollover / "학습 종료") ends this language's running
    // context, same as the old single-file behavior — NOT the same as a
    // target-language switch, which leaves this alone so switching back
    // later the same day resumes it (see `ConversationHistoryService`).
    // (세션을 마무리하는 것(자정 롤오버 / "학습 종료")은 이 언어의 현재
    // 진행 중이던 맥락을 끝낸다는 뜻이며, 예전의 단일 파일 방식과
    // 동일하다 — 이는 대상 언어 전환과는 다르다. 언어 전환은 이 데이터를
    // 그대로 남겨두어, 같은 날 다시 그 언어로 돌아오면 이어서 재개할 수
    // 있게 한다(`ConversationHistoryService` 참고).)
    await _conversationHistoryService.clear();
  }

  /// [turns] 목록을 `turnId` 기준으로 중복 제거한다 — 같은 `turnId`를 가진
  /// 여러 항목 중 `timestamp`가 가장 늦은(최신) 것만 남기고, 결과를
  /// `timestamp` 순으로 정렬해 반환한다. 사용자가 "다시 시도"로 같은
  /// turn을 여러 번 시도한 기록이 중복 저장되는 것을 막기 위해
  /// [finalizeSession]이 호출한다.
  /// [turns]: 원본 대화 turn 목록(중복 포함 가능).
  /// 반환값: `turnId`당 최신 항목만 남기고 시간순 정렬한 목록.
  List<ConversationTurn> _dedupeByLatestTurnId(List<ConversationTurn> turns) {
    final latestByTurnId = <String, ConversationTurn>{};
    for (final turn in turns) {
      final existing = latestByTurnId[turn.turnId];
      if (existing == null || turn.timestamp.isAfter(existing.timestamp)) {
        latestByTurnId[turn.turnId] = turn;
      }
    }
    final result = latestByTurnId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// [turns]로부터 저장용 [HistorySummary]를 만든다 — 발음 점수가 있는
  /// turn들의 평균 정확도, 연습한 문장 수, 마지막 연습 유형 등을
  /// 계산한다. [finalizeSession]이 파일에 쓸 요약 객체를 만들기 위해
  /// 호출한다.
  /// [sessionDate]: 세션이 시작된 시각(날짜 키 계산에 사용).
  /// [turns]: 중복 제거된 대화 turn 목록.
  /// 반환값: 파일에 직렬화되어 저장될 [HistorySummary].
  HistorySummary _buildSummary({
    required DateTime sessionDate,
    required List<ConversationTurn> turns,
  }) {
    final scored = turns.where((t) => t.pronunciationScore != null).toList();
    final averageScore = scored.isEmpty
        ? null
        : scored.map((t) => t.pronunciationScore!).reduce((a, b) => a + b) / scored.length;

    return HistorySummary(
      date: _dateKey(sessionDate),
      practicedSentenceCount: turns.length,
      sentences: turns.map(HistorySentenceEntry.fromTurn).toList(),
      lastExerciseType: turns.last.type,
      pronunciationAccuracy: averageScore,
    );
  }
}
