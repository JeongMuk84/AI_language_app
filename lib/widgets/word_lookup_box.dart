import 'package:flutter/material.dart';

import '../models/word_lookup_result.dart';
import '../theme/design_tokens.dart';

/// Static box showing a dictionary-style lookup for a single word/phrase
/// (see `GeminiService.lookupWord`, used by `DictionaryScreen`) — separate
/// from [FeedbackBox], which grades a full-sentence translation attempt, so
/// the two never overwrite each other on screen.
class WordLookupBox extends StatelessWidget {
  const WordLookupBox({
    super.key,
    required this.result,
    this.nativeLanguageLabel = 'native language',
    this.targetLanguageLabel = 'target language',
  });

  final WordLookupResult result;

  /// Human-readable names substituted into "Detected: ..." depending on
  /// [WordLookupResult.detectedLanguage] — pass the actual configured
  /// native/target language names (e.g. "한국어"/"Vietnamese") for a more
  /// useful label than the raw "native"/"target" the API returns.
  final String nativeLanguageLabel;
  final String targetLanguageLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final detectedLabel = result.detectedLanguage == 'target'
        ? targetLanguageLabel
        : nativeLanguageLabel;

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
          Text('Detected: $detectedLabel', style: textTheme.labelSmall),
          const SizedBox(height: 8),
          Text(
            result.translation,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(result.meaning, style: textTheme.bodyMedium),
          if (result.synonyms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Similar: ${result.synonyms.join(', ')}', style: textTheme.bodySmall),
          ],
          if (result.antonyms.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Opposite: ${result.antonyms.join(', ')}', style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
