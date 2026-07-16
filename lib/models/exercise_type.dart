/// The two alternating halves of the core learning loop.
enum ExerciseType {
  shadowing,
  writing;

  static ExerciseType fromValue(String? value) {
    return value == 'writing' ? ExerciseType.writing : ExerciseType.shadowing;
  }

  String get value => name;

  ExerciseType get other =>
      this == ExerciseType.shadowing ? ExerciseType.writing : ExerciseType.shadowing;
}
