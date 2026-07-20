import '../models/review_record.dart';
import 'config_service.dart';
import 'review_history_service.dart';
import 'tts_cache_service.dart';

/// Max entries surfaced by [ListeningHistoryService.buildHistory]. Matches
/// `TtsCacheService`'s own cap ([TtsCacheService] evicts LRU past 100
/// entries), so this is really just documenting an existing ceiling rather
/// than imposing a new one.
const int kMaxListeningHistorySize = 100;

/// Builds the "Listening History" list — every previously-learned sentence
/// (from the durable record in [ReviewHistoryService]) that the TTS cache
/// still has audio for, newest-first. Composes existing services rather
/// than introducing new persisted storage, mirroring how
/// `ReviewSessionService` builds its own filtered/sorted view over the same
/// underlying data.
class ListeningHistoryService {
  ListeningHistoryService({
    ReviewHistoryService? reviewHistoryService,
    TtsCacheService? ttsCacheService,
    ConfigService? configService,
  }) : _reviewHistoryService = reviewHistoryService ?? ReviewHistoryService(),
       _ttsCacheService = ttsCacheService ?? TtsCacheService(),
       _configService = configService ?? ConfigService();

  final ReviewHistoryService _reviewHistoryService;
  final TtsCacheService _ttsCacheService;
  final ConfigService _configService;

  /// Sentences with cached audio, ordered by [ReviewRecord.firstLearnedAt]
  /// descending (most recently learned first), capped at
  /// [kMaxListeningHistorySize]. A sentence whose cached clip has since been
  /// evicted is excluded rather than shown with a broken play button — same
  /// principle `ReviewSessionService.buildReviewSet` uses for review
  /// selection.
  Future<List<ReviewRecord>> buildHistory() async {
    final config = await _configService.readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final allRecords = await _reviewHistoryService.readAll();

    final playable = <ReviewRecord>[];
    for (final record in allRecords) {
      final location = await _ttsCacheService.peek(
        sentence: record.sentenceInTarget,
        language: targetLanguage,
      );
      if (location != null) playable.add(record);
    }

    playable.sort((a, b) => b.firstLearnedAt.compareTo(a.firstLearnedAt));
    return playable.take(kMaxListeningHistorySize).toList();
  }
}
