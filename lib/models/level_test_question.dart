/// One question in the placement level test, as returned by Gemini.
class LevelTestQuestion {
  const LevelTestQuestion({
    required this.prompt,
    required this.sourceLang,
    required this.direction,
  });

  factory LevelTestQuestion.fromJson(Map<String, dynamic> json) {
    return LevelTestQuestion(
      prompt: json['prompt'] as String? ?? '',
      sourceLang: json['sourceLang'] as String? ?? 'target',
      direction: json['direction'] as String? ?? '',
    );
  }

  /// The sentence shown to the user.
  final String prompt;

  /// Which language [prompt] is written in: `'native'` or `'target'`.
  final String sourceLang;

  /// Short human-readable description of the translation direction,
  /// e.g. "Translate to French:".
  final String direction;

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'sourceLang': sourceLang,
        'direction': direction,
      };
}
