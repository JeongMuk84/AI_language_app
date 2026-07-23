/// 학습자가 예전에 한 번 이상 turn을 완료한 문장을 spaced review를 위해
/// 추적하는 영구 기록. TTS 캐시(순전히 재생용이며 항목이 evict될 수 있는)와는
/// 독립적인, 이것이 진짜 "학습 기록"이다. `ReviewHistoryService`가
/// `review_history.json`에서 읽고 쓰며, `recordIfNew`가 새 문장을 처음 등록,
/// `markReviewed`가 복습 완료를 기록한다. `ReviewSessionService.buildReviewSet`
/// 이 이 기록들을 바탕으로 오늘의 복습 세트를 고르고,
/// `ListeningHistoryService.buildHistory`도 이 기록을 재생 가능한 문장 목록의
/// 원본으로 사용한다.
class ReviewRecord {
  /// [sentenceInTarget]/[sentenceInNative]는 이 기록의 키가 되는 문장의 각
  /// 언어 버전, [firstLearnedAt]은 처음 학습한 시각(이후 절대 갱신되지
  /// 않음), [lastReviewedAt]은 가장 최근 복습 시각, [reviewCount]는 지금까지
  /// 복습한 횟수다.
  const ReviewRecord({
    required this.sentenceInTarget,
    required this.sentenceInNative,
    required this.firstLearnedAt,
    this.lastReviewedAt,
    this.reviewCount = 0,
  });

  /// `review_history.json`에 저장된 항목 하나를 파싱해 [ReviewRecord]를
  /// 만든다.
  factory ReviewRecord.fromJson(Map<String, dynamic> json) {
    return ReviewRecord(
      sentenceInTarget: json['sentenceInTarget'] as String,
      sentenceInNative: json['sentenceInNative'] as String,
      firstLearnedAt: DateTime.parse(json['firstLearnedAt'] as String),
      lastReviewedAt: json['lastReviewedAt'] != null
          ? DateTime.parse(json['lastReviewedAt'] as String)
          : null,
      reviewCount: json['reviewCount'] as int? ?? 0,
    );
  }

  /// 이 기록의 키가 되는, target language로 작성된 문장.
  final String sentenceInTarget;

  /// 해당 문장의 native language 번역.
  final String sentenceInNative;

  /// 이 문장을 처음 학습한 시각. 이후 같은 문장에 대한 반복 turn이 있어도
  /// 절대 갱신되지 않는다.
  final DateTime firstLearnedAt;

  /// 가장 최근에 복습을 완료한 시각. 아직 한 번도 복습하지 않았다면 null.
  final DateTime? lastReviewedAt;

  /// 지금까지 이 문장을 복습한 횟수.
  final int reviewCount;

  /// [ReviewRecord]를 `review_history.json` 저장용 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {
        'sentenceInTarget': sentenceInTarget,
        'sentenceInNative': sentenceInNative,
        'firstLearnedAt': firstLearnedAt.toIso8601String(),
        if (lastReviewedAt != null) 'lastReviewedAt': lastReviewedAt!.toIso8601String(),
        'reviewCount': reviewCount,
      };

  /// 일부 필드만 바꾼 새 [ReviewRecord]를 만드는 불변 갱신 메서드.
  /// `ReviewHistoryService.markReviewed`가 복습 완료 시 [lastReviewedAt]과
  /// [reviewCount]를 갱신할 때 사용한다.
  ReviewRecord copyWith({DateTime? lastReviewedAt, int? reviewCount}) {
    return ReviewRecord(
      sentenceInTarget: sentenceInTarget,
      sentenceInNative: sentenceInNative,
      firstLearnedAt: firstLearnedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }
}
