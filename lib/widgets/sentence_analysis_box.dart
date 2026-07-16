import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Static box showing a sentence's native-language translation and a brief
/// analysis of its key expressions/grammar. Visually distinct from
/// [FeedbackBox] (different surface tint, no correctness accent) so
/// grading feedback and this "what does it mean" content read as two
/// separate things. Internally scrollable since analysis text length
/// varies.
class SentenceAnalysisBox extends StatelessWidget {
  const SentenceAnalysisBox({super.key, required this.translation, required this.analysis});

  final String translation;
  final String analysis;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignRadii.md),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Translation & Analysis', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Text(
              translation,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(analysis, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
