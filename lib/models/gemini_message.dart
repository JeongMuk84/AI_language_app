/// 로컬에서 관리하는 multi-turn Gemini 대화의 한 턴을 나타내는 모델. Gemini API
/// 자체는 요청 사이에 상태를 기억하지 않으므로(stateless), 앱은 매 호출마다
/// 이 메시지 목록을 통째로 다시 보내 문맥을 유지한다. "세션을 리셋한다"는
/// 것도 결국 이 목록을 비우는 것과 같은 의미다.
/// `ConversationSessionViewModel`이 `history` 상태로 이 목록을 들고 있으면서
/// `addMessage`로 메시지를 추가하고, `LearningSessionSnapshot.conversationHistory`
/// 로 담겨 `GeminiService.generateHandoffSummary`에 전달된다.
class GeminiMessage {
  /// [role]은 이 메시지의 발화자, [text]는 메시지 본문이다.
  const GeminiMessage({required this.role, required this.text});

  /// `'user'`(학습자가 보낸 메시지) 또는 `'model'`(Gemini가 응답한 메시지).
  final String role;

  /// 메시지 본문 텍스트.
  final String text;

  /// 저장된 대화 기록 JSON 항목을 파싱해 [GeminiMessage]를 만든다.
  factory GeminiMessage.fromJson(Map<String, dynamic> json) {
    return GeminiMessage(
      role: json['role'] as String? ?? 'user',
      text: json['text'] as String? ?? '',
    );
  }

  /// 저장/전송용 JSON 맵으로 직렬화한다.
  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}
