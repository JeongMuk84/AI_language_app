/// 특정 target language에 대해 "이전에 어디까지 학습했는지" 이어서 시작할 수
/// 있도록 저장되는 인계(handoff) 기록. 앱 문서 디렉토리에
/// `handoff_<language>.json`으로 저장된다. `HandoffService.write`가 이 값을
/// 파일에 쓰고, `SettingsViewModel`이 언어를 전환할 때 이전 target language에
/// 대한 요약(`GeminiService.generateHandoffSummary` 결과)을 이 모델에 담아
/// 넘긴다.
class HandoffData {
  /// [language]는 이 기록이 속한 target language, [summary]는 Gemini가 생성한
  /// 학습 진행 요약 텍스트, [generatedAt]은 생성 시각, [difficultyLevel]은
  /// 당시의 난이도 설정이다.
  const HandoffData({
    required this.language,
    required this.summary,
    required this.generatedAt,
    this.difficultyLevel,
  });

  /// `handoff_<language>.json` 파일 내용을 파싱해 [HandoffData]를 만든다.
  factory HandoffData.fromJson(Map<String, dynamic> json) {
    return HandoffData(
      language: json['language'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? '',
      difficultyLevel: json['difficultyLevel']?.toString(),
    );
  }

  /// 이 인계 기록이 속한 target language.
  final String language;

  /// Gemini가 생성한 학습 진행 요약 텍스트.
  final String summary;

  /// 이 handoff가 생성된 시각의 ISO-8601 타임스탬프 문자열.
  final String generatedAt;

  /// 인계 시점의 난이도 설정.
  final String? difficultyLevel;

  /// `handoff_<language>.json`에 저장할 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {
        'language': language,
        'summary': summary,
        'generatedAt': generatedAt,
        if (difficultyLevel != null) 'difficultyLevel': difficultyLevel,
      };
}
