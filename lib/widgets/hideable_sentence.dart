import 'package:flutter/material.dart';

/// ShadowingPronunciationScreen과 WritingListeningScreen이 공유하는
/// "문장을 숨겼다가 다시 보여주기" 토글 중 문장 표시를 담당하는 절반:
/// [hidden]이 아니면 [sentence]를 보여주고, [hidden]이면 같은 높이의 빈
/// 공간을 표시한다(아래쪽 레이아웃이 흔들리지 않도록).
class HideableSentence extends StatelessWidget {
  /// [sentence]와 [hidden] 상태를 받아 위젯을 구성한다.
  const HideableSentence({super.key, required this.sentence, required this.hidden});

  /// 표시할 문장 텍스트.
  final String sentence;

  /// true이면 문장 대신 빈 공간을 그린다.
  final bool hidden;

  /// [hidden]이면 높이 32의 빈 `SizedBox`를, 아니면 [sentence]를 가운데
  /// 정렬된 큰 텍스트로 그린다.
  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox(height: 32);
    return Text(
      sentence,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    );
  }
}

/// ShadowingPronunciationScreen과 WritingListeningScreen이 공유하는
/// "문장을 숨겼다가 다시 보여주기" 토글 중 버튼을 담당하는 절반.
class SentenceVisibilityButton extends StatelessWidget {
  /// [hidden] 상태와 탭 시 호출할 [onPressed] 콜백을 받아 위젯을
  /// 구성한다.
  const SentenceVisibilityButton({super.key, required this.hidden, required this.onPressed});

  /// 현재 문장이 숨겨져 있는지 여부 — 버튼 문구를 결정한다.
  final bool hidden;

  /// 버튼이 탭됐을 때 호출되는 콜백. 보통 상위 화면에서 [hidden] 상태를
  /// 토글하는 데 쓰인다.
  final VoidCallback onPressed;

  /// [hidden] 여부에 따라 "Show Sentence" 또는 "Record Without Seeing the
  /// Sentence" 문구가 적힌 `OutlinedButton`을 그린다.
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(hidden ? 'Show Sentence' : 'Record Without Seeing the Sentence'),
    );
  }
}
