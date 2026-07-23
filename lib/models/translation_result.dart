import 'mixed_language_segment.dart';
import 'validation_error.dart';

/// writing(번역) 시도를 채점한 결과를 나타내는 모델. `GeminiService.
/// validateTranslation`이 Gemini 응답 JSON을 파싱해 반환하며,
/// `WritingViewModel`이 이 값을 채점 화면에 표시하고
/// `ReviewProgress.currentTranslationResult`로 저장해 앱 재시작 후에도
/// 복습 진행 상태를 복원한다. 채점은 정확한 단어 일치가 아니라 의미
/// 기준으로 이루어진다 — [referenceTranslation]은 비교를 위한 모범 답안일
/// 뿐, 학습자가 실제로 작성한 문장이 아니다.
///
/// 이 모델에는 의도적으로 "완성된 문장(completed sentence)" 필드가 없다:
/// 모국어가 섞인 시도를 앱이 대신 target language 문장으로 자동 완성해주는
/// 일은 절대 없다. [mixedLanguageSegments]는 각 모국어 부분을 어떻게 말해야
/// 하는지 설명해줄 뿐이며, 학습자가 직접 자신의 시도를 고쳐서 전체가
/// target language로만 된 문장을 다시 제출해야 비로소 턴이 완료된 것으로
/// 간주된다(참고: [hasNativeLanguageMixed]).
class TranslationResult {
  /// [isCorrect]는 target-language 부분의 정오답 여부, [feedback]은 전체
  /// 코멘트, [referenceTranslation]은 비교용 모범 번역, [mixedLanguageSegments]
  /// 는 모국어로 남아있는 구간 목록, [errors]는 항목별 교정 목록이다.
  const TranslationResult({
    required this.isCorrect,
    required this.feedback,
    required this.referenceTranslation,
    required this.mixedLanguageSegments,
    required this.errors,
  });

  /// `GeminiService.validateTranslation`이 받은 Gemini 응답(JSON)을 파싱해
  /// [TranslationResult]를 만든다.
  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    final segments = (json['mixedLanguageSegments'] as List? ?? const [])
        .map((e) => MixedLanguageSegment.fromJson(e as Map<String, dynamic>))
        .toList();
    final errors = (json['errors'] as List? ?? const [])
        .map((e) => ValidationError.fromJson(e as Map<String, dynamic>))
        .toList();
    return TranslationResult(
      isCorrect: json['isCorrect'] as bool? ?? false,
      feedback: json['feedback'] as String? ?? '',
      referenceTranslation: json['referenceTranslation'] as String? ?? '',
      mixedLanguageSegments: segments,
      errors: errors,
    );
  }

  /// 시도한 답 중 TARGET LANGUAGE 부분이 문법적/어휘적으로 맞는지 여부 —
  /// [hasNativeLanguageMixed]와는 독립적인 값이다. 문법적으로는 완벽하지만
  /// 여전히 모국어 단어가 섞여 있는 시도도 여기서는 `isCorrect: true`가
  /// 될 수 있다(target language로 쓰인 부분 자체는 문제가 없으므로). 하지만
  /// 그렇다고 해서 턴이 완료된 것은 아니다 — 참고: [hasNativeLanguageMixed].
  final bool isCorrect;

  /// target-language 부분에 대한 모국어 전체 코멘트 — 항목별 세부 교정은
  /// 여기 몰아넣지 않고 [errors]에 따로 담는다.
  final String feedback;

  /// 모국어 문장에 대한 모범 번역으로, 전체가 target language로만 작성됨 —
  /// 비교용으로만 보여준다.
  final String referenceTranslation;

  /// target language로 쓰는 대신 학습자가 모국어로 대신 써버린 구간 목록 —
  /// 시도가 이미 전체 target language였다면 비어 있다. 각 항목은 학습자가
  /// 직접 적용할 수 있도록, 그 부분을 target language로 어떻게 말해야
  /// 하는지 설명한다.
  final List<MixedLanguageSegment> mixedLanguageSegments;

  /// target-language 부분 안에서의 구체적이고 실행 가능한 교정 목록(문법/
  /// 단어 선택/철자/성조 표기 오류 등) — 없으면 비어 있다.
  /// [mixedLanguageSegments]가 이미 다루는 내용과 중복되지 않는다.
  final List<ValidationError> errors;

  /// 시도한 답의 일부라도 모국어로 남아 있었는지 여부. 모델이 별도로
  /// 반환한 boolean 값을 그대로 믿는 대신 [mixedLanguageSegments]로부터
  /// 로컬에서 계산한다 — 그래야 실제로 반환된 segment들과 절대 어긋나지
  /// 않는다. 이 값이 false이고 동시에 [isCorrect]가 true일 때만 턴이
  /// 완료된 것으로 취급된다 — 참고: `WritingState.canProceedToListening`.
  bool get hasNativeLanguageMixed => mixedLanguageSegments.isNotEmpty;

  /// [TranslationResult]를 JSON 맵으로 직렬화한다.
  /// `ReviewProgress.toJson`이 `currentTranslationResult`를 저장할 때
  /// 사용한다.
  Map<String, dynamic> toJson() => {
        'isCorrect': isCorrect,
        'feedback': feedback,
        'referenceTranslation': referenceTranslation,
        'mixedLanguageSegments': mixedLanguageSegments.map((e) => e.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}
