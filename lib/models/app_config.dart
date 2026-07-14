/// Local app configuration persisted to `config.json` in the app documents
/// directory. Does NOT include the Gemini API key — that lives in
/// `flutter_secure_storage` via `ApiKeyStorageService`.
class AppConfig {
  const AppConfig({
    this.nativeLanguage,
    this.targetLanguage,
    this.difficultyLevel,
    this.themeMode,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      nativeLanguage: json['nativeLanguage'] as String?,
      targetLanguage: json['targetLanguage'] as String?,
      difficultyLevel: json['difficultyLevel']?.toString(),
      themeMode: json['themeMode'] as String?,
    );
  }

  final String? nativeLanguage;
  final String? targetLanguage;
  final String? difficultyLevel;

  /// Raw stored value: `'white'` or `'black'`. Use [effectiveThemeMode] to
  /// read this with the default applied — new users (no field yet) get
  /// `'black'`.
  final String? themeMode;

  bool get hasLanguages =>
      (nativeLanguage?.isNotEmpty ?? false) && (targetLanguage?.isNotEmpty ?? false);

  bool get hasDifficultyLevel => difficultyLevel?.isNotEmpty ?? false;

  String get effectiveThemeMode => themeMode == 'white' ? 'white' : 'black';

  Map<String, dynamic> toJson() => {
        if (nativeLanguage != null) 'nativeLanguage': nativeLanguage,
        if (targetLanguage != null) 'targetLanguage': targetLanguage,
        if (difficultyLevel != null) 'difficultyLevel': difficultyLevel,
        if (themeMode != null) 'themeMode': themeMode,
      };

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
