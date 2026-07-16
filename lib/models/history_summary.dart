import 'conversation_turn.dart';
import 'exercise_type.dart';

/// One deduplicated turn as recorded in a day's history file.
class HistorySentenceEntry {
  const HistorySentenceEntry({
    required this.turnId,
    required this.type,
    required this.timestamp,
    this.sentenceInTarget,
    this.sentenceInNative,
    this.userAnswer,
    this.isCorrect,
    this.pronunciationScore,
  });

  factory HistorySentenceEntry.fromTurn(ConversationTurn turn) {
    return HistorySentenceEntry(
      turnId: turn.turnId,
      type: turn.type,
      timestamp: turn.timestamp,
      sentenceInTarget: turn.sentenceInTarget,
      sentenceInNative: turn.sentenceInNative,
      userAnswer: turn.userAnswer,
      isCorrect: turn.isCorrect,
      pronunciationScore: turn.pronunciationScore,
    );
  }

  factory HistorySentenceEntry.fromJson(Map<String, dynamic> json) {
    return HistorySentenceEntry(
      turnId: json['turnId'] as String,
      type: ExerciseType.fromValue(json['type'] as String?),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sentenceInTarget: json['sentenceInTarget'] as String?,
      sentenceInNative: json['sentenceInNative'] as String?,
      userAnswer: json['userAnswer'] as String?,
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
  final bool? isCorrect;
  final double? pronunciationScore;

  Map<String, dynamic> toJson() => {
        'turnId': turnId,
        'type': type.value,
        'timestamp': timestamp.toIso8601String(),
        if (sentenceInTarget != null) 'sentenceInTarget': sentenceInTarget,
        if (sentenceInNative != null) 'sentenceInNative': sentenceInNative,
        if (userAnswer != null) 'userAnswer': userAnswer,
        if (isCorrect != null) 'isCorrect': isCorrect,
        if (pronunciationScore != null) 'pronunciationScore': pronunciationScore,
      };
}

/// A finalized, deduplicated summary of one day's session(s), persisted to
/// `history/history_<yyyy-MM-dd>.json`.
class HistorySummary {
  const HistorySummary({
    required this.date,
    required this.practicedSentenceCount,
    required this.sentences,
    required this.lastExerciseType,
    this.pronunciationAccuracy,
  });

  factory HistorySummary.fromJson(Map<String, dynamic> json) {
    return HistorySummary(
      date: json['date'] as String,
      practicedSentenceCount: json['practicedSentenceCount'] as int? ?? 0,
      sentences: (json['sentences'] as List? ?? const [])
          .map((s) => HistorySentenceEntry.fromJson(s as Map<String, dynamic>))
          .toList(),
      lastExerciseType: ExerciseType.fromValue(json['lastExerciseType'] as String?),
      pronunciationAccuracy: (json['pronunciationAccuracy'] as num?)?.toDouble(),
    );
  }

  /// yyyy-MM-dd, local time.
  final String date;
  final int practicedSentenceCount;
  final List<HistorySentenceEntry> sentences;
  final ExerciseType lastExerciseType;

  /// Average pronunciation match rate (0-100) across scored turns, or null
  /// if no turn in this day had a pronunciation score.
  final double? pronunciationAccuracy;

  Map<String, dynamic> toJson() => {
        'date': date,
        'practicedSentenceCount': practicedSentenceCount,
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'lastExerciseType': lastExerciseType.value,
        if (pronunciationAccuracy != null) 'pronunciationAccuracy': pronunciationAccuracy,
      };
}
