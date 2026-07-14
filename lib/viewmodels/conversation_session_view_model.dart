import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gemini_message.dart';

class ConversationSessionState {
  const ConversationSessionState({this.history = const []});

  final List<GeminiMessage> history;
}

/// Holds the local multi-turn conversation history for the current
/// learning session. Gemini doesn't remember anything between requests —
/// this list is what the app resends each time to keep context — so
/// [reset] (clearing it) is what "forgetting the conversation" means here.
class ConversationSessionViewModel extends Notifier<ConversationSessionState> {
  @override
  ConversationSessionState build() => const ConversationSessionState();

  void addMessage(GeminiMessage message) {
    state = ConversationSessionState(history: [...state.history, message]);
  }

  void reset() {
    state = const ConversationSessionState();
  }

  /// Seeds a fresh session with a handoff summary as prior context, used
  /// when resuming a language for which a handoff file exists.
  void seedWithContext(String contextSummary) {
    state = ConversationSessionState(
      history: [GeminiMessage(role: 'model', text: contextSummary)],
    );
  }
}

final conversationSessionProvider =
    NotifierProvider<ConversationSessionViewModel, ConversationSessionState>(
  ConversationSessionViewModel.new,
);
