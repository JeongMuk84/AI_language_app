/// 앱 문서 디렉토리의 `config.json`에 저장되는 로컬 앱 설정을 나타내는 모델.
/// Gemini API 키는 여기 포함되지 않으며, 그 값은 `ApiKeyStorageService`를 통해
/// `flutter_secure_storage`에 별도로 보관된다. `ConfigService.readConfig`가
/// `config.json`을 파싱해 이 객체를 만들고, `ConfigService.writeConfig`/
/// `updateConfig`가 이 객체를 다시 JSON으로 직렬화해 저장한다.
/// `SettingsViewModel`과 `SettingsDialog` 화면이 언어/난이도/테마 설정을 읽고
/// 쓸 때 이 모델을 사용한다.
class AppConfig {
  /// 각 필드는 아직 설정되지 않았을 수 있어 모두 nullable이다(예: 첫 실행 시
  /// 언어를 아직 고르지 않은 상태). [nativeLanguage]는 학습자의 모국어,
  /// [targetLanguage]는 학습 대상 언어, [difficultyLevel]은 CEFR 등 난이도
  /// 표기, [themeMode]는 저장된 테마 원본 값이다.
  const AppConfig({
    this.nativeLanguage,
    this.targetLanguage,
    this.difficultyLevel,
    this.themeMode,
  });

  /// `config.json`의 내용을 파싱해 [AppConfig]를 만든다.
  /// `ConfigService.readConfig`가 파일을 읽은 뒤 이 팩토리로 객체를 생성한다.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      nativeLanguage: json['nativeLanguage'] as String?,
      targetLanguage: json['targetLanguage'] as String?,
      difficultyLevel: json['difficultyLevel']?.toString(),
      themeMode: json['themeMode'] as String?,
    );
  }

  /// 학습자의 모국어. 예: 'ko'. 설정 화면에서 선택되어 저장된다.
  final String? nativeLanguage;

  /// 학습 대상 언어. 예: 'vi'. `app_router.dart`가 [hasLanguages]와 함께
  /// 온보딩 완료 여부를 판단하는 데 사용한다.
  final String? targetLanguage;

  /// 학습 난이도(CEFR 레벨 등 문자열 표기). 레벨 테스트 결과로 설정되거나
  /// 사용자가 직접 고를 수 있다.
  final String? difficultyLevel;

  /// 저장된 원본 테마 값: `'white'` 또는 `'black'`. 기본값이 적용된 값을
  /// 읽으려면 [effectiveThemeMode]를 사용할 것 — 이 필드가 아직 없는(기존
  /// 사용자의) 설정 파일이면 `'black'`으로 취급된다.
  final String? themeMode;

  /// [nativeLanguage]와 [targetLanguage]가 모두 채워져 있는지 나타낸다.
  /// `app_router.dart`의 리다이렉트 로직이 이 값으로 온보딩(언어 설정) 화면과
  /// 메인 화면 중 어디로 보낼지 게이팅한다.
  bool get hasLanguages =>
      (nativeLanguage?.isNotEmpty ?? false) && (targetLanguage?.isNotEmpty ?? false);

  /// [difficultyLevel]이 설정되어 있는지 나타낸다.
  bool get hasDifficultyLevel => difficultyLevel?.isNotEmpty ?? false;

  /// [themeMode]에 기본값(`'black'`)을 적용해 실제로 사용할 테마 값을
  /// 계산한다. `ThemeModeViewModel`과 `SettingsDialog`의 초기 상태 계산에
  /// 쓰인다.
  String get effectiveThemeMode => themeMode == 'white' ? 'white' : 'black';

  /// `config.json`에 저장할 JSON 맵으로 직렬화한다. `ConfigService.writeConfig`
  /// 가 이 값을 파일에 쓴다. null인 필드는 아예 키를 생략한다.
  Map<String, dynamic> toJson() => {
        if (nativeLanguage != null) 'nativeLanguage': nativeLanguage,
        if (targetLanguage != null) 'targetLanguage': targetLanguage,
        if (difficultyLevel != null) 'difficultyLevel': difficultyLevel,
        if (themeMode != null) 'themeMode': themeMode,
      };

  /// 일부 필드만 바꾼 새 [AppConfig]를 만드는 불변(immutable) 갱신 메서드.
  /// `SettingsViewModel.save`가 `configService.updateConfig`에 넘기는
  /// 콜백 안에서 기존 설정을 기반으로 언어/난이도만 바꿀 때 쓰인다.
  /// [clearDifficultyLevel]을 true로 주면 난이도 값을 명시적으로 지울 수
  /// 있다(단순히 null을 넘기면 "값 유지"로 해석되므로 별도 플래그가 필요).
  AppConfig copyWith({
    String? nativeLanguage,
    String? targetLanguage,
    String? difficultyLevel,
    bool clearDifficultyLevel = false,
    String? themeMode,
  }) {
    return AppConfig(
      nativeLanguage: nativeLanguage ?? this.nativeLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      difficultyLevel: clearDifficultyLevel ? null : (difficultyLevel ?? this.difficultyLevel),
      themeMode: themeMode ?? this.themeMode,
    );
  }
}
