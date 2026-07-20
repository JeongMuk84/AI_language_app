import 'exercise_type.dart';
import 'learning_sub_step.dart';

/// The in-progress learning session, persisted so it survives an app
/// restart (see `SessionStateService`). Cleared on "학습 종료", a detected
/// Pacific-day rollover, or a target-language switch (see
/// `SettingsViewModel.save`).
///
/// Does NOT include the running conversation history — that's kept
/// separately, per target language, by `ConversationHistoryService` (see
/// its doc comment for why) so it isn't wiped by the same "clear on
/// language switch" step this state's fields go through.
class SessionState {
  const SessionState({
    required this.currentExerciseType,
    required this.sessionStartedAt,
    this.currentSentence,
    this.currentTurnId,
    this.currentSubStep = LearningSubStep.first,
    this.currentUserAnswer,
  });

  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      currentExerciseType: ExerciseType.fromValue(json['currentExerciseType'] as String?),
      sessionStartedAt: DateTime.parse(json['sessionStartedAt'] as String),
      currentSentence: json['currentSentence'] as String?,
      currentTurnId: json['currentTurnId'] as String?,
      // Absent in session files written before this field existed —
      // defaults to `first`, same as a brand-new sentence would.
      currentSubStep: LearningSubStep.fromValue(json['currentSubStep'] as String?),
      currentUserAnswer: json['currentUserAnswer'] as String?,
    );
  }

  final ExerciseType currentExerciseType;
  final DateTime sessionStartedAt;
  final String? currentSentence;
  final String? currentTurnId;

  /// Which screen within the current `currentExerciseType` pair — e.g.
  /// dictation vs. pronunciation for shadowing. See `LearningSubStep`.
  final LearningSubStep currentSubStep;

  /// The learner's own final, fully-target-language submitted translation
  /// (i.e. the one that passed grading — see
  /// `WritingState.canProceedToListening`), set only when
  /// `currentExerciseType == writing` and `currentSubStep == second` (i.e.
  /// on WritingListeningScreen) — needed to resume that screen, since it
  /// plays back and grades pronunciation against this exact sentence. Not
  /// applicable to shadowing's pronunciation screen, which only needs
  /// [currentSentence].
  final String? currentUserAnswer;

  Map<String, dynamic> toJson() => {
        'currentExerciseType': currentExerciseType.value,
        'sessionStartedAt': sessionStartedAt.toIso8601String(),
        if (currentSentence != null) 'currentSentence': currentSentence,
        if (currentTurnId != null) 'currentTurnId': currentTurnId,
        'currentSubStep': currentSubStep.value,
        if (currentUserAnswer != null) 'currentUserAnswer': currentUserAnswer,
      };

  SessionState copyWith({
    ExerciseType? currentExerciseType,
    DateTime? sessionStartedAt,
    String? currentSentence,
    bool clearCurrentSentence = false,
    String? currentTurnId,
    bool clearCurrentTurnId = false,
    LearningSubStep? currentSubStep,
    String? currentUserAnswer,
    bool clearCurrentUserAnswer = false,
  }) {
    return SessionState(
      currentExerciseType: currentExerciseType ?? this.currentExerciseType,
      sessionStartedAt: sessionStartedAt ?? this.sessionStartedAt,
      currentSentence: clearCurrentSentence ? null : (currentSentence ?? this.currentSentence),
      currentTurnId: clearCurrentTurnId ? null : (currentTurnId ?? this.currentTurnId),
      currentSubStep: currentSubStep ?? this.currentSubStep,
      currentUserAnswer: clearCurrentUserAnswer
          ? null
          : (currentUserAnswer ?? this.currentUserAnswer),
    );
  }
}
