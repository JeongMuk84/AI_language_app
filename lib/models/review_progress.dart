import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import 'review_item.dart';

/// A review session in progress, persisted so it survives an app restart
/// (see `SessionStateService.readReviewProgress`). Its mere presence on
/// disk *is* "isInReviewMode" — there's no separate flag to fall out of
/// sync with it.
class ReviewProgress {
  const ReviewProgress({
    required this.reviewItemList,
    required this.reviewCurrentIndex,
    required this.startedAt,
    this.currentUserTranslation,
    this.currentTranslationResult,
    this.currentPronunciationResult,
  });

  factory ReviewProgress.fromJson(Map<String, dynamic> json) {
    final translationJson = json['currentTranslationResult'] as Map<String, dynamic>?;
    final pronunciationJson = json['currentPronunciationResult'] as Map<String, dynamic>?;
    return ReviewProgress(
      reviewItemList: (json['reviewItemList'] as List? ?? const [])
          .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviewCurrentIndex: json['reviewCurrentIndex'] as int? ?? 0,
      startedAt: DateTime.parse(json['startedAt'] as String),
      currentUserTranslation: json['currentUserTranslation'] as String?,
      currentTranslationResult: translationJson == null
          ? null
          : TranslationResult.fromJson(translationJson),
      currentPronunciationResult: pronunciationJson == null
          ? null
          : PronunciationResult.fromJson(pronunciationJson),
    );
  }

  final List<ReviewItem> reviewItemList;
  final int reviewCurrentIndex;

  /// When this review set was built — used for the same "same local
  /// calendar day" rollover check as the learning session, so a review
  /// left mid-way overnight gets rebuilt fresh rather than resumed stale.
  final DateTime startedAt;

  /// Snapshot of progress on the item at [reviewCurrentIndex] — the
  /// learner's submitted translation, its grading result, and (if already
  /// attempted) the pronunciation result — so that if the app restarts (or
  /// this screen is otherwise remounted) mid-item, `ReviewViewModel` can
  /// restore exactly where the learner left off instead of wiping their
  /// submission and re-locking Play/Record behind "submit again". Null
  /// fields mean "not yet submitted/attempted for this item". Always reset
  /// to null when [reviewCurrentIndex] advances to a new item — a snapshot
  /// only ever describes the *current* item, never a completed one.
  final String? currentUserTranslation;
  final TranslationResult? currentTranslationResult;
  final PronunciationResult? currentPronunciationResult;

  Map<String, dynamic> toJson() => {
        'reviewItemList': reviewItemList.map((e) => e.toJson()).toList(),
        'reviewCurrentIndex': reviewCurrentIndex,
        'startedAt': startedAt.toIso8601String(),
        if (currentUserTranslation != null) 'currentUserTranslation': currentUserTranslation,
        if (currentTranslationResult != null)
          'currentTranslationResult': currentTranslationResult!.toJson(),
        if (currentPronunciationResult != null)
          'currentPronunciationResult': currentPronunciationResult!.toJson(),
      };

  ReviewProgress copyWith({int? reviewCurrentIndex}) {
    return ReviewProgress(
      reviewItemList: reviewItemList,
      reviewCurrentIndex: reviewCurrentIndex ?? this.reviewCurrentIndex,
      startedAt: startedAt,
    );
  }
}
