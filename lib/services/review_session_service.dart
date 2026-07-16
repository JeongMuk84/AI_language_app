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
const int kMaxReviewSetSize = 15;
const int _recentCount = 10;
const int _randomCount = kMaxReviewSetSize - _recentCount;

/// Picks which sentences to review, from the durable learning record in
/// `ReviewHistoryService` — filtered to only ones the TTS cache still has
/// audio for, since a sentence with no cached audio can't be replayed
/// without spending a fresh (quota-limited) TTS call, which review must
/// never do.
class ReviewSessionService {
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

class _PoolEntry {
  const _PoolEntry(this.record, this.location);

  final ReviewRecord record;
  final TtsCacheLocation location;

  ReviewItem toItem() => ReviewItem(
        sentenceInTarget: record.sentenceInTarget,
        sentenceInNative: record.sentenceInNative,
        cachedAudioPath: location.path,
        voiceUsed: location.voice,
      );
}
