/// 빌드 시점에 `--dart-define`으로 주입되는 두 컴파일 타임 상수
/// (`TRIAL_MODE`, `TRIAL_EXPIRY`)를 근거로, 평가판(trial) 빌드가
/// 만료됐는지 판단하는 서비스. 이 값들은 컴파일 타임 상수이므로 앱을
/// 아무리 재설치하거나 config.json/secure storage를 초기화해도(Settings의
/// "Reset All Data" 포함) 절대 바뀌지 않는다 — `main()`이 정상적인
/// 라우팅/온보딩 로직을 실행하기도 전에 가장 먼저 [isExpired]를 확인하며,
/// 만료됐다면 그 어떤 화면(Settings 포함)도 거치지 않고
/// `TrialExpiredScreen`만 표시한다.
class TrialGateService {
  /// `--dart-define=TRIAL_MODE=true`로 빌드했는지 여부. false(기본값)이면
  /// 일반 버전이며 [isExpired]는 항상 false를 반환한다.
  static const bool isTrialMode = bool.fromEnvironment('TRIAL_MODE');

  /// `--dart-define=TRIAL_EXPIRY=YYYY-MM-DD`로 주입되는 만료일 원본
  /// 문자열. 지정하지 않으면 빈 문자열이며, 이 경우 [isExpired]는 안전하게
  /// false를 반환한다(평가판 모드로 빌드했는데 만료일을 깜빡 지정하지
  /// 않은 잘못된 빌드가 즉시 앱을 막아버리는 사고를 방지하기 위함).
  /// SettingsDialog가 "Trial version — expires ..." 문구를 표시할 때도 이
  /// 값을 그대로 쓴다.
  static const String trialExpiryRaw = String.fromEnvironment('TRIAL_EXPIRY');

  /// [trialExpiryRaw]를 파싱한 날짜. 형식이 잘못됐거나 비어 있으면 `null`.
  static DateTime? get trialExpiryDate => DateTime.tryParse(trialExpiryRaw);

  /// 지금 이 순간 평가판이 만료됐는지 판단한다. `main()`이 timezone
  /// 초기화나 storage 마이그레이션 등 다른 어떤 것도 하기 전에 가장 먼저
  /// 호출해, 만료됐다면 곧바로 `TrialExpiredScreen`만 띄우고 반환한다.
  /// 반환값: [isTrialMode]가 false이거나 [trialExpiryRaw]가 비어있거나
  /// 파싱할 수 없으면 `false`. 그 외에는 기기의 오늘 날짜(시각은 무시하고
  /// 달력 날짜만 비교)가 만료일을 지났으면 `true`.
  bool isExpired() {
    if (!isTrialMode) return false;
    final expiry = trialExpiryDate;
    if (expiry == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDateOnly = DateTime(expiry.year, expiry.month, expiry.day);
    return today.isAfter(expiryDateOnly);
  }
}
