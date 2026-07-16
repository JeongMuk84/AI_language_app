import 'conversation_turn.dart';
import 'exercise_type.dart';

/// The in-progress learning session, persisted so it survives an app
/// restart (see `SessionStateService`). Cleared on "학습 종료" or when a
/// midnight rollover is detected on the next launch.
class SessionState {
  const SessionState({
    required this.conversationHistory,
    required this.currentExerciseType,
    required this.sessionStartedAt,
    this.currentSentence,
    this.currentTurnId,
  });

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      conversationHistory: (json['conversationHistory'] as List? ?? const [])
          .map((t) => ConversationTurn.fromJson(t as Map<String, dynamic>))
          .toList(),
      currentExerciseType: ExerciseType.fromValue(json['currentExerciseType'] as String?),
      sessionStartedAt: DateTime.parse(json['sessionStartedAt'] as String),
      currentSentence: json['currentSentence'] as String?,
      currentTurnId: json['currentTurnId'] as String?,
    );
  }

  final List<ConversationTurn> conversationHistory;
  final ExerciseType currentExerciseType;
  final DateTime sessionStartedAt;
  final String? currentSentence;
  final String? currentTurnId;

  Map<String, dynamic> toJson() => {
        'conversationHistory': conversationHistory.map((t) => t.toJson()).toList(),
        'currentExerciseType': currentExerciseType.value,
        'sessionStartedAt': sessionStartedAt.toIso8601String(),
        if (currentSentence != null) 'currentSentence': currentSentence,
        if (currentTurnId != null) 'currentTurnId': currentTurnId,
      };

  SessionState copyWith({
    List<ConversationTurn>? conversationHistory,
    ExerciseType? currentExerciseType,
    DateTime? sessionStartedAt,
    String? currentSentence,
    bool clearCurrentSentence = false,
    String? currentTurnId,
    bool clearCurrentTurnId = false,
  }) {
    return SessionState(
      conversationHistory: conversationHistory ?? this.conversationHistory,
      currentExerciseType: currentExerciseType ?? this.currentExerciseType,
      sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
      currentSentence: clearCurrentSentence ? null : (currentSentence ?? this.currentSentence),
      currentTurnId: clearCurrentTurnId ? null : (currentTurnId ?? this.currentTurnId),
    );
  }
}
