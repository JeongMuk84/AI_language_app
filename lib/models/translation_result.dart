import 'mixed_language_segment.dart';

/// Result of grading a writing (translation) attempt. Graded by meaning,
/// not exact wording — [referenceTranslation] is a model answer used for
/// comparison, not the sentence the learner actually produced.
/// [completedSentence] is what actually gets read/said aloud next (see its
/// doc comment below).
class TranslationResult {
  const TranslationResult({
    required this.isCorrect,
    required this.feedback,
    required this.referenceTranslation,
    required this.completedSentence,
    required this.mixedLanguageSegments,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    final segments = (json['mixedLanguageSegments'] as List? ?? const [])
        .map((e) => MixedLanguageSegment.fromJson(e as Map<String, dynamic>))
        .toList();
    return TranslationResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      feedback: json['feedback'] as String? ?? '',
      referenceTranslation: json['referenceTranslation'] as String? ?? '',
      completedSentence: json['completedSentence'] as String? ?? '',
      mixedLanguageSegments: segments,
    );
  }

  final bool isCorrect;

  /// Native-language explanation of grammar/wording issues in the
  /// target-language portion of the attempt.
  final String feedback;

  /// A model translation of the native sentence, written ENTIRELY in the
  /// target language — shown for comparison only.
  final String referenceTranslation;

  /// The learner's own attempt, rewritten entirely in the target language
  /// (any native-language segments replaced by their target-language
  /// equivalent). This — not [referenceTranslation] — is the sentence that
  /// gets displayed/read aloud/graded on the following listening &
  /// pronunciation screen, since it's the sentence the learner actually
  /// produced (augmented, not replaced by a model example).
  final String completedSentence;

  /// Native-language segments the learner fell back to instead of writing
  /// in the target language — empty if the attempt was already entirely in
  /// the target language.
  final List<MixedLanguageSegment> mixedLanguageSegments;

  Map<String, dynamic> toJson() => {
        'isCorrect': isCorrect,
        'feedback': feedback,
        'referenceTranslation': referenceTranslation,
        'completedSentence': completedSentence,
        'mixedLanguageSegments': mixedLanguageSegments.map((e) => e.toJson()).toList(),
      };
}
