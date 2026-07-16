/// One sentence the learner has previously completed a turn on, tracked for
/// spaced review — independent of the TTS cache (which exists purely for
/// playback and can evict entries; this is the learning record).
class ReviewRecord {
  const ReviewRecord({
    required this.sentenceInTarget,
    required this.sentenceInNative,
    required this.firstLearnedAt,
    this.lastReviewedAt,
    this.reviewCount = 0,
  });

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

  final String sentenceInTarget;
  final String sentenceInNative;
  final DateTime firstLearnedAt;
  final DateTime? lastReviewedAt;
  final int reviewCount;

  Map<String, dynamic> toJson() => {
        'sentenceInTarget': sentenceInTarget,
        'sentenceInNative': sentenceInNative,
        'firstLearnedAt': firstLearnedAt.toIso8601String(),
        if (lastReviewedAt != null) 'lastReviewedAt': lastReviewedAt!.toIso8601String(),
        'reviewCount': reviewCount,
      };

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
