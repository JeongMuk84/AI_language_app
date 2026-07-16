/// Result of grading a writing (translation) attempt. Graded by meaning,
/// not exact wording — [referenceTranslation] is a model answer used to
/// drive the follow-up listening/pronunciation exercise, not the only
/// acceptable answer.
class TranslationResult {
  const TranslationResult({
    required this.isCorrect,
    required this.feedback,
    required this.referenceTranslation,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    return TranslationResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      feedback: json['feedback'] as String? ?? '',
      referenceTranslation: json['referenceTranslation'] as String? ?? '',
    );
  }

  final bool isCorrect;

  /// Native-language explanation of grammar/wording issues.
  final String feedback;

  /// The model translation, written ENTIRELY in the target language — this
  /// is what the learner reads/says aloud next (drives the follow-up
  /// listening/pronunciation exercise), so it must never be a
  /// native-language explanation.
  final String referenceTranslation;
}
