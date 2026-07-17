import 'package:flutter/material.dart';

import '../models/validation_error.dart';
import '../theme/design_tokens.dart';

/// Static box for showing grading/pronunciation-analysis feedback: an
/// optional correct/incorrect indicator, an optional match-rate percentage,
/// the feedback text itself, and (for text-graded results) a structured
/// list of specific corrections — see [ValidationError].
class FeedbackBox extends StatelessWidget {
  const FeedbackBox({
    super.key,
    required this.feedback,
    this.isCorrect,
    this.scorePercent,
    this.errors = const [],
  });

  final String feedback;
  final bool? isCorrect;

  /// 0-100, e.g. a pronunciation match rate.
  final double? scorePercent;

  /// Specific "what you wrote -> what it should be" corrections, rendered
  /// one per row below [feedback]. Empty for results that don't have
  /// structured errors (e.g. pronunciation feedback).
  final List<ValidationError> errors;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final Color accent = switch (isCorrect) {
      true => DesignColors.semanticSuccess,
      false => DesignColors.semanticError,
      null => colorScheme.primary,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignRadii.md),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCorrect != null || scorePercent != null) ...[
            Row(
              children: [
                if (isCorrect != null) ...[
                  Icon(isCorrect! ? Icons.check_circle : Icons.cancel, color: accent, size: 20),
                  const SizedBox(width: 8),
                ],
                if (scorePercent != null)
                  Text(
                    '${scorePercent!.round()}%',
                    style: textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(feedback, style: textTheme.bodyMedium),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < errors.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ErrorRow(error: errors[i]),
            ],
          ],
        ],
      ),
    );
  }
}

/// One "what you wrote -> what it should be" row, with an explanation
/// underneath. The wrong/corrected contrast is carried by color (struck-
/// through red vs. bold green) plus an arrow between them, not just text.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.error});

  final ValidationError error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                error.userWrote,
                style: textTheme.bodyMedium?.copyWith(
                  color: DesignColors.semanticError,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward, size: 16),
            ),
            Expanded(
              child: Text(
                error.shouldBe,
                style: textTheme.bodyMedium?.copyWith(
                  color: DesignColors.semanticSuccess,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (error.explanation.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(error.explanation, style: textTheme.bodySmall),
        ],
      ],
    );
  }
}
