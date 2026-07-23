/// 자유 입력된 언어 이름(예: "Vietnamese", "베트남어", "Español")으로부터
/// 파일 시스템에 안전한 key를 만들어낸다 — 소문자로 바꾸고, 공백과
/// 파일 시스템 예약 문자를 밑줄(underscore)로 합치며, 그 외 문자는
/// 그대로 둔다. Unicode 문자는 음역(transliteration)하거나 해시로
/// 뭉개지 않고 의도적으로 그대로 보존한다 — 이 앱은 이미
/// `HandoffService`의 `handoff_<language>.json`처럼 Unicode 문자가 그대로
/// 들어간 파일명을 쓰고 있고, "베트남어"와 "日本語"처럼 서로 다른
/// 언어를 같은 ASCII 자리표시자(placeholder)로 뭉개버리면 두 언어의
/// 데이터가 조용히 합쳐져 버리기 때문이다.
///
/// `audio_cache/<key>/`, `review_history/<key>/`,
/// `conversation_history/<key>/` 같은 언어별 저장소 폴더의 key로
/// 사용되며, `TtsCacheService`, `StorageLocationService`,
/// `ReviewHistoryService`, `ConversationHistoryService`에서 각각
/// 현재 target language를 이 함수로 변환해 폴더 경로를 구성한다. 이를
/// 통해 한 학습자가 여러 target language를 오가며 학습해도 언어별
/// 데이터가 서로 섞이지 않는다.
///
/// [language]가 비어 있거나 공백만 있으면(trim 후 빈 문자열이 되면)
/// `'unknown'`을 반환한다.
String languageStorageKey(String language) {
  final trimmed = language.trim();
  if (trimmed.isEmpty) return 'unknown';
  final sanitized = trimmed.toLowerCase().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}
