/// 레벨(난이도) 배치 테스트의 문제 하나를 나타내는 모델. Gemini가 생성해
/// 반환한다. `GeminiService.generateLevelTest`가 Gemini 응답을 파싱해 이
/// 목록을 만들고, `LevelTestViewModel.loadQuestions`가 이를
/// `LevelTestState.questions`에 담아 `LevelTestScreen`에 표시한다.
class LevelTestQuestion {
  /// [prompt]는 화면에 표시할 문제 문장, [sourceLang]은 [prompt]가 쓰인
  /// 언어, [direction]은 번역 방향 설명이다.
  const LevelTestQuestion({
    required this.prompt,
    required this.sourceLang,
    required this.direction,
  });

  /// Gemini의 레벨 테스트 생성 응답(JSON)에서 문제 하나를 파싱해
  /// [LevelTestQuestion]을 만든다.
  factory LevelTestQuestion.fromJson(Map<String, dynamic> json) {
    return LevelTestQuestion(
      prompt: json['prompt'] as String? ?? '',
      sourceLang: json['sourceLang'] as String? ?? 'target',
      direction: json['direction'] as String? ?? '',
    );
  }

  /// 사용자에게 보여줄 문제 문장.
  final String prompt;

  /// [prompt]가 작성된 언어: `'native'` 또는 `'target'`.
  final String sourceLang;

  /// 번역 방향을 사람이 읽을 수 있게 짧게 설명한 문구, 예: "Translate to
  /// French:".
  final String direction;

  /// [LevelTestQuestion]을 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'sourceLang': sourceLang,
        'direction': direction,
      };
}
