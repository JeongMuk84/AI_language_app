import 'validation_error.dart';

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
    required this.errors,
  });

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

  final bool isCorrect;

  /// Native-language overall comment on what differs, if anything —
  /// point-by-point corrections live in [errors], not crammed in here.
  final String feedback;

  /// Native-language translation of the original (target-language)
  /// sentence.
  final String translation;

  /// Native-language notes on key expressions/grammar, but with the actual
  /// target-language words/phrases quoted verbatim and glossed in
  /// parentheses (e.g. "간다(khong đi)") rather than paraphrased away.
  final String analysis;

  /// Specific, actionable corrections (wrong word/misspelling/wrong tone
  /// mark, etc.) — empty if the attempt matched the original.
  final List<ValidationError> errors;
}
