import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Static box for showing grading/pronunciation-analysis feedback: an
/// optional correct/incorrect indicator, an optional match-rate percentage,
/// and the feedback text itself.
class FeedbackBox extends StatelessWidget {
  const FeedbackBox({super.key, required this.feedback, this.isCorrect, this.scorePercent});

  final String feedback;
  final bool? isCorrect;

  /// 0-100, e.g. a pronunciation match rate.
  final double? scorePercent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: accent, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(feedback, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
