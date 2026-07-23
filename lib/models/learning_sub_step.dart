/// 현재 `ExerciseType` 쌍(shadowing 또는 writing) 안에서 학습자가 두 화면 중
/// 어느 쪽에 있는지를 나타내는 enum — 세션을 재개할 때 올바른 exercise 쌍뿐
/// 아니라 정확히 떠났던 그 화면으로 돌아가기 위해 `ExerciseType`과 함께
/// 필요하다. `SessionState.currentSubStep`으로 저장되며, `app_router.dart`가
/// 세션 재개 시 어느 화면으로 라우팅할지 이 값으로 판단한다.
///
/// [first] = ShadowingDictationScreen(shadowing) / WritingScreen(writing)
/// [second] = ShadowingPronunciationScreen(shadowing) / WritingListeningScreen(writing)
enum LearningSubStep {
  /// 각 exercise 쌍의 첫 번째 화면(받아쓰기 / 번역 작성).
  first,

  /// 각 exercise 쌍의 두 번째 화면(발음 연습 / 듣기).
  second;

  /// 저장된 문자열 값을 [LearningSubStep]으로 변환한다. `'second'`가
  /// 아니면 항상 [first]로 취급한다 — 이 필드가 없던 예전 세션 파일도
  /// 새 문장을 시작하는 것과 동일하게 [first]로 안전하게 처리된다.
  /// `SessionState.fromJson`이 사용한다.
  static LearningSubStep fromValue(String? value) {
    return value == 'second' ? LearningSubStep.second : LearningSubStep.first;
  }

  /// JSON 직렬화에 쓰이는 문자열 값. `SessionState.toJson`이 사용한다.
  String get value => name;
}
