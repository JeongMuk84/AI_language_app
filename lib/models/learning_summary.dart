/// 특정 target language로 지금까지 학습한 내용을 압축해 누적해온 요약을
/// 나타내는 모델. `learning_summary/<languageKey>/summary.json`에 저장된다
/// (`LearningSummaryService` 참고). `GeminiService.updateLearningSummary`가
/// 하루치 세션이 마감될 때마다 기존 값과 그날 내용을 합쳐 새로 압축한
/// 텍스트로 갱신하며, `GeminiService.generateDailySentenceSet`이 이 값을
/// 참고해 이미 다룬 주제/어휘/상황을 반복하지 않도록 한다.
class LearningSummary {
  /// [cumulativeSummary]는 압축된 누적 요약 텍스트, [lastUpdatedDate]는
  /// 마지막으로 갱신된 시각이다.
  const LearningSummary({required this.cumulativeSummary, required this.lastUpdatedDate});

  /// 저장된 summary.json 내용을 파싱해 [LearningSummary]를 만든다.
  /// `LearningSummaryService.readCumulativeSummary`가 사용한다.
  factory LearningSummary.fromJson(Map<String, dynamic> json) {
    return LearningSummary(
      cumulativeSummary: json['cumulativeSummary'] as String? ?? '',
      lastUpdatedDate: DateTime.parse(json['lastUpdatedDate'] as String),
    );
  }

  /// 압축·병합되어 유지되는 누적 요약 텍스트(대략 200단어 내외).
  final String cumulativeSummary;

  /// 이 요약이 마지막으로 갱신된 시각.
  final DateTime lastUpdatedDate;

  /// [LearningSummary]를 summary.json에 저장할 JSON 맵으로 직렬화한다.
  /// `LearningSummaryService.writeCumulativeSummary`가 사용한다.
  Map<String, dynamic> toJson() => {
    'cumulativeSummary': cumulativeSummary,
    'lastUpdatedDate': lastUpdatedDate.toIso8601String(),
  };
}
