import 'pregenerated_sentence.dart';

/// 하루치 학습 문장 10개(쉐도잉 5 + 작문 5)를 한 번의 `generateDailySentenceSet`
/// 호출로 미리 만들어 저장해두는 모델. `SessionStateService.readSentenceQueue`/
/// `writeSentenceQueue`가 `sentence_queue.json`으로 읽고 쓴다.
///
/// [sentences]의 인덱스는 그날의 `dailyTurnCount`와 1:1로 대응한다 —
/// 즉 `sentences[dailyTurnCount]`가 다음에 진행할 turn의 문장이다
/// (`dailyTurnCount`는 오늘 완료된 turn 수이므로, 아직 완료되지 않은 다음
/// turn을 정확히 가리킨다). [ExerciseType.shadowing]/[ExerciseType.writing]이
/// 번갈아 나오는 순서(쉐도잉1-작문1-쉐도잉2-작문2...)로 채워져 있다고
/// 가정하지만, 실제 타입 판별은 항상 해당 인덱스 항목의 [PregeneratedSentence.type]
/// 을 그대로 신뢰한다.
class SentenceQueue {
  /// [generatedAt]은 이 세트가 만들어진 시각(같은 태평양 날짜인지 판정하는
  /// 데 쓰임), [sentences]는 순서대로 꺼내 쓸 문장 목록이다.
  const SentenceQueue({required this.generatedAt, required this.sentences});

  /// 저장된 `sentence_queue.json` 내용을 파싱해 [SentenceQueue]를 만든다.
  /// `SessionStateService.readSentenceQueue`가 사용한다.
  factory SentenceQueue.fromJson(Map<String, dynamic> json) {
    return SentenceQueue(
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      sentences: (json['sentences'] as List? ?? const [])
          .map((e) => PregeneratedSentence.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 이 세트가 생성된 시각 — `DayBoundaryService`로 오늘과 같은 태평양
  /// 날짜인지 판정해, 날짜가 바뀌면 낡은 세트로 취급하고 폐기하는 데 쓰인다.
  final DateTime generatedAt;

  /// 순서대로 꺼내 쓸 문장 목록(정상적으로는 10개).
  final List<PregeneratedSentence> sentences;

  /// [index]번째 문장을 반환한다. 범위를 벗어나면(세트가 소진되었거나
  /// 손상된 경우) `null` — 호출부는 이 경우 문장을 즉석에서 새로 생성하는
  /// 예전 방식으로 안전하게 폴백해야 한다.
  PregeneratedSentence? itemAt(int index) {
    if (index < 0 || index >= sentences.length) return null;
    return sentences[index];
  }

  /// [SentenceQueue]를 `sentence_queue.json`에 저장할 JSON 맵으로
  /// 직렬화한다. `SessionStateService.writeSentenceQueue`가 사용한다.
  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt.toIso8601String(),
    'sentences': sentences.map((e) => e.toJson()).toList(),
  };
}
