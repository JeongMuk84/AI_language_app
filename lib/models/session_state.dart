import 'exercise_type.dart';
import 'learning_sub_step.dart';

/// 진행 중인 학습 세션 상태를 나타내는 모델. 앱이 재시작되어도 살아남도록
/// 저장된다(참고: `SessionStateService`). "학습 종료" 버튼을 눌렀을 때,
/// 태평양 시간(Pacific time) 기준 날짜가 바뀐 것이 감지되었을 때, 또는
/// target language를 전환했을 때(참고: `SettingsViewModel.save`) 지워진다.
///
/// 진행 중인 conversation history는 여기 포함되지 않는다 — 그것은
/// target language별로 `ConversationHistoryService`가 따로 관리한다(그
/// 이유는 해당 클래스의 doc comment 참고). 그래야 이 `SessionState`의
/// 필드들이 "언어 전환 시 초기화"되는 것과 같은 단계를 거쳐도 conversation
/// history까지 함께 지워지지 않는다.
class SessionState {
  /// [currentExerciseType]은 현재 진행 중인 shadowing/writing 여부,
  /// [sessionStartedAt]은 이 세션이 시작된 시각, [currentSentence]는 현재
  /// 다루고 있는 문장, [currentTurnId]는 현재 턴의 id,
  /// [currentSubStep]은 exercise 쌍 안에서의 세부 화면 위치,
  /// [currentUserAnswer]는 writing의 두 번째 화면을 재개하기 위해 필요한
  /// 학습자의 제출 번역이다.
  const SessionState({
    required this.currentExerciseType,
    required this.sessionStartedAt,
    this.currentSentence,
    this.currentTurnId,
    this.currentSubStep = LearningSubStep.first,
    this.currentUserAnswer,
  });

  /// 저장된 `session_state.json` 파일 내용을 파싱해 [SessionState]를 만든다.
  /// `SessionStateService.readState`가 앱 시작/화면 재진입 시 세션을 복원할
  /// 때 사용한다.
  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      currentExerciseType: ExerciseType.fromValue(json['currentExerciseType'] as String?),
      sessionStartedAt: DateTime.parse(json['sessionStartedAt'] as String),
      currentSentence: json['currentSentence'] as String?,
      currentTurnId: json['currentTurnId'] as String?,
      // 이 필드가 생기기 전에 저장된 세션 파일에는 값이 없다 — 그런 경우
      // 새 문장을 막 시작한 것과 동일하게 `first`를 기본값으로 사용한다.
      currentSubStep: LearningSubStep.fromValue(json['currentSubStep'] as String?),
      currentUserAnswer: json['currentUserAnswer'] as String?,
    );
  }

  /// 현재 진행 중인 exercise가 shadowing인지 writing인지.
  final ExerciseType currentExerciseType;

  /// 이 세션이 시작된 시각. Pacific time 기준 날짜 롤오버 판정에도 쓰인다.
  final DateTime sessionStartedAt;

  /// 현재 다루고 있는 문장(target language).
  final String? currentSentence;

  /// 현재 턴을 식별하는 id.
  final String? currentTurnId;

  /// 현재 `currentExerciseType` 쌍 안에서 어느 화면에 있는지 — 예: shadowing의
  /// 경우 dictation 화면인지 pronunciation 화면인지. 참고: `LearningSubStep`.
  final LearningSubStep currentSubStep;

  /// 학습자가 최종적으로 제출한, 전체가 target language로 작성된 번역
  /// (즉 채점을 통과한 것 — 참고: `WritingState.canProceedToListening`).
  /// `currentExerciseType == writing`이고 `currentSubStep == second`일
  /// 때(즉 WritingListeningScreen일 때)만 값이 설정된다 — 이 화면은 바로 이
  /// 문장을 재생하고 그 발음을 채점하므로, 화면을 재개하려면 이 값이
  /// 필요하다. shadowing의 pronunciation 화면에는 해당하지 않으며, 그
  /// 화면은 [currentSentence]만 있으면 충분하다.
  final String? currentUserAnswer;

  /// [SessionState]를 `session_state.json` 저장용 JSON 맵으로 직렬화한다.
  /// `SessionStateService.writeState`가 사용한다.
  Map<String, dynamic> toJson() => {
        'currentExerciseType': currentExerciseType.value,
        'sessionStartedAt': sessionStartedAt.toIso8601String(),
        if (currentSentence != null) 'currentSentence': currentSentence,
        if (currentTurnId != null) 'currentTurnId': currentTurnId,
        'currentSubStep': currentSubStep.value,
        if (currentUserAnswer != null) 'currentUserAnswer': currentUserAnswer,
      };

  /// 일부 필드만 바꾼 새 [SessionState]를 만드는 불변 갱신 메서드.
  /// `SessionStateService`의 `setCurrentSentence`/`advanceToSecondSubStep`/
  /// `completeTurnAndSwitchType` 등이 세션 진행 상태를 바꿀 때 사용한다.
  /// `clearCurrentSentence`/`clearCurrentTurnId`/`clearCurrentUserAnswer`
  /// 플래그는 각 필드를 명시적으로 null로 지우기 위한 것이다(단순히 null을
  /// 넘기면 "값 유지"로 해석되므로 별도 플래그가 필요하다).
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
