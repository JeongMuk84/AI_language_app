/// 특정 target language의 "1년에 걸친 점진적 난이도 상승" 진행 상태를
/// 나타내는 모델. `difficulty_progression/<languageKey>/progression.json`에
/// 저장된다(`DifficultyProgressionService` 참고). [startDate]는 그 언어의
/// 레벨 테스트를 처음 완료해 학습을 시작한 날짜(또는 이 기능이 처음 그
/// 언어에 대해 계산이 필요해진 날짜)이고, [initialScore]는 그 시점의
/// 0~100 난이도 점수(레벨 테스트 결과 CEFR 등급을 매핑한 값)다. 이 둘은
/// 한 번 기록되면 바뀌지 않는다 — 오늘의 난이도 점수는 매번 이 값들로부터
/// `DifficultyProgressionService.readTodayScore`가 다시 계산한다.
class DifficultyProgression {
  /// [startDate]와 [initialScore]로 진행 기록을 만든다.
  const DifficultyProgression({required this.startDate, required this.initialScore});

  /// 저장된 progression.json 내용을 파싱해 [DifficultyProgression]을 만든다.
  /// `DifficultyProgressionService`가 사용한다.
  factory DifficultyProgression.fromJson(Map<String, dynamic> json) {
    return DifficultyProgression(
      startDate: DateTime.parse(json['startDate'] as String),
      initialScore: (json['initialScore'] as num).toDouble(),
    );
  }

  /// 이 언어의 점진적 난이도 상승이 시작된 날짜.
  final DateTime startDate;

  /// [startDate] 시점의 0~100 시작 난이도 점수.
  final double initialScore;

  /// [DifficultyProgression]을 progression.json에 저장할 JSON 맵으로
  /// 직렬화한다.
  Map<String, dynamic> toJson() => {
    'startDate': startDate.toIso8601String(),
    'initialScore': initialScore,
  };
}
