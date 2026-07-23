/// 현재 review set에 뽑힌 문장 하나를 나타내는 모델(참고:
/// `ReviewSessionService.buildReviewSet`) — TTS 캐시에 오디오가 아직 남아
/// 있음이 확인된 `ReviewRecord`에, 그 캐시 위치 정보를 더한 것이다.
/// `ReviewViewModel`이 복습 화면에서 이 목록을 순회하며 문제를 표시하고,
/// `ReviewProgress.reviewItemList`로 저장되어 앱 재시작 후에도 같은 목록을
/// 이어서 사용할 수 있다.
class ReviewItem {
  /// [sentenceInTarget]/[sentenceInNative]는 복습할 문장의 각 언어 버전,
  /// [cachedAudioPath]는 캐시된 오디오 파일명, [voiceUsed]는 그 오디오를
  /// 생성할 때 쓰인 TTS 음성이다.
  const ReviewItem({
    required this.sentenceInTarget,
    required this.sentenceInNative,
    this.cachedAudioPath,
    this.voiceUsed,
  });

  /// `ReviewProgress` 저장 파일 등에 담긴 항목 하나를 파싱해 [ReviewItem]을
  /// 만든다.
  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      sentenceInTarget: json['sentenceInTarget'] as String,
      sentenceInNative: json['sentenceInNative'] as String,
      cachedAudioPath: json['cachedAudioPath'] as String?,
      voiceUsed: json['voiceUsed'] as String?,
    );
  }

  /// 복습할 문장의 target language 버전.
  final String sentenceInTarget;

  /// 복습할 문장의 native language 버전.
  final String sentenceInNative;

  /// 현재 target language의 `audio_cache/<languageKey>/` 폴더 안에 있는
  /// 캐시된 `.wav` 파일의 (절대 경로가 아닌) 파일명만 — 참고:
  /// `TtsCacheLocation.path`.
  final String? cachedAudioPath;

  /// [cachedAudioPath] 오디오를 생성할 때 사용된 TTS 음성.
  final String? voiceUsed;

  /// [ReviewItem]을 JSON 맵으로 직렬화한다. `ReviewProgress.toJson`이
  /// `reviewItemList`를 저장할 때 사용한다.
  Map<String, dynamic> toJson() => {
        'sentenceInTarget': sentenceInTarget,
        'sentenceInNative': sentenceInNative,
        if (cachedAudioPath != null) 'cachedAudioPath': cachedAudioPath,
        if (voiceUsed != null) 'voiceUsed': voiceUsed,
      };
}
