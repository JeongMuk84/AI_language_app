import 'gemini_message.dart';

/// Snapshot of a learner's progress in one target language, handed to
/// Gemini to produce a handoff summary when they switch away from it.
///
/// There's no real learning screen yet, so today this only carries the
/// difficulty level and whatever local conversation history exists.
/// [conversationHistory] is the deliberate extension point: once actual
/// learning-session logs (exercises done, mistakes made, vocab covered...)
/// exist, add fields here rather than growing [GeminiService]'s prompt
/// building in place.
class LearningSessionSnapshot {
  const LearningSessionSnapshot({
    required this.nativeLanguage,
    required this.targetLanguage,
    this.difficultyLevel,
    this.conversationHistory = const [],
  });

  final String nativeLanguage;
  final String targetLanguage;
  final String? difficultyLevel;
  final List<GeminiMessage> conversationHistory;
}
