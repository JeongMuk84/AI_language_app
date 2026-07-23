import 'package:flutter/material.dart';

import '../models/mixed_language_segment.dart';
import '../theme/design_tokens.dart';

/// 학습자의 번역 시도에 모국어 구간(target language로 아직 어떻게
/// 말하는지 모르는 부분)이 섞여 있을 때 WritingScreen에 표시되는 정적인
/// 박스 — [FeedbackBox]의 채점 피드백과는 별개로, 채점되지 않는 보조
/// 학습 도구다.
class MixedLanguageBox extends StatelessWidget {
  /// 표시할 [segments] 목록을 받아 위젯을 구성한다.
  const MixedLanguageBox({super.key, required this.segments});

  /// 모국어로 섞여 쓰인 구간들. 각 항목은 원문 구절, 제안 번역, 설명을
  /// 담고 있다.
  final List<MixedLanguageSegment> segments;

  /// [segments]를 원문 구절 -> 제안 번역 -> 설명 순으로 하나씩 나열해
  /// 그린다.
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
