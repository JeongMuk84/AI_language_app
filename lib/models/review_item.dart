/// One sentence selected into the current review set (see
/// `ReviewSessionService.buildReviewSet`) — a [ReviewRecord] that's known
/// to still have cached audio available, plus that cache location.
class ReviewItem {
  const ReviewItem({
    required this.sentenceInTarget,
    required this.sentenceInNative,
    this.cachedAudioPath,
    this.voiceUsed,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      sentenceInTarget: json['sentenceInTarget'] as String,
      sentenceInNative: json['sentenceInNative'] as String,
      cachedAudioPath: json['cachedAudioPath'] as String?,
      voiceUsed: json['voiceUsed'] as String?,
    );
  }

  final String sentenceInTarget;
  final String sentenceInNative;

  /// Bare filename (not an absolute path) of the cached `.wav` within
  /// `tts_cache/` — see `TtsCacheLocation.path`.
  final String? cachedAudioPath;
  final String? voiceUsed;

  Map<String, dynamic> toJson() => {
        'sentenceInTarget': sentenceInTarget,
        'sentenceInNative': sentenceInNative,
        if (cachedAudioPath != null) 'cachedAudioPath': cachedAudioPath,
        if (voiceUsed != null) 'voiceUsed': voiceUsed,
      };
}
