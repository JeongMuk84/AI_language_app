/// One native-language segment the learner fell back to inside an
/// otherwise target-language translation attempt (e.g. a Korean speaker
/// learning Vietnamese writing "Tôi muốn 예약하다 nhà hàng") — surfaced as a
/// learning opportunity rather than graded as an error. See
/// `GeminiService.validateTranslation`.
class MixedLanguageSegment {
  const MixedLanguageSegment({
    required this.originalSegment,
    required this.suggestedTranslation,
    required this.explanation,
  });

  factory MixedLanguageSegment.fromJson(Map<String, dynamic> json) {
    return MixedLanguageSegment(
      originalSegment: json['originalSegment'] as String? ?? '',
      suggestedTranslation: json['suggestedTranslation'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
    );
  }

  /// The native-language text exactly as the learner wrote it.
  final String originalSegment;

  /// How to say [originalSegment], written ENTIRELY in the target language.
  final String suggestedTranslation;

  /// Nuance/alternatives, written in the native language.
  final String explanation;

  Map<String, dynamic> toJson() => {
        'originalSegment': originalSegment,
        'suggestedTranslation': suggestedTranslation,
        'explanation': explanation,
      };
}
