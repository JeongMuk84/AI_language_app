import 'conversation_turn.dart';
import 'exercise_type.dart';
import 'learning_sub_step.dart';

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
    this.currentSubStep = LearningSubStep.first,
    this.currentUserAnswer,
    this.currentCompletedSentence,
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
      // Absent in session files written before this field existed —
      // defaults to `first`, same as a brand-new sentence would.
      currentSubStep: LearningSubStep.fromValue(json['currentSubStep'] as String?),
      currentUserAnswer: json['currentUserAnswer'] as String?,
      currentCompletedSentence: json['currentCompletedSentence'] as String?,
    );
  }

  final List<ConversationTurn> conversationHistory;
  final ExerciseType currentExerciseType;
  final DateTime sessionStartedAt;
  final String? currentSentence;
  final String? currentTurnId;

  /// Which screen within the current `currentExerciseType` pair — e.g.
  /// dictation vs. pronunciation for shadowing. See `LearningSubStep`.
  final LearningSubStep currentSubStep;

  /// The learner's own submitted translation, set only when
  /// `currentExerciseType == writing` and `currentSubStep == second` (i.e.
  /// on WritingListeningScreen) — needed to resume that screen, since it
  /// plays back and grades pronunciation against this exact sentence, not
  /// the model answer. Not applicable to shadowing's pronunciation screen,
  /// which only needs `currentSentence`.
  final String? currentUserAnswer;

  /// The learner's own submitted translation with any native-language
  /// segments replaced by their target-language equivalent (see
  /// `TranslationResult.completedSentence`) — set alongside
  /// [currentUserAnswer] and needed to resume WritingListeningScreen, since
  /// that's the exact sentence it displays/plays/grades against.
  final String? currentCompletedSentence;

  Map<String, dynamic> toJson() => {
        'conversationHistory': conversationHistory.map((t) => t.toJson()).toList(),
        'currentExerciseType': currentExerciseType.value,
        'sessionStartedAt': sessionStartedAt.toIso8601String(),
        if (currentSentence != null) 'currentSentence': currentSentence,
        if (currentTurnId != null) 'currentTurnId': currentTurnId,
        'currentSubStep': currentSubStep.value,
        if (currentUserAnswer != null) 'currentUserAnswer': currentUserAnswer,
        if (currentCompletedSentence != null)
          'currentCompletedSentence': currentCompletedSentence,
      };

  SessionState copyWith({
    List<ConversationTurn>? conversationHistory,
    ExerciseType? currentExerciseType,
    DateTime? sessionStartedAt,
    String? currentSentence,
    bool clearCurrentSentence = false,
    String? currentTurnId,
    bool clearCurrentTurnId = false,
    LearningSubStep? currentSubStep,
    String? currentUserAnswer,
    bool clearCurrentUserAnswer = false,
    String? currentCompletedSentence,
    bool clearCurrentCompletedSentence = false,
  }) {
    return SessionState(
      conversationHistory: conversationHistory ?? this.conversationHistory,
      currentExerciseType: currentExerciseType ?? this.currentExerciseType,
      sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
      currentSentence: clearCurrentSentence ? null : (currentSentence ?? this.currentSentence),
      currentTurnId: clearCurrentTurnId ? null : (currentTurnId ?? this.currentTurnId),
      currentSubStep: currentSubStep ?? this.currentSubStep,
      currentUserAnswer: clearCurrentUserAnswer
          ? null
          : (currentUserAnswer ?? this.currentUserAnswer),
      currentCompletedSentence: clearCurrentCompletedSentence
          ? null
          : (currentCompletedSentence ?? this.currentCompletedSentence),
    );
  }
}
