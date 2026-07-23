import 'package:flutter/material.dart';

import '../models/word_lookup_result.dart';
import '../theme/design_tokens.dart';

/// 단어/구 하나에 대한 사전식 조회 결과를 보여주는 정적인 박스
/// (`GeminiService.lookupWord` 참고, `DictionaryScreen`에서 쓰임) —
/// 문장 전체 번역 시도를 채점하는 [FeedbackBox]와는 별개이므로, 화면
/// 위에서 서로를 덮어쓰는 일이 없다.
class WordLookupBox extends StatelessWidget {
  /// [result]와, 선택적인 [nativeLanguageLabel]/[targetLanguageLabel]을
  /// 받아 위젯을 구성한다.
  const WordLookupBox({
    super.key,
    required this.result,
    this.nativeLanguageLabel = 'native language',
    this.targetLanguageLabel = 'target language',
  });

  /// 조회 API가 반환한 결과(번역, 뜻, 유의어/반의어, 감지된 언어 등).
  final WordLookupResult result;

  /// [WordLookupResult.detectedLanguage] 값에 따라 "Detected: ..." 문구에
  /// 대입되는 사람이 읽기 좋은 이름 — API가 반환하는 원시 "native"/
  /// "target" 대신, 실제로 설정된 모국어/target language 이름(예:
  /// "한국어"/"Vietnamese")을 넘기면 더 유용한 라벨이 된다.
  final String nativeLanguageLabel;

  /// [nativeLanguageLabel]과 동일한 용도로, target language 쪽 이름.
  final String targetLanguageLabel;

  /// 감지된 언어 라벨, 번역, 뜻, 유의어/반의어(있는 경우)를 순서대로
  /// 그린다.
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
