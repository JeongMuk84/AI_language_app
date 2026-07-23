import 'package:flutter/material.dart';

import '../models/validation_error.dart';
import '../theme/design_tokens.dart';

/// 채점/발음 분석 피드백을 보여주는 정적인 박스: 선택적인 정답/오답
/// 표시, 선택적인 일치율 퍼센트, 피드백 텍스트 본문, 그리고(텍스트 채점
/// 결과의 경우) 구체적인 교정 사항을 구조화한 목록 — [ValidationError]
/// 참고. WritingScreen, ShadowingDictationScreen, ShadowingPronunciationScreen,
/// WritingListeningScreen, ReviewScreen에서 채점/발음 분석 결과를 표시하는
/// 데 쓰인다.
class FeedbackBox extends StatelessWidget {
  /// [feedback], [isCorrect], [scorePercent], [errors]를 받아 박스를
  /// 구성한다.
  const FeedbackBox({
    super.key,
    required this.feedback,
    this.isCorrect,
    this.scorePercent,
    this.errors = const [],
  });

  /// 표시할 피드백 본문 텍스트.
  final String feedback;

  /// 정답 여부. null이면 정답/오답 아이콘을 표시하지 않는다.
  final bool? isCorrect;

  /// 0-100 범위, 예를 들어 발음 일치율.
  final double? scorePercent;

  /// "학습자가 쓴 것 -> 실제 정답"의 구체적인 교정 목록으로, [feedback]
  /// 아래에 한 행씩 렌더링된다. 구조화된 오류가 없는 결과(예: 발음 피드백)
  /// 에서는 비어 있다.
  final List<ValidationError> errors;

  /// [isCorrect]/[scorePercent] 유무에 따른 상단 표시줄, [feedback] 본문,
  /// 그리고 [errors]가 있으면 그 각각을 [_ErrorRow]로 그린다. 정답 여부에
  /// 따라 테두리·아이콘 색상(성공/실패/중립)이 달라진다.
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

/// "학습자가 쓴 것 -> 실제 정답" 한 줄과 그 아래 설명으로 구성된 행.
/// 오답/교정 사이의 대비는 텍스트만이 아니라 색상(빨간 취소선 vs. 굵은
/// 초록색)과 그 사이의 화살표로도 전달된다.
class _ErrorRow extends StatelessWidget {
  /// 표시할 [error]를 받아 행을 구성한다.
  const _ErrorRow({required this.error});

  final ValidationError error;

  /// [error.userWrote]를 취소선 빨간색으로, [error.shouldBe]를 굵은
  /// 초록색으로, 그 사이에 화살표를 넣어 그리고, 설명이 있으면 그 아래에
  /// 작은 텍스트로 덧붙인다.
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
