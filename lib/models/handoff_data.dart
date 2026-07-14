/// Persisted "pick up where you left off" record for one target language,
/// stored as `handoff_<language>.json` in the app documents directory.
class HandoffData {
  const HandoffData({
    required this.language,
    required this.summary,
    required this.generatedAt,
    this.difficultyLevel,
  });

  factory HandoffData.fromJson(Map<String, dynamic> json) {
    return HandoffData(
      language: json['language'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? '',
      difficultyLevel: json['difficultyLevel']?.toString(),
    );
  }

  final String language;
  final String summary;

  /// ISO-8601 timestamp of when this handoff was generated.
  final String generatedAt;
  final String? difficultyLevel;

  Map<String, dynamic> toJson() => {
        'language': language,
        'summary': summary,
        'generatedAt': generatedAt,
        if (difficultyLevel != null) 'difficultyLevel': difficultyLevel,
      };
}
