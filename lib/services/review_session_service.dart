import 'dart:math';

import '../models/review_item.dart';
import '../models/review_record.dart';
import 'config_service.dart';
import 'review_history_service.dart';
import 'tts_cache_service.dart';

/// Max sentences in a single review set. Below this, every reviewable
/// sentence (one with cached audio) is included; above it, a mix of
/// recently-learned and overdue-for-review sentences is selected instead
/// (see `buildReviewSet`).
/// (한 번의 review set에 들어가는 최대 문장 수. 이 값 이하이면 복습 가능한
/// (캐시된 오디오가 있는) 모든 문장이 포함되고, 이보다 많으면 최근 학습한
/// 문장과 복습이 밀린 문장을 섞어서 선택한다([buildReviewSet] 참고).)
const int kMaxReviewSetSize = 15;
/// [ReviewSessionService.buildReviewSet]에서 풀이 [kMaxReviewSetSize]를
/// 초과할 때, 최근에 처음 학습한 순으로 무조건 포함시키는 문장 개수.
const int _recentCount = 10;
/// [_recentCount]를 채운 나머지를, 복습이 밀린 정도에 가중치를 둔 무작위
/// 추출로 채우는 개수(`kMaxReviewSetSize - _recentCount`).
const int _randomCount = kMaxReviewSetSize - _recentCount;

/// Picks which sentences to review, from the durable learning record in
/// `ReviewHistoryService` — filtered to only ones the TTS cache still has
/// audio for, since a sentence with no cached audio can't be replayed
/// without spending a fresh (quota-limited) TTS call, which review must
/// never do.
/// (`ReviewHistoryService`의 영구 학습 기록으로부터 복습할 문장을 골라낸다
/// — TTS 캐시에 아직 오디오가 남아있는 문장으로만 필터링하는데, 캐시된
/// 오디오가 없는 문장은 새로 TTS 호출(quota가 제한된 자원)을 써야만 다시
/// 재생할 수 있고, 복습 기능은 절대 그렇게 해서는 안 되기 때문이다.)
///
/// `reviewSessionServiceProvider`(`service_providers.dart`)를 통해
/// 노출되며, `app_router.dart`가 라우팅 시 "오늘 복습할 게 있는지" 판단할
/// 때, `ReviewViewModel`이 복습 화면 진입 시 실제 표시할 문항 목록을 얻을
/// 때 각각 `buildReviewSet()`을 호출한다.
class ReviewSessionService {
  /// 필요한 하위 서비스들을 주입받아 생성한다(테스트에서 모킹 가능하도록).
  /// 모두 생략하면 각각 기본 구현을 새로 만들어 사용한다.
  ReviewSessionService({
    ReviewHistoryService? reviewHistoryService,
    TtsCacheService? ttsCacheService,
    ConfigService? configService,
  }) : _reviewHistoryService = reviewHistoryService ?? ReviewHistoryService(),
       _ttsCacheService = ttsCacheService ?? TtsCacheService(),
       _configService = configService ?? ConfigService();

  final ReviewHistoryService _reviewHistoryService;
  final TtsCacheService _ttsCacheService;
  final ConfigService _configService;

  final Random _random = Random();

  /// Builds today's review set:
  /// - Pool <= [kMaxReviewSetSize]: every reviewable sentence.
  /// - Pool > [kMaxReviewSetSize]: the [_recentCount] most recently
  ///   *first learned* (not most recently reviewed — this surfaces what
  ///   was just learned, not what was just reviewed) + [_randomCount]
  ///   more picked at random from the rest, weighted toward sentences that
  ///   haven't been reviewed in a while (or ever).
  /// Returns an empty list if there's nothing reviewable — the caller
  /// should skip straight to a new learning session in that case.
  /// (오늘의 review set을 만든다:
  /// - 풀이 [kMaxReviewSetSize] 이하이면: 복습 가능한 모든 문장.
  /// - 풀이 [kMaxReviewSetSize]를 초과하면: *처음 학습한* 시점이 가장 최근인
  ///   [_recentCount]개(가장 최근에 "복습한" 것이 아니라 - 방금 새로 배운
  ///   것을 보여주기 위함) + 나머지 중에서 무작위로 뽑은 [_randomCount]개
  ///   (오랫동안 - 혹은 한 번도 - 복습되지 않은 문장에 가중치를 둠)를
  ///   합친다.
  /// 복습할 것이 없으면 빈 리스트를 반환한다 — 이 경우 호출자는 곧바로
  /// 새 학습 세션으로 넘어가야 한다.)
  ///
  /// `app_router.dart`가 라우팅 리다이렉트 판단에서 "복습할 게 있는지"를
  /// 확인할 때, `ReviewViewModel`이 복습 화면에서 실제로 보여줄 문항 목록을
  /// 준비할 때 호출한다.
  /// 반환값: 이번 복습 세션에서 다룰 [ReviewItem] 목록(비어있을 수 있음).
  Future<List<ReviewItem>> buildReviewSet() async {
    final config = await _configService.readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final allRecords = await _reviewHistoryService.readAll();

    final reviewable = <_PoolEntry>[];
    for (final record in allRecords) {
      final location = await _ttsCacheService.peek(
        sentence: record.sentenceInTarget,
        language: targetLanguage,
      );
      if (location != null) {
        reviewable.add(_PoolEntry(record, location));
      }
    }

    if (reviewable.isEmpty) return const [];
    if (reviewable.length <= kMaxReviewSetSize) {
      return reviewable.map((e) => e.toItem()).toList();
    }

    final byRecency = [...reviewable]
      ..sort((a, b) => b.record.firstLearnedAt.compareTo(a.record.firstLearnedAt));
    final recent = byRecency.take(_recentCount).toList();
    final remainder = byRecency.skip(_recentCount).toList();

    final now = DateTime.now();
    final weights = remainder
        .map(
          (e) => (now.difference(e.record.lastReviewedAt ?? DateTime.utc(2000)).inHours + 1)
              .toDouble(),
        )
        .toList();
    final randomPicks = _weightedSampleWithoutReplacement(remainder, weights, _randomCount);

    final selected = [...recent, ...randomPicks]..shuffle(_random);
    return selected.map((e) => e.toItem()).toList();
  }

  /// [items]에서 [weights]로 가중치를 준 무작위 비복원 추출(weighted sampling
  /// without replacement)로 [count]개를 뽑는다. 가중치가 클수록(오래
  /// 복습되지 않았을수록) 뽑힐 확률이 높아진다. [buildReviewSet]이 최근
  /// 학습분 이외의 나머지에서 무작위 추가 항목을 고를 때 호출한다.
  /// [items]: 추출 대상 항목 목록.
  /// [weights]: 각 항목에 대응하는 가중치(같은 인덱스끼리 대응).
  /// [count]: 뽑을 개수(항목 수보다 많으면 있는 만큼만 반환).
  /// 반환값: 뽑힌 [_PoolEntry] 목록.
  List<_PoolEntry> _weightedSampleWithoutReplacement(
    List<_PoolEntry> items,
    List<double> weights,
    int count,
  ) {
    final pool = List.of(items);
    final w = List.of(weights);
    final result = <_PoolEntry>[];
    while (result.length < count && pool.isNotEmpty) {
      final total = w.fold<double>(0, (sum, x) => sum + x);
      var roll = _random.nextDouble() * total;
      var index = w.length - 1;
      for (var i = 0; i < w.length; i++) {
        roll -= w[i];
        if (roll <= 0) {
          index = i;
          break;
        }
      }
      result.add(pool.removeAt(index));
      w.removeAt(index);
    }
    return result;
  }
}

/// [ReviewSessionService]가 review set을 고르는 동안 사용하는 내부 작업용
/// 쌍(pair) — 학습 기록([ReviewRecord])과 그에 대응하는 TTS 캐시 위치를
/// 함께 묶어둔다. 이 파일 밖에서는 쓰이지 않는 private 헬퍼 클래스다.
class _PoolEntry {
  /// [record]와 [location]을 묶어 항목을 만든다.
  const _PoolEntry(this.record, this.location);

  /// 이 문장의 영구 학습 기록(최초 학습 시각, 복습 횟수 등).
  final ReviewRecord record;
  /// 이 문장의 TTS 캐시 상 위치(오디오 경로, 사용된 음성).
  final TtsCacheLocation location;

  /// 이 항목을 화면/뷰모델이 사용하는 공개 모델인 [ReviewItem]으로
  /// 변환한다. [buildReviewSet]이 최종 결과 목록을 만들 때 각 항목에
  /// 호출한다.
  /// 반환값: 대상/모국어 문장, 캐시된 오디오 경로, 사용된 음성을 담은
  /// [ReviewItem].
  ReviewItem toItem() => ReviewItem(
        sentenceInTarget: record.sentenceInTarget,
        sentenceInNative: record.sentenceInNative,
        cachedAudioPath: location.path,
        voiceUsed: location.voice,
      );
}
