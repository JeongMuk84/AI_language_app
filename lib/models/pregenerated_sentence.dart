import 'exercise_type.dart';

/// `GeminiService.generateDailySentenceSet`이 한 번의 호출로 미리 만들어낸,
/// 오늘 하루치 학습 세트 안의 문장 하나를 나타내는 모델. [type]이
/// [ExerciseType.shadowing]이면 [text]는 대상 언어 문장(받아쓰기용),
/// [ExerciseType.writing]이면 [text]는 모국어 문장(번역용)이다 —
/// `GeminiService.generateNextSentence`가 그때그때 하나씩 생성하던 것과
/// 같은 역할을, `SentenceQueue`에 미리 담아두는 형태로 대체한다.
class PregeneratedSentence {
  /// [type]과 [text]로 문장 하나를 만든다.
  const PregeneratedSentence({required this.type, required this.text});

  /// Gemini의 `generateDailySentenceSet` 응답(JSON)에서 문장 하나를 파싱해
  /// [PregeneratedSentence]를 만든다.
  factory PregeneratedSentence.fromJson(Map<String, dynamic> json) {
    return PregeneratedSentence(
      type: ExerciseType.fromValue(json['type'] as String?),
      text: json['text'] as String? ?? '',
    );
  }

  /// 이 항목이 shadowing(받아쓰기)용인지 writing(번역)용인지.
  final ExerciseType type;

  /// 문장 본문 — [type]에 따라 대상 언어 또는 모국어로 쓰여 있다.
  final String text;

  /// [PregeneratedSentence]를 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {'type': type.value, 'text': text};
}
