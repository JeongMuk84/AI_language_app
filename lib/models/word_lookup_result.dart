/// Dictionary 화면(`dictionary_screen.dart`)의 검색창에 입력한 단어/짧은
/// 구를 사전처럼 조회한 결과를 나타내는 모델 — 문장 전체 번역 시도를
/// 채점하는 [TranslationResult]와는 별개다. `GeminiService.lookupWord`가
/// Gemini 응답을 파싱해 반환하며, `word_lookup_box.dart` 위젯이 이 결과를
/// 화면에 표시한다.
class WordLookupResult {
  /// [detectedLanguage]는 입력이 native/target 중 어느 언어로 감지됐는지,
  /// [translation]은 반대쪽 언어로의 번역, [meaning]은 뜻/뉘앙스 설명,
  /// [synonyms]/[antonyms]는 유의어/반의어 목록이다.
  const WordLookupResult({
    required this.detectedLanguage,
    required this.translation,
    required this.meaning,
    required this.synonyms,
    required this.antonyms,
  });

  /// `GeminiService.lookupWord`가 받은 Gemini 응답(JSON)을 파싱해
  /// [WordLookupResult]를 만든다.
  factory WordLookupResult.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) =>
        (value as List? ?? const []).map((e) => e.toString()).toList();
    return WordLookupResult(
      detectedLanguage: json['detectedLanguage'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      meaning: json['meaning'] as String? ?? '',
      synonyms: stringList(json['synonyms']),
      antonyms: stringList(json['antonyms']),
    );
  }

  /// 조회한 입력이 어느 언어로 작성되었는지: `"native"` 또는 `"target"`.
  final String detectedLanguage;

  /// 입력의 반대쪽 언어 번역(입력이 native였다면 target으로, target이었다면
  /// native로) — 전체가 그 반대쪽 언어로만 작성된다.
  final String translation;

  /// 뜻/뉘앙스에 대한 설명. 모국어로 작성된다.
  final String meaning;

  /// 입력과 같은 언어로 된 유사 단어/구 목록 — target-language 항목은 이 앱의
  /// 정형화된 "원문 인용 + 괄호 설명" 패턴대로, 원문을 그대로 인용한 뒤
  /// 괄호 안에 모국어 뜻을 붙인다.
  final List<String> synonyms;

  /// [synonyms]와 동일한 언어/포맷 규칙을 따르는 반의어 목록; 해당하는 것이
  /// 없으면 비어 있다.
  final List<String> antonyms;
}
