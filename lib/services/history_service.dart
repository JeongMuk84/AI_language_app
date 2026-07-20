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
class HistoryService {
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

  Future<Directory> _historyDir() async {
    final dir = await _storageLocationService.baseDirectory();
    final historyDir = Directory('${dir.path}/history');
    if (!await historyDir.exists()) {
      await historyDir.create(recursive: true);
    }
    return historyDir;
  }

  String _dateKey(DateTime date) {
    final pacificDate = _dayBoundaryService.pacificDateOf(date);
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pacificDate.year}-${pad2(pacificDate.month)}-${pad2(pacificDate.day)}';
  }

  Future<File> _fileForDate(DateTime date) async {
    final dir = await _historyDir();
    return File('${dir.path}/history_${_dateKey(date)}.json');
  }

  Future<List<File>> _allHistoryFiles() async {
    final dir = await _historyDir();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<bool> hasAnyHistory() async {
    final files = await _allHistoryFiles();
    return files.isNotEmpty;
  }

  /// Deletes every saved history file. Used by the `RESET_APP`/
  /// `RESET_HISTORY` dev/test flags and Settings' "Reset All Data".
  Future<void> clearHistory() async {
    final dir = await _historyDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// The `lastExerciseType` of the most recently saved history file, or
  /// null if there's no history yet.
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
    await _conversationHistoryService.clear();
  }

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
