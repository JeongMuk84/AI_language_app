import 'mixed_language_segment.dart';
import 'validation_error.dart';

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
    required this.errors,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    final segments = (json['mixedLanguageSegments'] as List? ?? const [])
        .map((e) => MixedLanguageSegment.fromJson(e as Map<String, dynamic>))
        .toList();
    final errors = (json['errors'] as List? ?? const [])
        .map((e) => ValidationError.fromJson(e as Map<String, dynamic>))
        .toList();
    return TranslationResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      feedback: json['feedback'] as String? ?? '',
      referenceTranslation: json['referenceTranslation'] as String? ?? '',
      completedSentence: json['completedSentence'] as String? ?? '',
      mixedLanguageSegments: segments,
      errors: errors,
    );
  }

  final bool isCorrect;

  /// Native-language overall comment on the target-language portion —
  /// point-by-point corrections live in [errors], not crammed in here.
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

  /// Specific, actionable corrections within the target-language portion
  /// (grammar/word-choice/spelling/tone-mark mistakes) — empty if there
  /// weren't any. Never duplicates what's already covered by
  /// [mixedLanguageSegments].
  final List<ValidationError> errors;

  Map<String, dynamic> toJson() => {
        'isCorrect': isCorrect,
        'feedback': feedback,
        'referenceTranslation': referenceTranslation,
        'completedSentence': completedSentence,
        'mixedLanguageSegments': mixedLanguageSegments.map((e) => e.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}
