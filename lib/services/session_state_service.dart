import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/conversation_turn.dart';
import '../models/exercise_type.dart';
import '../models/session_state.dart';

/// Reads/writes the in-progress learning session to `session_state.json` in
/// the app documents directory, so it survives an app restart. Cleared on
/// "학습 종료" or a detected midnight rollover (see `HistoryService.finalizeSession`).
class SessionStateService {
  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/session_state.json');
  }

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
  /// into the exact same sentence" case.
  Future<SessionState> setCurrentSentence(
    SessionState current, {
    required String sentence,
    required String turnId,
  }) async {
    final updated = current.copyWith(currentSentence: sentence, currentTurnId: turnId);
    await writeState(updated);
    return updated;
  }

  /// Appends a completed turn to history and switches the active exercise
  /// type, clearing the current sentence so the next screen requests a
  /// fresh one.
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
    );
    await writeState(updated);
    return updated;
  }
}
