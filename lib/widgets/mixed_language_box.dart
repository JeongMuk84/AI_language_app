import 'package:flutter/material.dart';

import '../models/mixed_language_segment.dart';
import '../theme/design_tokens.dart';

/// Static box shown on WritingScreen when the learner's translation
/// attempt mixed in native-language segments (parts they don't yet know
/// how to say in the target language) — a separate, non-graded learning
/// aid, distinct from [FeedbackBox]'s grading feedback.
class MixedLanguageBox extends StatelessWidget {
  const MixedLanguageBox({super.key, required this.segments});

  final List<MixedLanguageSegment> segments;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignRadii.md),
        border: Border.all(color: colorScheme.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Words you didn\'t know',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const Divider(height: 24),
            Text(
              '"${segments[i].originalSegment}"',
              style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 4),
            Text(
              segments[i].suggestedTranslation,
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(segments[i].explanation, style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
