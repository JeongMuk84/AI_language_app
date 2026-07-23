/// 녹음된 발음 시도를 target 문장과 비교 분석한 결과를 나타내는 모델.
/// `GeminiService.analyzePronunciation`이 녹음된 오디오를 Gemini에 보내 받은
/// 응답을 파싱해 반환하며, `ShadowingViewModel`/`WritingViewModel`/
/// `ReviewViewModel`이 발음 연습 화면에서 이 결과를 표시한다.
/// `ReviewProgress.currentPronunciationResult`로도 저장되어 앱 재시작 후
/// 복습 화면 복원에 쓰인다.
class PronunciationResult {
  /// [recognizedText]는 Gemini가 알아들은 발화 내용, [feedback]은 모국어
  /// 설명, [accuracyPercent]는 정확도 점수(0-100)다.
  const PronunciationResult({
    required this.recognizedText,
    required this.feedback,
    required this.accuracyPercent,
  });

  /// `GeminiService.analyzePronunciation`이 받은 Gemini 응답(JSON)을 파싱해
  /// [PronunciationResult]를 만든다.
  factory PronunciationResult.fromJson(Map<String, dynamic> json) {
    final rawScore = json['accuracyPercent'] as num? ?? 0;
    return PronunciationResult(
      recognizedText: json['recognizedText'] as String? ?? '',
      feedback: json['feedback'] as String? ?? '',
      accuracyPercent: rawScore.toDouble().clamp(0, 100),
    );
  }

  /// Gemini가 알아들은 내용을 TARGET language 그대로 옮겨적은 것(번역하지
  /// 않음) — 학습자가 자신의 발음이 정확히 어떻게 인식되었는지 모국어로
  /// 의역된 것이 아니라 있는 그대로 볼 수 있도록 하기 위함이다.
  final String recognizedText;

  /// 모국어로 작성된 설명/코멘트.
  final String feedback;

  /// 발음 정확도 점수. 0-100 범위.
  final double accuracyPercent;

  /// [PronunciationResult]를 JSON 맵으로 직렬화한다. `ReviewProgress.toJson`이
  /// `currentPronunciationResult`를 저장할 때 사용한다.
  Map<String, dynamic> toJson() => {
        'recognizedText': recognizedText,
        'feedback': feedback,
        'accuracyPercent': accuracyPercent,
      };
}
