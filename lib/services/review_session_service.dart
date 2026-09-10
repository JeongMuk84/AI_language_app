import 'dart:math';

import '../constants/learning_constants.dart';
import '../models/review_item.dart';
import '../models/review_record.dart';
import 'config_service.dart';
import 'review_history_service.dart';
import 'tts_cache_service.dart';

/// Number of the most-recently-*first-learned* sentences that are always
/// included in a review set when the pool is larger than the target size —
/// i.e. "yesterday's batch" (`kDailyTurnLimit` sentences a day). The rest of
/// the target size is filled at random from the remainder.
/// (풀이 목표 개수보다 클 때, "처음 학습한" 시점이 가장 최근인 순으로
/// 무조건 포함시키는 문장 개수 — 사실상 "어제 배운 한 묶음"
/// ([kDailyTurnLimit]문장/일)이다. 목표 개수의 나머지는 그 외 문장들에서
/// 무작위로 채운다.)
const int kYesterdayLearnedCount = kDailyTurnLimit;

/// How many EXTRA review sentences to append today for a given live TTS
/// cache count, on top of the usual `dailyReviewCount` set.
///
/// Zero until the cache reaches [kReviewRampUpThreshold]; above it, grows
/// linearly with the overshoot ([kReviewRampUpSlope] per cached sentence
/// over the threshold) so it ramps gently near the threshold and harder as
/// the cache nears its [kTtsCacheMaxEntries] cap. No upper clamp — the LRU
/// cap bounds the cache, so this is bounded in practice at
/// `(kTtsCacheMaxEntries - kReviewRampUpThreshold) * kReviewRampUpSlope`.
/// The whole point is to deliberately drain a nearly-full cache by
/// reviewing its most-worn sentences up to [kReviewRetireThreshold] (which
/// deletes them); once enough drain out and the count drops back below the
/// threshold this returns 0 again, so daily volume rises and falls on its
/// own with the cache.
/// (`buildReviewSet`이 평소 세트에 덧붙일 추가 문장 수. 캐시가
/// [kReviewRampUpThreshold] 미만이면 0, 이상이면 초과분에 선형 비례.)
int rampUpExtraCount(int cacheCount) {
  if (cacheCount < kReviewRampUpThreshold) return 0;
  return (cacheCount - kReviewRampUpThreshold) * kReviewRampUpSlope;
}

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

  /// Builds today's review set. Base target size is the CURRENT config's
  /// `dailyReviewCount` (`AppConfig.effectiveDailyReviewCount`, default
  /// [kDefaultDailyReviewCount]); when the live per-language TTS cache count
  /// is at/above [kReviewRampUpThreshold], [rampUpExtraCount] more are
  /// appended (see below).
  ///
  /// The pool is every reviewable sentence — one that (a) still has cached
  /// TTS audio and (b) hasn't yet been reviewed [kReviewRetireThreshold]
  /// times (a sentence that reached that count is deleted from the cache
  /// and history by `ReviewViewModel.advance`; this `< kReviewRetireThreshold`
  /// filter is just belt-and-suspenders for a record that slipped through).
  ///
  /// Normal selection from that pool ([_selectNormal]):
  /// - Pool <= target: every reviewable sentence.
  /// - target <= [kYesterdayLearnedCount]: no random fill — just the
  ///   `target` most-recently-*first-learned* sentences.
  /// - Pool > target > [kYesterdayLearnedCount]: the
  ///   [kYesterdayLearnedCount] most recently *first learned* (not most
  ///   recently reviewed — this surfaces what was just learned) + the
  ///   remaining `target - kYesterdayLearnedCount` picked at random from
  ///   the rest, weighted toward sentences that haven't been reviewed in a
  ///   while (or ever).
  ///
  /// Ramp-up (cache >= [kReviewRampUpThreshold]): after normal selection,
  /// [rampUpExtraCount] more are taken from the still-unselected pool,
  /// ordered by MOST-reviewed first (closest to [kReviewRetireThreshold]),
  /// ties broken by oldest `firstLearnedAt` — i.e. the sentences most
  /// likely to be retired soon, so powering through the set actively drains
  /// the cache. These extras run through the exact same review flow; they're
  /// just mixed into the set. Below the threshold nothing extra is added and
  /// the set is the plain `dailyReviewCount` size again.
  ///
  /// Returns an empty list if there's nothing reviewable — the caller
  /// should skip straight to a new learning session in that case.
  /// (오늘의 review set을 만든다. 기본 목표 개수는 현재 config의
  /// `dailyReviewCount`이며, 언어별 TTS 캐시 개수가 [kReviewRampUpThreshold]
  /// 이상이면 [rampUpExtraCount]만큼 문장을 더 덧붙인다 — 추가분은 아직
  /// 뽑히지 않은 풀에서 "복습을 많이 한(7회에 가까운) 순, 동률이면 오래된
  /// 순"으로 골라, 곧 삭제될 문장을 밀어 캐시를 실제로 소진시킨다. 캐시가
  /// 다시 임계 밑으로 내려가면 자동으로 평소 크기로 돌아온다.)
  ///
  /// `app_router.dart`가 라우팅 리다이렉트 판단에서 "복습할 게 있는지"를
  /// 확인할 때, `ReviewViewModel`이 복습 화면에서 실제로 보여줄 문항 목록을
  /// 준비할 때 호출한다.
  /// 반환값: 이번 복습 세션에서 다룰 [ReviewItem] 목록(비어있을 수 있음).
  Future<List<ReviewItem>> buildReviewSet() async {
    final config = await _configService.readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final baseTarget = config.effectiveDailyReviewCount;
    final allRecords = await _reviewHistoryService.readAll();

    final reviewable = <_PoolEntry>[];
    for (final record in allRecords) {
      if (record.reviewCount >= kReviewRetireThreshold) continue;
      final location = await _ttsCacheService.peek(
        sentence: record.sentenceInTarget,
        language: targetLanguage,
      );
      if (location != null) {
        reviewable.add(_PoolEntry(record, location));
      }
    }

    if (reviewable.isEmpty) return const [];

    final normal = _selectNormal(reviewable, baseTarget);

    // 램프업: 이 언어 캐시가 거의 가득 차면, 복습을 가장 많이 한(reviewCount가
    // 높은) 오래된 문장을 일부러 더 얹어 캐시를 다시 끌어내린다. 매 빌드마다
    // 실시간 개수를 읽으므로, 별도 모드 플래그 없이 하루 복습량이 캐시를 따라
    // 늘었다 줄었다 한다.
    final cacheCount = await _ttsCacheService.count();
    final extraCount = rampUpExtraCount(cacheCount);
    final extras = <_PoolEntry>[];
    if (extraCount > 0) {
      final chosen = normal.map((e) => e.record.sentenceInTarget).toSet();
      final rest = reviewable
          .where((e) => !chosen.contains(e.record.sentenceInTarget))
          .toList()
        ..sort((a, b) {
          final byWear = b.record.reviewCount.compareTo(a.record.reviewCount);
          if (byWear != 0) return byWear;
          return a.record.firstLearnedAt.compareTo(b.record.firstLearnedAt);
        });
      extras.addAll(rest.take(extraCount));
    }

    final selected = [...normal, ...extras]..shuffle(_random);
    return selected.map((e) => e.toItem()).toList();
  }

  /// 램프업을 뺀 평소 선정 로직. [reviewable] 풀에서 최대 [targetSize]개를
  /// 고른다 — 세 갈래 경우는 [buildReviewSet] 문서 참고. 뽑힌 [_PoolEntry]
  /// 목록을 (섞지 않은 채로) 돌려주며, 최종 결합된 세트를 섞는 것은 호출자
  /// 몫이다.
  List<_PoolEntry> _selectNormal(List<_PoolEntry> reviewable, int targetSize) {
    if (reviewable.length <= targetSize) return [...reviewable];

    final byRecency = [...reviewable]
      ..sort((a, b) => b.record.firstLearnedAt.compareTo(a.record.firstLearnedAt));

    // 목표가 작아서 "어제 배운 묶음"만으로 채워지는 경우 — 가장 최근에
    // 학습한 순으로 그만큼만 뽑고, 가중 무작위 채움은 하지 않는다.
    if (targetSize <= kYesterdayLearnedCount) {
      return byRecency.take(targetSize).toList();
    }

    final recent = byRecency.take(kYesterdayLearnedCount).toList();
    final remainder = byRecency.skip(kYesterdayLearnedCount).toList();
    final randomCount = targetSize - kYesterdayLearnedCount;

    final now = DateTime.now();
    final weights = remainder
        .map(
          (e) => (now.difference(e.record.lastReviewedAt ?? DateTime.utc(2000)).inHours + 1)
              .toDouble(),
        )
        .toList();
    final randomPicks = _weightedSampleWithoutReplacement(remainder, weights, randomCount);

    return [...recent, ...randomPicks];
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
  /// 반환값: 대상/모국어 문장, 캐시된 오디오 경로, 사용된 음성, 그리고
  /// 지금까지의 누적 복습 횟수를 담은 [ReviewItem].
  ReviewItem toItem() => ReviewItem(
        sentenceInTarget: record.sentenceInTarget,
        sentenceInNative: record.sentenceInNative,
        cachedAudioPath: location.path,
        voiceUsed: location.voice,
        reviewCount: record.reviewCount,
      );
}
