/// One turn in a local multi-turn Gemini conversation. Gemini itself is
/// stateless between requests — the app resends this history on every call
/// to keep context, which is also why "resetting a session" just means
/// clearing a list of these.
class GeminiMessage {
  const GeminiMessage({required this.role, required this.text});

  /// `'user'` or `'model'`.
  final String role;
  final String text;

  factory GeminiMessage.fromJson(Map<String, dynamic> json) {
    return GeminiMessage(
      role: json['role'] as String? ?? 'user',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}
