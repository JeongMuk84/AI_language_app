import 'exercise_type.dart';

/// 진행 중인 세션의 conversation history에 쌓이는, 완료된 문장 한 턴(shadowing
/// 또는 writing exercise 한 개)을 나타내는 모델. `ShadowingViewModel`과
/// `WritingViewModel`이 각각 턴을 완료할 때 이 객체를 생성하고,
/// `ConversationHistoryService.append`가 이를 언어별 conversation history
/// 파일에 저장한다. `GeminiService.generateNextSentence` 등은 이 히스토리
/// 목록을 받아 다음 문장을 생성할 때 문맥으로 활용한다.
class ConversationTurn {
  /// [turnId]는 이 턴을 식별하는 고유 id, [type]은 shadowing/writing 중
  /// 어느 exercise였는지, [timestamp]는 턴이 기록된 시각이다.
  /// [sentenceInTarget]/[sentenceInNative]는 해당 턴에서 다룬 문장의
  /// 대상 언어/모국어 버전, [userAnswer]는 학습자가 실제로 제출한 답,
  /// [isCorrect]는 채점 결과, [pronunciationScore]는 발음 점수(0-100)다.
  const ConversationTurn({
    required this.turnId,
    required this.type,
    required this.timestamp,
    this.sentenceInTarget,
    this.sentenceInNative,
    this.userAnswer,
    this.isCorrect,
    this.pronunciationScore,
  });

  /// conversation history JSON 파일에 저장된 항목 하나를 파싱해
  /// [ConversationTurn]을 만든다. `ConversationHistoryService`가 히스토리
  /// 파일을 읽을 때 사용한다.
  factory ConversationTurn.fromJson(Map<String, dynamic> json) {
    return ConversationTurn(
      turnId: json['turnId'] as String,
      type: ExerciseType.fromValue(json['type'] as String?),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sentenceInTarget: json['sentenceInTarget'] as String?,
      sentenceInNative: json['sentenceInNative'] as String?,
      userAnswer: json['userAnswer'] as String?,
      isCorrect: json['isCorrect'] as bool?,
      pronunciationScore: (json['pronunciationScore'] as num?)?.toDouble(),
    );
  }

  /// 이 턴을 식별하는 고유 id.
  final String turnId;

  /// shadowing/writing 중 어느 exercise였는지.
  final ExerciseType type;

  /// 이 턴이 기록된 시각.
  final DateTime timestamp;

  /// writing 턴의 경우, 학습자가 최종적으로 제출한 번역 결과다(참고:
  /// `WritingState.lastUserTranslation`). 턴이 "완료"로 기록되는 시점에는
  /// 이미 전체가 target language로만 작성되었음이 보장된다 — 즉 학습자가
  /// 직접 쓰지 않은, 모델이 생성한 예시 문장이 여기 들어오는 일은 없다.
  final String? sentenceInTarget;

  /// 해당 턴에서 다룬 문장의 native language 버전.
  final String? sentenceInNative;

  /// 학습자가 실제로 입력/제출한 답.
  final String? userAnswer;

  /// 채점 결과가 정답이었는지 여부.
  final bool? isCorrect;

  /// 발음 정확도 점수. 0-100 범위.
  final double? pronunciationScore;

  /// 이 턴을 conversation history JSON 파일에 저장할 형태로 직렬화한다.
  /// `ConversationHistoryService.append`/`_writeAll`이 파일을 쓸 때 사용한다.
  Map<String, dynamic> toJson() => {
        'turnId': turnId,
        'type': type.value,
        'timestamp': timestamp.toIso8601String(),
        if (sentenceInTarget != null) 'sentenceInTarget': sentenceInTarget,
        if (sentenceInNative != null) 'sentenceInNative': sentenceInNative,
        if (userAnswer != null) 'userAnswer': userAnswer,
        if (isCorrect != null) 'isCorrect': isCorrect,
        if (pronunciationScore != null) 'pronunciationScore': pronunciationScore,
      };

  /// 일부 필드만 바꾼 새 [ConversationTurn]을 만드는 불변 갱신 메서드.
  /// 채점/발음 분석 결과가 나온 뒤 [userAnswer]/[isCorrect]/
  /// [pronunciationScore]를 채워 넣는 등의 상황에서 사용한다.
  ConversationTurn copyWith({
    String? userAnswer,
    bool? isCorrect,
    double? pronunciationScore,
    DateTime? timestamp,
  }) {
    return ConversationTurn(
      turnId: turnId,
      type: type,
      timestamp: timestamp ?? this.timestamp,
      sentenceInTarget: sentenceInTarget,
      sentenceInNative: sentenceInNative,
      userAnswer: userAnswer ?? this.userAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      pronunciationScore: pronunciationScore ?? this.pronunciationScore,
    );
  }
}
