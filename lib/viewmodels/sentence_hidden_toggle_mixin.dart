import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared "hide sentence, then reveal" toggle behavior for
/// [ShadowingViewModel] (ShadowingPronunciationScreen) and
/// [WritingViewModel] (WritingListeningScreen) — both screens let the
/// learner attempt pronunciation without reading the sentence first.
/// Hiding always starts a fresh pronunciation attempt; revealing again
/// doesn't touch it.
mixin SentenceHiddenToggleMixin<S> on Notifier<S> {
  bool sentenceHiddenOf(S state);

  /// Returns a copy of [state] with `sentenceHidden` set to [hidden] and,
  /// only when [hidden] is true, the pronunciation attempt (result +
  /// error) cleared.
  S copyWithSentenceHidden(S state, {required bool hidden});

  void toggleSentenceHidden() {
    final hidden = sentenceHiddenOf(state);
    state = copyWithSentenceHidden(state, hidden: !hidden);
  }
}
