/// 핵심 학습 루프를 이루는 두 가지 exercise 유형을 나타내는 enum. `SessionState`,
/// `ConversationTurn`, `HistorySummary` 등 세션/기록 관련 모델 전반에서 현재
/// 어느 exercise를 진행 중인지 표시하는 데 쓰이며, `ShadowingViewModel`/
/// `WritingViewModel`이 각각 대응하는 화면 흐름을 담당한다.
enum ExerciseType {
  /// 원어민 음성을 듣고 따라 말하는(shadowing) exercise.
  shadowing,

  /// 모국어 문장을 target language로 번역해 쓰는(writing) exercise.
  writing;

  /// 저장된 문자열 값을 [ExerciseType]으로 변환한다. `'writing'`이 아니면
  /// 항상 [shadowing]으로 취급한다(값이 없거나 손상된 세션/히스토리 파일에
  /// 대한 안전한 기본값). `SessionState.fromJson` 등 각 모델의 `fromJson`이
  /// 사용한다.
  static ExerciseType fromValue(String? value) {
    return value == 'writing' ? ExerciseType.writing : ExerciseType.shadowing;
  }

  /// JSON 직렬화에 쓰이는 문자열 값(enum 이름 그대로). 각 모델의 `toJson`이
  /// 사용한다.
  String get value => name;

  /// 현재 값의 반대쪽 exercise type을 반환한다. shadowing과 writing이 한
  /// 턴이 끝날 때마다 서로 번갈아 진행되는데, `app_router.dart`가 세션을
  /// 재개할 때 마지막으로 완료한 type을 기준으로 다음에 시작할 exercise
  /// type을 정할 때 이 getter로 전환한다.
  ExerciseType get other =>
      this == ExerciseType.shadowing ? ExerciseType.writing : ExerciseType.shadowing;
}
