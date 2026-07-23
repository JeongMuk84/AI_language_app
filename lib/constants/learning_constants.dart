/// `analyzePronunciation`이 반환하는 발음 일치율(0~100) 중, shadowing/
/// writing의 발음(pronunciation) 화면에서 "Continue" 버튼이 열리기 위해
/// 필요한 최소값. 이 값 미만이면 학습자는 다시 녹음해서 재도전해야 한다.
/// `ReviewScreen`, `ShadowingPronunciationScreen`, `WritingListeningScreen`,
/// `ReviewViewModel`이 결과의 `accuracyPercent`와 이 값을 비교해 통과
/// 여부를 판정한다.
const double kPronunciationPassThreshold = 85;

/// `GeminiService.generateNextSentence`를 호출할 때 컨텍스트로 함께
/// 보내는, 가장 최근 대화 턴(conversation turn)의 개수. 최근 컨텍스트만
/// 보내도 자연스러운 이어지는 문장을 생성하기에 충분하며, 세션 전체
/// 이력을 다 보내면 세션이 길어질수록 매 프롬프트가 커지고(느려지고
/// 비용도 늘어난다).
const int kHistoryContextWindow = 6;

/// 로컬 달력 하루(local calendar day) 동안 완료할 수 있는 최대 턴 수
/// (shadowing + writing 합산) — shadowing 5개 + writing 5개. 턴 하나당
/// 문장 하나, 문장 하나당 TTS 합성 한 번이므로, 이 상한은 Gemini 무료
/// 티어의 일일 TTS 사용량 쿼터 안에 하루 사용량을 묶어두는 역할을 한다.
/// 이 값에 도달하면 "학습 종료"를 눌렀을 때와 동일하게 세션이 자동으로
/// finalize된다. `SessionStateService`가 일일 카운트를 이 값과 비교하고,
/// `WritingViewModel`/`ShadowingViewModel`이 턴 완료 시 도달 여부를
/// 확인한다.
const int kDailyTurnLimit = 10;

/// "오늘 지금까지 완료한 턴 수"(0~[kDailyTurnLimit])를 AppBar에 표시할
/// 값으로 변환한다 — "학습자가 지금 몇 번째 턴을 진행 중인가"를
/// 1-indexed로 나타낸다(완료 0개 → "1" 표시, 즉 첫 문장이 진행 중이라는
/// 뜻). [kDailyTurnLimit]로 상한을 씌워서, 마지막 턴이 끝난 직후부터
/// 세션이 finalize되어 화면이 전환되기 전까지의 짧은 순간에 "11/10"처럼
/// 잘못된 값이 잠깐이라도 보이지 않게 한다. `WritingScreen`,
/// `WritingListeningScreen`, `ShadowingDictationScreen`,
/// `ShadowingPronunciationScreen`이 AppBar 문구를 만들 때 이 함수를
/// 호출한다.
///
/// [completedCount]는 오늘 완료한 턴 수이며, 반환값은 화면에 표시할
/// 1-indexed 턴 번호다.
int displayedDailyTurnNumber(int completedCount) {
  final current = completedCount + 1;
  return current > kDailyTurnLimit ? kDailyTurnLimit : current;
}
