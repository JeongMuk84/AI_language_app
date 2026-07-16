/// Result of grading a shadowing dictation attempt. [translation] and
/// [analysis] ride along on the same call (rather than a separate Gemini
/// request) to show the learner what the sentence means and how it's built,
/// in their native language, once they've submitted.
class DictationResult {
  const DictationResult({
    required this.isCorrect,
    required this.feedback,
    required this.translation,
    required this.analysis,
  });

  factory DictationResult.fromJson(Map<String, dynamic> json) {
    return DictationResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      feedback: json['feedback'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      analysis: json['analysis'] as String? ?? '',
    );
  }

  final bool isCorrect;

  /// Native-language explanation of what differs, if anything. Never the
  /// dictated sentence or the learner's answer — those stay exactly as
  /// they are (target language / whatever the learner typed) and are
  /// never round-tripped through this result.
  final String feedback;

  /// Native-language translation of the original (target-language)
  /// sentence.
  final String translation;

  /// Native-language notes on key expressions/grammar, but with the actual
  /// target-language words/phrases quoted verbatim and glossed in
  /// parentheses (e.g. "간다(khong đi)") rather than paraphrased away.
  final String analysis;
}
