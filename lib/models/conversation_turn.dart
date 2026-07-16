import 'exercise_type.dart';

/// One completed sentence turn (a shadowing or writing exercise) in the
/// running session conversation history.
class ConversationTurn {
  const ConversationTurn({
    required this.turnId,
    required this.type,
    required this.timestamp,
    this.sentenceInTarget,
    this.sentenceInNative,
    this.userAnswer,
    this.completedSentence,
    this.isCorrect,
    this.pronunciationScore,
  });

  factory ConversationTurn.fromJson(Map<String, dynamic> json) {
    return ConversationTurn(
      turnId: json['turnId'] as String,
      type: ExerciseType.fromValue(json['type'] as String?),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sentenceInTarget: json['sentenceInTarget'] as String?,
      sentenceInNative: json['sentenceInNative'] as String?,
      userAnswer: json['userAnswer'] as String?,
      completedSentence: json['completedSentence'] as String?,
      isCorrect: json['isCorrect'] as bool?,
      pronunciationScore: (json['pronunciationScore'] as num?)?.toDouble(),
    );
  }

  final String turnId;
  final ExerciseType type;
  final DateTime timestamp;
  final String? sentenceInTarget;
  final String? sentenceInNative;
  final String? userAnswer;

  /// Writing turns only: [userAnswer] with any native-language segments
  /// replaced by their target-language equivalent (see
  /// `TranslationResult.completedSentence`) — the sentence actually
  /// displayed/spoken/graded on WritingListeningScreen, kept here for
  /// future conversation-context and review-selection use.
  final String? completedSentence;
  final bool? isCorrect;

  /// 0-100.
  final double? pronunciationScore;

  Map<String, dynamic> toJson() => {
        'turnId': turnId,
        'type': type.value,
        'timestamp': timestamp.toIso8601String(),
        if (sentenceInTarget != null) 'sentenceInTarget': sentenceInTarget,
        if (sentenceInNative != null) 'sentenceInNative': sentenceInNative,
        if (userAnswer != null) 'userAnswer': userAnswer,
        if (completedSentence != null) 'completedSentence': completedSentence,
        if (isCorrect != null) 'isCorrect': isCorrect,
        if (pronunciationScore != null) 'pronunciationScore': pronunciationScore,
      };

  ConversationTurn copyWith({
    String? userAnswer,
    bool? isCorrect,
    double? pronunciationScore,
    DateTime? timestamp,
  }) {
    return ConversationTurn(
      turnId: turnId,
      type: type,
      timestamp: timestamp ?? this.timestamp,
      sentenceInTarget: sentenceInTarget,
      sentenceInNative: sentenceInNative,
      userAnswer: userAnswer ?? this.userAnswer,
      completedSentence: completedSentence,
      isCorrect: isCorrect ?? this.isCorrect,
      pronunciationScore: pronunciationScore ?? this.pronunciationScore,
    );
  }
}
