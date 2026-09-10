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

/// 한 문장을 이만큼 복습하면(`ReviewScreen`에서 "Next Sentence"로 완료
/// 처리되어 `reviewCount`가 이 값에 도달하면) 그 문장은 "충분히 익혔다"고
/// 보고 그 즉시 TTS 캐시(오디오 파일 + manifest 항목)와 `ReviewHistoryService`
/// 레코드에서 모두 제거된다 — 이후 `buildReviewSet`의 대상 풀에도,
/// `ListeningHistoryScreen`(캐시에 남은 것만 표시)에도 다시 나타나지 않는다.
/// 이는 TTS 캐시의 LRU eviction(용량 초과 시 오래된 것부터 밀려남)과는
/// 별개인, 추가적인 명시적 삭제 경로다. `ReviewViewModel.advance`와
/// `ReviewSessionService.buildReviewSet`이 참조한다.
const int kReviewRetireThreshold = 7;

/// config.json에 `dailyReviewCount`가 없을 때 쓰는 기본값. 이 필드가 없는
/// (예: 이번 기능 이전에 만들어진) 설정 파일은 이 값으로 취급한다.
/// `AppConfig.effectiveDailyReviewCount`와 `SettingsDialog`의 기본
/// 입력값이 이 상수를 쓴다.
const int kDefaultDailyReviewCount = 20;

/// 사용자가 Settings의 "Daily Review Count"에 입력할 수 있는 최솟값.
/// 어제 배운 [kDailyTurnLimit]문장조차 채우지 못하는 모순된 값을 막기
/// 위해 [kDailyTurnLimit]과 같게 둔다. `SettingsViewModel.save`가 검증에
/// 사용한다.
const int kMinDailyReviewCount = kDailyTurnLimit;

/// 언어별 TTS 캐시가 이 개수 "이상"이 되면, 그날부터 `buildReviewSet`이
/// 평소 복습 세트 위에 "곧 지워질 만한"(복습 횟수가 높고 오래된) 문장을
/// 추가로 덧붙여 하루 복습량을 늘린다 — 쌓인 캐시를 실제로 소진(7회 채워
/// 삭제)시키기 위한 의도적 가속이다. 캐시가 다시 이 값 밑으로 내려가면
/// 자동으로 평소 모드로 복귀한다. `kTtsCacheMaxEntries`(600)보다 10 작게
/// 잡아, 상한에 닿기 전 마지막 구간에서 소진을 유도한다. `ReviewSessionService`와
/// `SettingsDialog`가 참조한다.
const int kReviewRampUpThreshold = 590;

/// [kReviewRampUpThreshold]를 넘어선 캐시 초과분 1개당 그날 추가되는 복습
/// 문장 수. 선형 비례라 590 근처에서는 소폭, 상한(600)에 가까울수록 더
/// 많이 늘어난다(예: slope 2 → 캐시 595에서 +10문장, 600에서 +20문장).
/// 소진 속도를 조절하는 튜닝 손잡이다 — `rampUpExtraCount` 참고.
const int kReviewRampUpSlope = 2;

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
