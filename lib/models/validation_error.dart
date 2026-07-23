/// 채점된 시도 안에서의 구체적이고 실행 가능한 교정 항목 하나(참고:
/// `GeminiService.validateTranslation` / `validateDictation`) — 자유
/// 텍스트가 아니라 의도적으로 구조화된 형태를 쓴다. 그래야 피드백이
/// "어딘가 오타가 있다"는 식의 막연하고 행동으로 옮길 수 없는 코멘트로
/// 뭉개지지 않는다. `TranslationResult.errors`/`DictationResult.errors`에
/// 목록으로 담겨 `feedback_box.dart` 위젯이 화면에 표시한다.
class ValidationError {
  /// [userWrote]는 학습자가 실제로 쓴(틀린) 표현, [shouldBe]는 올바른
  /// 표현, [explanation]은 그 이유에 대한 모국어 설명이다.
  const ValidationError({
    required this.userWrote,
    required this.shouldBe,
    required this.explanation,
  });

  /// Gemini 응답(JSON)의 교정 항목 하나를 파싱해 [ValidationError]를 만든다.
  factory ValidationError.fromJson(Map<String, dynamic> json) {
    return ValidationError(
      userWrote: json['userWrote'] as String? ?? '',
      shouldBe: json['shouldBe'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
    );
  }

  /// 학습자가 틀리게 쓴 단어/구를 원문 그대로 인용한 것. target language로
  /// 작성된다.
  final String userWrote;

  /// 교정된 단어/구 그 자체만 — 절대 문장 전체를 고쳐서 주지 않는다. 그래야
  /// 학습자가 나머지 부분은 스스로 떠올려야 한다. target language로
  /// 작성된다.
  final String shouldBe;

  /// 왜 틀렸는지에 대한 설명. 모국어로 작성된다.
  final String explanation;

  /// [ValidationError]를 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {
        'userWrote': userWrote,
        'shouldBe': shouldBe,
        'explanation': explanation,
      };
}
