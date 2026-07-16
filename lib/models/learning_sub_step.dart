/// Which of the two screens within the current `ExerciseType` pair the
/// learner is on — needed alongside `ExerciseType` to resume into the
/// exact screen they left, not just the right pair.
///
/// [first] = ShadowingDictationScreen (shadowing) / WritingScreen (writing)
/// [second] = ShadowingPronunciationScreen (shadowing) / WritingListeningScreen (writing)
enum LearningSubStep {
  first,
  second;

  static LearningSubStep fromValue(String? value) {
    return value == 'second' ? LearningSubStep.second : LearningSubStep.first;
  }

  String get value => name;
}
