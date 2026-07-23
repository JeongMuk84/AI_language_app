import 'gemini_message.dart';

/// 한 target language에서의 학습자 진행 상황 스냅샷. 그 언어에서 벗어날(다른
/// 언어로 전환할) 때 Gemini에 넘겨 handoff summary를 생성하는 데 쓰인다.
///
/// 아직 제대로 된 학습 화면/로그 체계가 없어서, 현재는 난이도와 그때까지의
/// 로컬 대화 기록 정도만 담고 있다. [conversationHistory]는 의도적으로 남겨둔
/// 확장 지점이다 — 나중에 실제 학습 세션 로그(수행한 exercise, 틀린 부분,
/// 다룬 단어 등)가 생기면, `GeminiService`의 프롬프트 생성 코드를 그 자리에서
/// 계속 불리는 대신 이 클래스에 필드를 추가하는 방향으로 확장해야 한다.
class LearningSessionSnapshot {
  /// [nativeLanguage]/[targetLanguage]는 학습자의 모국어/학습 대상 언어,
  /// [difficultyLevel]은 현재 난이도, [conversationHistory]는 지금까지의
  /// 로컬 Gemini 대화 기록이다. `SettingsViewModel.save`가 target language를
  /// 전환하기 직전, 이전 언어에 대한 이 값을 만들어
  /// `GeminiService.generateHandoffSummary`에 넘긴다.
  const LearningSessionSnapshot({
    required this.nativeLanguage,
    required this.targetLanguage,
    this.difficultyLevel,
    this.conversationHistory = const [],
  });

  /// 학습자의 모국어.
  final String nativeLanguage;

  /// 요약을 생성할 대상(곧 떠나게 될) target language.
  final String targetLanguage;

  /// 현재 난이도 설정.
  final String? difficultyLevel;

  /// `ConversationSessionViewModel.history`에서 읽어온, 지금까지의 로컬
  /// Gemini 대화 기록. `GeminiService.generateHandoffSummary`가 이 기록을
  /// 요약 프롬프트에 포함시켜 handoff 문장을 생성한다.
  final List<GeminiMessage> conversationHistory;
}
