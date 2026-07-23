import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// 문장의 모국어 번역과 핵심 표현/문법에 대한 간단한 분석을 보여주는
/// 정적인 박스. ShadowingDictationScreen에서 쓰인다. [FeedbackBox]와
/// 시각적으로 구분되도록(다른 표면 색조, 정답 여부 강조 없음) 하여, 채점
/// 피드백과 이 "무슨 뜻인가"라는 내용이 서로 다른 것으로 읽히게 한다.
/// 분석 텍스트 길이가 다양하므로 내부적으로 스크롤 가능하다.
class SentenceAnalysisBox extends StatelessWidget {
  /// [translation]과 [analysis]를 받아 위젯을 구성한다.
  const SentenceAnalysisBox({super.key, required this.translation, required this.analysis});

  /// 문장의 모국어 번역 텍스트.
  final String translation;

  /// 핵심 표현/문법에 대한 분석 텍스트.
  final String analysis;

  /// 최대 높이가 제한된 스크롤 가능한 컨테이너 안에 [translation]과
  /// [analysis]를 순서대로 그린다.
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
