/// Result of a dictionary-style lookup on a single word/short phrase typed
/// into ReviewScreen's translation textbox — distinct from
/// [TranslationResult], which grades a full-sentence translation attempt.
class WordLookupResult {
  const WordLookupResult({
    required this.detectedLanguage,
    required this.translation,
    required this.meaning,
    required this.synonyms,
    required this.antonyms,
  });

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

  /// `"native"` or `"target"` — which language the looked-up input was
  /// written in.
  final String detectedLanguage;

  /// The input's equivalent in the OTHER language (target if the input was
  /// native, native if the input was target) — written entirely in that
  /// other language.
  final String translation;

  /// Explanation of the meaning/nuance, written in the native language.
  final String meaning;

  /// Similar words/phrases in the SAME language as the input — target-
  /// language entries are quoted with a native-language gloss in
  /// parentheses, matching the app's established "quote + gloss" pattern.
  final List<String> synonyms;

  /// Same language/formatting rules as [synonyms]; empty if none apply.
  final List<String> antonyms;
}
