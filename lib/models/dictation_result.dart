import 'validation_error.dart';

/// shadowing dictation 시도를 채점한 결과를 나타내는 모델.
/// `GeminiService.validateDictation`이 Gemini 응답 JSON을 파싱해 반환하며,
/// `ShadowingViewModel`이 이 값을 `ShadowingState.dictationResult`에 담아
/// 채점 화면에 표시한다. [translation]과 [analysis]는 별도의 Gemini 요청을
/// 또 보내는 대신 같은 호출에 함께 실어 받는다 — 학습자가 제출한 직후 그
/// 자리에서 문장의 뜻과 구조를 모국어로 바로 보여주기 위해서다.
class DictationResult {
  /// [isCorrect]는 정답 여부, [feedback]은 전체적인 코멘트, [translation]은
  /// 원문의 모국어 번역, [analysis]는 문장 구조/표현 설명, [errors]는
  /// 항목별 교정 목록이다.
  const DictationResult({
    required this.isCorrect,
    required this.feedback,
    required this.translation,
    required this.analysis,
    required this.errors,
  });

  /// `GeminiService.validateDictation`이 받은 Gemini 응답(JSON)을 파싱해
  /// [DictationResult]를 만든다.
  factory DictationResult.fromJson(Map<String, dynamic> json) {
    final errors = (json['errors'] as List? ?? const [])
        .map((e) => ValidationError.fromJson(e as Map<String, dynamic>))
        .toList();
    return DictationResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      feedback: json['feedback'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      analysis: json['analysis'] as String? ?? '',
      errors: errors,
    );
  }

  /// 학습자의 받아쓰기가 원문과 일치했는지 여부.
  final bool isCorrect;

  /// 무엇이 어떻게 달랐는지에 대한 모국어 전체 코멘트 — 항목별 세부 교정은
  /// 여기에 몰아넣지 않고 [errors]에 따로 담는다.
  final String feedback;

  /// 원문(target language 문장)의 모국어 번역.
  final String translation;

  /// 핵심 표현/문법에 대한 모국어 설명. 실제 target language 단어/구는
  /// 의역하지 않고 원문 그대로 인용한 뒤 괄호로 뜻을 덧붙인다
  /// (예: "간다(khong đi)").
  final String analysis;

  /// 구체적이고 실행 가능한 교정 목록(틀린 단어, 오탈자, 성조 표기 오류 등).
  /// 받아쓰기가 원문과 일치했다면 비어 있다.
  final List<ValidationError> errors;
}
