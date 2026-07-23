/// target language로 작성해야 할 번역 시도 안에서 학습자가 모국어로 대신
/// 써버린 구간 하나를 나타내는 모델(예: 베트남어를 배우는 한국어 화자가
/// "Tôi muốn 예약하다 nhà hàng"라고 쓴 경우) — 오답으로 감점하기보다는
/// 학습 기회로 보여주기 위한 용도다. `GeminiService.validateTranslation`이
/// Gemini 응답을 파싱해 `TranslationResult.mixedLanguageSegments`에 담고,
/// `mixed_language_box.dart` 위젯이 이 목록을 화면에 표시한다.
class MixedLanguageSegment {
  /// [originalSegment]는 학습자가 실제로 쓴 모국어 원문, [suggestedTranslation]은
  /// 그 부분을 target language로 어떻게 써야 하는지, [explanation]은 뉘앙스나
  /// 대안 설명이다.
  const MixedLanguageSegment({
    required this.originalSegment,
    required this.suggestedTranslation,
    required this.explanation,
  });

  /// `GeminiService.validateTranslation`이 받은 Gemini 응답(JSON)의
  /// `mixedLanguageSegments` 배열 원소 하나를 파싱해
  /// [MixedLanguageSegment]를 만든다.
  factory MixedLanguageSegment.fromJson(Map<String, dynamic> json) {
    return MixedLanguageSegment(
      originalSegment: json['originalSegment'] as String? ?? '',
      suggestedTranslation: json['suggestedTranslation'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
    );
  }

  /// 학습자가 실제로 쓴 그대로의 모국어 텍스트.
  final String originalSegment;

  /// [originalSegment]를 어떻게 말해야 하는지, 전체가 target language로만
  /// 작성된 표현.
  final String suggestedTranslation;

  /// 뉘앙스나 다른 표현 대안에 대한 설명. 모국어로 작성된다.
  final String explanation;

  /// [MixedLanguageSegment]를 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {
        'originalSegment': originalSegment,
        'suggestedTranslation': suggestedTranslation,
        'explanation': explanation,
      };
}
