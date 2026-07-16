/// Result of analyzing a recorded pronunciation attempt against a target
/// sentence.
class PronunciationResult {
  const PronunciationResult({
    required this.recognizedText,
    required this.feedback,
    required this.accuracyPercent,
  });

  factory PronunciationResult.fromJson(Map<String, dynamic> json) {
    final rawScore = json['accuracyPercent'] as num? ?? 0;
    return PronunciationResult(
      recognizedText: json['recognizedText'] as String? ?? '',
      feedback: json['feedback'] as String? ?? '',
      accuracyPercent: rawScore.toDouble().clamp(0, 100),
    );
  }

  /// What Gemini heard, transcribed in the TARGET language (never
  /// translated) — so the learner can see exactly what their pronunciation
  /// was recognized as, not a native-language paraphrase of it.
  final String recognizedText;

  /// Native-language explanation/notes.
  final String feedback;

  /// 0-100.
  final double accuracyPercent;
}
