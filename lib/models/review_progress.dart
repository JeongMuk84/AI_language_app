import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import 'review_item.dart';

/// 진행 중인 복습 세션 상태를 나타내는 모델. 앱 재시작에도 살아남도록
/// 저장된다(참고: `SessionStateService.readReviewProgress`/
/// `writeReviewProgress`). 이 값이 디스크에 존재한다는 사실 자체가 곧
/// "지금 복습 모드다(isInReviewMode)"라는 의미다 — 따로 플래그를 두지
/// 않으므로 상태가 서로 어긋날 여지가 없다. `ReviewViewModel`이 복습 화면의
/// 진행 상태를 이 모델로 읽고 쓴다.
class ReviewProgress {
  /// [reviewItemList]는 이번 복습 세션에서 다룰 문항 목록,
  /// [reviewCurrentIndex]는 현재 보고 있는 항목의 인덱스, [startedAt]은
  /// 이 복습 세트를 만든 시각이다. [currentUserTranslation]/
  /// [currentTranslationResult]/[currentPronunciationResult]는 현재
  /// 항목에서의 진행 스냅샷이다.
  const ReviewProgress({
    required this.reviewItemList,
    required this.reviewCurrentIndex,
    required this.startedAt,
    this.currentUserTranslation,
    this.currentTranslationResult,
    this.currentPronunciationResult,
  });

  /// 저장된 review progress 파일 내용을 파싱해 [ReviewProgress]를 만든다.
  /// `SessionStateService.readReviewProgress`가 사용한다.
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

  /// 이번 복습 세션에서 다룰 [ReviewItem] 목록.
  final List<ReviewItem> reviewItemList;

  /// 현재 보고 있는 [reviewItemList] 항목의 인덱스.
  final int reviewCurrentIndex;

  /// 이 review set이 만들어진 시각 — 학습 세션과 동일한 "로컬 캘린더 날짜가
  /// 같은지" 롤오버 판정에 사용된다. 그래서 밤사이 걸쳐 중단된 복습은
  /// 이어서 재개되는 대신 새로 다시 만들어진다.
  final DateTime startedAt;

  /// [reviewCurrentIndex]가 가리키는 항목에서의 진행 스냅샷 — 학습자가
  /// 제출한 번역, 그 채점 결과, (이미 시도했다면) 발음 분석 결과. 앱이
  /// 재시작되거나 이 화면이 다시 마운트되어도 `ReviewViewModel`이 학습자가
  /// 멈췄던 지점을 정확히 복원할 수 있도록 하기 위함이다 — 제출 내용을
  /// 지워버리거나 Play/Record 버튼을 다시 "재제출 전까지 잠금" 상태로
  /// 되돌리지 않기 위함. 필드가 null이면 "이 항목에 대해 아직 제출/시도하지
  /// 않음"을 뜻한다. [reviewCurrentIndex]가 다음 항목으로 넘어갈 때는 항상
  /// null로 초기화된다 — 이 스냅샷은 언제나 *현재* 항목만을 설명하며,
  /// 이미 완료된 항목을 설명하는 일은 없다.
  final String? currentUserTranslation;

  /// [currentUserTranslation]에 대한 채점 결과.
  final TranslationResult? currentTranslationResult;

  /// 현재 항목에 대해 이미 시도된 발음 분석 결과.
  final PronunciationResult? currentPronunciationResult;

  /// [ReviewProgress]를 review progress 저장 파일용 JSON 맵으로 직렬화한다.
  /// `SessionStateService.writeReviewProgress`가 사용한다.
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

  /// [reviewCurrentIndex]만 바꾼 새 [ReviewProgress]를 만드는 불변 갱신
  /// 메서드(그 외 필드는 스냅샷 규칙대로 초기화된 새 인스턴스가 된다).
  /// 현재 코드베이스에서는 `ReviewViewModel`이 매번 `ReviewProgress(...)`를
  /// 직접 새로 생성해 쓰고 있어 이 메서드 자체는 아직 호출되지 않지만,
  /// 인덱스만 바꾸는 갱신을 표현하기 위해 존재한다.
  ReviewProgress copyWith({int? reviewCurrentIndex}) {
    return ReviewProgress(
      reviewItemList: reviewItemList,
      reviewCurrentIndex: reviewCurrentIndex ?? this.reviewCurrentIndex,
      startedAt: startedAt,
    );
  }
}
