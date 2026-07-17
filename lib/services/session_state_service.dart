import 'dart:convert';
import 'dart:io';

import '../models/conversation_turn.dart';
import '../models/exercise_type.dart';
import '../models/learning_sub_step.dart';
import '../models/review_progress.dart';
import '../models/session_state.dart';
import 'storage_location_service.dart';

/// Reads/writes the in-progress learning session to `session_state.json` in
/// the app's storage directory (see `StorageLocationService`), so it
/// survives an app restart. Cleared on "학습 종료" or a detected midnight
/// rollover (see `HistoryService.finalizeSession`).
class SessionStateService {
  SessionStateService({StorageLocationService? storageLocationService})
      : _storageLocationService = storageLocationService ?? StorageLocationService();

  final StorageLocationService _storageLocationService;

  Future<File> _stateFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/session_state.json');
  }

  Future<File> _dailyProgressFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/daily_progress.json');
  }

  Future<File> _reviewProgressFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/review_progress.json');
  }

  bool _isSameLocalDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Returns null when there's no active session.
  Future<SessionState?> readState() async {
    final file = await _stateFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return SessionState.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  Future<void> writeState(SessionState state) async {
    final file = await _stateFile();
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  /// Deletes the persisted session, if any. Used by "학습 종료", the
  /// midnight-rollover recovery path, and the `RESET_APP`/`RESET_SESSION`
  /// dev/test flags and Settings' "Reset All Data".
  Future<void> clearSession() async {
    final file = await _stateFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Starts a brand new session at [initialType], with no current sentence
  /// yet — the entry screen for that exercise type is responsible for
  /// requesting the first sentence.
  Future<SessionState> startNewSession({required ExerciseType initialType}) async {
    final state = SessionState(
      conversationHistory: const [],
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
      clearCurrentCompletedSentence: true,
    );
    await writeState(updated);
    return updated;
  }

  /// Marks the session as being on the *second* screen of the current
  /// pair (ShadowingPronunciationScreen / WritingListeningScreen) — called
  /// when the learner moves past dictation/writing, so a restart resumes
  /// into that screen instead of dictation/writing's blank first screen.
  /// [userAnswer] and [completedSentence], for the writing pair only, are
  /// the learner's just-graded translation and its target-language-only
  /// completed form — WritingListeningScreen needs both to resume (the
  /// latter is the exact sentence it displays/plays/grades against).
  Future<SessionState> advanceToSecondSubStep(
    SessionState current, {
    String? userAnswer,
    String? completedSentence,
  }) async {
    final updated = current.copyWith(
      currentSubStep: LearningSubStep.second,
      currentUserAnswer: userAnswer,
      currentCompletedSentence: completedSentence,
    );
    await writeState(updated);
    return updated;
  }

  /// Appends a completed turn to history and switches the active exercise
  /// type, clearing the current sentence so the next screen requests a
  /// fresh one. This is turn *completion* — always resets to the first
  /// sub-step of the new type, since the very next screen the learner
  /// lands on is always dictation/writing, never pronunciation/listening.
  /// Distinct from [advanceToSecondSubStep], which handles the
  /// in-progress (not-yet-completed) resume case within the same pair.
  Future<SessionState> completeTurnAndSwitchType(
    SessionState current, {
    required ConversationTurn turn,
    required ExerciseType nextType,
  }) async {
    final updated = current.copyWith(
      conversationHistory: [...current.conversationHistory, turn],
      currentExerciseType: nextType,
      clearCurrentSentence: true,
      clearCurrentTurnId: true,
      currentSubStep: LearningSubStep.first,
      clearCurrentUserAnswer: true,
      clearCurrentCompletedSentence: true,
    );
    await writeState(updated);
    return updated;
  }

  /// Turns (shadowing + writing) completed today (local calendar day),
  /// 0-[kDailyTurnLimit]. Resets automatically once the stored date no
  /// longer matches today — same "same local calendar day" comparison used
  /// for session rollover in `app_router.dart`. Persisted separately from
  /// `session_state.json` since it must survive "학습 종료"/session
  /// finalization (which clears that file) and keep counting across
  /// however many sessions happen today.
  Future<int> readDailyTurnCount() async {
    final file = await _dailyProgressFile();
    if (!await file.exists()) return 0;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return 0;
    final json = jsonDecode(content) as Map<String, dynamic>;
    final date = DateTime.parse(json['date'] as String);
    if (!_isSameLocalDay(date, DateTime.now())) return 0;
    return json['count'] as int? ?? 0;
  }

  /// Increments (rolling over to 1 first if the date has changed) and
  /// persists today's turn count. Returns the new count.
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
  Future<void> clearDailyProgress() async {
    final file = await _dailyProgressFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// The in-progress review session, if any — its mere presence *is*
  /// "isInReviewMode". Null if there's none, or if the stored one started
  /// on an earlier local calendar day (that one is discarded here so a
  /// stale review is never silently resumed into a new day; the caller is
  /// responsible for building a fresh set in that case).
  Future<ReviewProgress?> readReviewProgress() async {
    final file = await _reviewProgressFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    final progress = ReviewProgress.fromJson(jsonDecode(content) as Map<String, dynamic>);
    if (!_isSameLocalDay(progress.startedAt, DateTime.now())) {
      await clearReviewProgress();
      return null;
    }
    return progress;
  }

  Future<void> writeReviewProgress(ReviewProgress progress) async {
    final file = await _reviewProgressFile();
    await file.writeAsString(jsonEncode(progress.toJson()));
  }

  /// Deletes the in-progress review session. Called when review finishes,
  /// is skipped, or rolls over to a new day, and by the `RESET_APP`
  /// dev/test flag and Settings' "Reset All Data".
  Future<void> clearReviewProgress() async {
    final file = await _reviewProgressFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
