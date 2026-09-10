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
  /// [PronunciationResult]를 만든다. Gemini의 응답 스키마는 오디오를 먼저
  /// 있는 그대로 전사(`recognizedText`)한 뒤 그 전사 결과를 원문과 비교해
  /// `matchPercentage`를 계산하도록 설계되어 있다(`GeminiService.
  /// analyzePronunciation`의 프롬프트 참고) — `matchPercentage`를
  /// [accuracyPercent]로 읽어온다.
  factory PronunciationResult.fromJson(Map<String, dynamic> json) {
    final rawScore = json['matchPercentage'] as num? ?? 0;
    return PronunciationResult(
      recognizedText: json['recognizedText'] as String? ?? '',
      feedback: json['feedback'] as String? ?? '',
      accuracyPercent: rawScore.toDouble().clamp(0, 100),
    );
  }

  /// 클라이언트 측에서(오디오를 아예 Gemini로 보내지 않고) 만드는 결과 —
  /// `AudioRecorderWidget`이 녹음 전체에 걸쳐 말소리로 볼 만한 진폭을 한
  /// 번도 감지하지 못했을 때, 각 화면의 `analyzePronunciation`이 API 호출을
  /// 건너뛰고 이 값을 그대로 쓴다. Gemini가 무음/잡음을 판정해 돌려주는
  /// `noSpeechDetected: true` 응답과 결과적으로 동일한 모양(빈
  /// [recognizedText], 0점)이 되도록 맞춰져 있다.
  factory PronunciationResult.noSpeechDetected() => const PronunciationResult(
        recognizedText: '',
        feedback: 'No speech detected. Please try again.',
        accuracyPercent: 0,
      );

  /// Gemini가 오디오만 듣고(원문을 참고해 "그럴듯하게 맞추지" 않고) 있는
  /// 그대로 옮겨적은 전사 결과, TARGET language 그대로(번역하지 않음) —
  /// 학습자가 단어를 빠뜨렸거나 다르게 발음했다면 그 사실이 그대로
  /// 반영되어야 한다. 알아들을 수 있는 말이 전혀 없었으면(무음/잡음만)
  /// 빈 문자열이다 — 이 경우 UI는 "No speech was detected." 같은 안내로
  /// 대신 표시해야 하며, 빈 줄을 그냥 보여주면 안 된다.
  final String recognizedText;

  /// 모국어로 작성된 설명/코멘트.
  final String feedback;

  /// [recognizedText]와 원문을 텍스트 대 텍스트로 비교해 나온 일치율.
  /// 0-100 범위. 무음/잡음만 있었으면(직접 또는 클라이언트 판정으로) 0.
  final double accuracyPercent;

  /// [PronunciationResult]를 JSON 맵으로 직렬화한다. `ReviewProgress.toJson`이
  /// `currentPronunciationResult`를 저장할 때 사용한다.
  Map<String, dynamic> toJson() => {
        'recognizedText': recognizedText,
        'feedback': feedback,
        'accuracyPercent': accuracyPercent,
      };
}
