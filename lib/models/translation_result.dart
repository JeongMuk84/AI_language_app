import 'mixed_language_segment.dart';
import 'validation_error.dart';

/// Result of grading a writing (translation) attempt. Graded by meaning,
/// not exact wording — [referenceTranslation] is a model answer used for
/// comparison, not the sentence the learner actually produced.
///
/// There is deliberately no "completed sentence" here: a mixed-language
/// attempt is never auto-completed into a target-language sentence on the
/// learner's behalf. [mixedLanguageSegments] only explains how to say each
/// native-language part — the learner has to edit their own attempt and
/// resubmit an entirely target-language sentence themselves before the
/// turn can be considered done (see [hasNativeLanguageMixed]).
class TranslationResult {
  const TranslationResult({
    required this.isCorrect,
    required this.feedback,
    required this.referenceTranslation,
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
      mixedLanguageSegments: segments,
      errors: errors,
    );
  }

  /// Whether the TARGET-LANGUAGE portion of the attempt is grammatically/
  /// lexically correct — independent of [hasNativeLanguageMixed]. A
  /// grammatically perfect attempt that still mixes in native-language
  /// words is `isCorrect: true` here (the part that IS in the target
  /// language is fine) but still isn't a completed turn; see
  /// [hasNativeLanguageMixed].
  final bool isCorrect;

  /// Native-language overall comment on the target-language portion —
  /// point-by-point corrections live in [errors], not crammed in here.
  final String feedback;

  /// A model translation of the native sentence, written ENTIRELY in the
  /// target language — shown for comparison only.
  final String referenceTranslation;

  /// Native-language segments the learner fell back to instead of writing
  /// in the target language — empty if the attempt was already entirely in
  /// the target language. Each entry explains how to say that part in the
  /// target language, for the learner to apply themselves.
  final List<MixedLanguageSegment> mixedLanguageSegments;

  /// Specific, actionable corrections within the target-language portion
  /// (grammar/word-choice/spelling/tone-mark mistakes) — empty if there
  /// weren't any. Never duplicates what's already covered by
  /// [mixedLanguageSegments].
  final List<ValidationError> errors;

  /// True if any part of the attempt was left in the native language.
  /// Derived locally from [mixedLanguageSegments] rather than trusting a
  /// separately-model-authored boolean, so it can never disagree with the
  /// segments actually returned. A turn only counts as complete when this
  /// is false AND [isCorrect] is true — see `WritingState.canProceedToListening`.
  bool get hasNativeLanguageMixed => mixedLanguageSegments.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'isCorrect': isCorrect,
        'feedback': feedback,
        'referenceTranslation': referenceTranslation,
        'mixedLanguageSegments': mixedLanguageSegments.map((e) => e.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}
