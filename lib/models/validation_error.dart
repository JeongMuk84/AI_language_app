/// One specific, actionable correction within a graded attempt (see
/// `GeminiService.validateTranslation` / `validateDictation`) — deliberately
/// structured instead of free text, so feedback can never collapse into a
/// vague "there's a typo somewhere" with no way to act on it.
class ValidationError {
  const ValidationError({
    required this.userWrote,
    required this.shouldBe,
    required this.explanation,
  });

  factory ValidationError.fromJson(Map<String, dynamic> json) {
    return ValidationError(
      userWrote: json['userWrote'] as String? ?? '',
      shouldBe: json['shouldBe'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
    );
  }

  /// The exact word/phrase the learner wrote wrong, quoted verbatim, in
  /// the target language.
  final String userWrote;

  /// The corrected word/phrase ONLY — never a full corrected sentence, so
  /// the learner still has to recall the rest themselves. In the target
  /// language.
  final String shouldBe;

  /// Why, written in the native language.
  final String explanation;

  Map<String, dynamic> toJson() => {
        'userWrote': userWrote,
        'shouldBe': shouldBe,
        'explanation': explanation,
      };
}
