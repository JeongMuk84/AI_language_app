import 'package:flutter/material.dart';

/// The sentence display half of the "hide sentence, then reveal" toggle
/// shared by ShadowingPronunciationScreen and WritingListeningScreen: shows
/// [sentence] when not [hidden], or a same-height blank spacer when hidden
/// (so the layout below doesn't jump).
class HideableSentence extends StatelessWidget {
  const HideableSentence({super.key, required this.sentence, required this.hidden});

  final String sentence;
  final bool hidden;

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

/// The toggle button half of the "hide sentence, then reveal" toggle shared
/// by ShadowingPronunciationScreen and WritingListeningScreen.
class SentenceVisibilityButton extends StatelessWidget {
  const SentenceVisibilityButton({super.key, required this.hidden, required this.onPressed});

  final bool hidden;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(hidden ? 'Show Sentence' : 'Record Without Seeing the Sentence'),
    );
  }
}
