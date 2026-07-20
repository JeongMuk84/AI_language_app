/// Filesystem-safe key derived from a free-typed language name (e.g.
/// "Vietnamese", "베트남어", "Español") — lowercased, whitespace and
/// filesystem-reserved characters collapsed to underscores, otherwise left
/// as-is. Unicode letters are deliberately preserved rather than
/// transliterated/hashed away: this app already writes literal Unicode
/// filenames today (see `HandoffService`'s `handoff_<language>.json`), and
/// collapsing e.g. "베트남어" and "日本語" down to the same ASCII-only
/// placeholder would silently merge two different languages' data.
///
/// Used to key per-language storage folders (`audio_cache/<key>/`,
/// `review_history/<key>/`, `conversation_history/<key>/`) so that a
/// learner's data for one target language never mixes with another's.
String languageStorageKey(String language) {
  final trimmed = language.trim();
  if (trimmed.isEmpty) return 'unknown';
  final sanitized = trimmed.toLowerCase().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}
