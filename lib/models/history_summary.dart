import 'conversation_turn.dart';
import 'exercise_type.dart';

/// 하루치 history 파일에 기록되는, 중복 제거된 턴 하나를 나타내는 모델.
/// `ConversationTurn`과 필드 구성이 거의 동일하지만, history 파일에 영구
/// 보관되는 별도의 항목 타입으로 분리되어 있다. `HistoryService`가
/// `finalizeSession()`에서 그날의 `ConversationTurn` 목록을 이 타입으로
/// 변환해 `history_<yyyy-MM-dd>.json`에 저장한다.
class HistorySentenceEntry {
  /// [turnId]는 원본 턴의 고유 id, [type]은 shadowing/writing 여부,
  /// [timestamp]는 턴 시각, [sentenceInTarget]/[sentenceInNative]는 다룬
  /// 문장의 각 언어 버전, [userAnswer]는 학습자의 제출 답, [isCorrect]는
  /// 정답 여부, [pronunciationScore]는 발음 점수다.
  const HistorySentenceEntry({
    required this.turnId,
    required this.type,
    required this.timestamp,
    this.sentenceInTarget,
    this.sentenceInNative,
    this.userAnswer,
    this.isCorrect,
    this.pronunciationScore,
  });

  /// 진행 중 세션의 [ConversationTurn]을 history 저장용 [HistorySentenceEntry]로
  /// 변환한다. `HistoryService.finalizeSession`이 세션 종료 시 그날 쌓인
  /// 턴들을 history 파일에 옮겨 담을 때 사용한다.
  factory HistorySentenceEntry.fromTurn(ConversationTurn turn) {
    return HistorySentenceEntry(
      turnId: turn.turnId,
      type: turn.type,
      timestamp: turn.timestamp,
      sentenceInTarget: turn.sentenceInTarget,
      sentenceInNative: turn.sentenceInNative,
      userAnswer: turn.userAnswer,
      isCorrect: turn.isCorrect,
      pronunciationScore: turn.pronunciationScore,
    );
  }

  /// history 파일(`history_<yyyy-MM-dd>.json`)에 저장된 항목 하나를 파싱해
  /// [HistorySentenceEntry]를 만든다. `HistorySummary.fromJson`이 `sentences`
  /// 목록을 파싱할 때 각 원소에 사용한다.
  factory HistorySentenceEntry.fromJson(Map<String, dynamic> json) {
    return HistorySentenceEntry(
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

  /// 원본 턴의 고유 id.
  final String turnId;

  /// shadowing/writing 여부.
  final ExerciseType type;

  /// 이 턴이 기록된 시각.
  final DateTime timestamp;

  /// 다룬 문장의 target language 버전.
  final String? sentenceInTarget;

  /// 다룬 문장의 native language 버전.
  final String? sentenceInNative;

  /// 학습자가 제출한 답.
  final String? userAnswer;

  /// 정답 여부.
  final bool? isCorrect;

  /// 발음 점수(0-100).
  final double? pronunciationScore;

  /// history 파일에 저장할 JSON 맵으로 직렬화한다. `HistorySummary.toJson`이
  /// `sentences` 목록을 직렬화할 때 각 원소에 사용한다.
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
}

/// 하루치 세션(들)을 마무리하며 만들어지는, 중복 제거된 최종 요약.
/// `history/history_<yyyy-MM-dd>.json`으로 저장된다.
/// `HistoryService.finalizeSession`이 `_buildSummary`로 이 객체를 만들어
/// 파일에 쓰고, 학습 기록/통계 화면이 이 파일들을 읽어 표시한다.
class HistorySummary {
  /// [date]는 이 요약이 속한 날짜(yyyy-MM-dd), [practicedSentenceCount]는 그날
  /// 연습한 문장 수, [sentences]는 개별 턴 기록 목록, [lastExerciseType]은 그날
  /// 마지막으로 진행한 exercise 종류, [pronunciationAccuracy]는 평균 발음
  /// 정확도다.
  const HistorySummary({
    required this.date,
    required this.practicedSentenceCount,
    required this.sentences,
    required this.lastExerciseType,
    this.pronunciationAccuracy,
  });

  /// `history_<yyyy-MM-dd>.json` 파일 내용을 파싱해 [HistorySummary]를 만든다.
  factory HistorySummary.fromJson(Map<String, dynamic> json) {
    return HistorySummary(
      date: json['date'] as String,
      practicedSentenceCount: json['practicedSentenceCount'] as int? ?? 0,
      sentences: (json['sentences'] as List? ?? const [])
          .map((s) => HistorySentenceEntry.fromJson(s as Map<String, dynamic>))
          .toList(),
      lastExerciseType: ExerciseType.fromValue(json['lastExerciseType'] as String?),
      pronunciationAccuracy: (json['pronunciationAccuracy'] as num?)?.toDouble(),
    );
  }

  /// yyyy-MM-dd, local time.
  final String date;
  final int practicedSentenceCount;
  final List<HistorySentenceEntry> sentences;
  final ExerciseType lastExerciseType;

  /// Average pronunciation match rate (0-100) across scored turns, or null
  /// if no turn in this day had a pronunciation score.
  final double? pronunciationAccuracy;

  Map<String, dynamic> toJson() => {
        'date': date,
        'practicedSentenceCount': practicedSentenceCount,
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'lastExerciseType': lastExerciseType.value,
        if (pronunciationAccuracy != null) 'pronunciationAccuracy': pronunciationAccuracy,
      };
}
