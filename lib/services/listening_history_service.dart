import '../models/review_record.dart';
import 'config_service.dart';
import 'review_history_service.dart';
import 'tts_cache_service.dart';

/// Max entries surfaced by [ListeningHistoryService.buildHistory]. Matches
/// `TtsCacheService`'s own cap ([TtsCacheService] evicts LRU past 100
/// entries), so this is really just documenting an existing ceiling rather
/// than imposing a new one.
/// ([ListeningHistoryService.buildHistory]가 보여주는 최대 항목 수.
/// `TtsCacheService` 자체의 상한(100개를 넘으면 LRU로 evict함)과 일치하며,
/// 새로운 제약을 추가한다기보다는 이미 존재하는 상한을 그대로 문서화한
/// 값이다.)
const int kMaxListeningHistorySize = 100;

/// Builds the "Listening History" list — every previously-learned sentence
/// (from the durable record in [ReviewHistoryService]) that the TTS cache
/// still has audio for, newest-first. Composes existing services rather
/// than introducing new persisted storage, mirroring how
/// `ReviewSessionService` builds its own filtered/sorted view over the same
/// underlying data.
/// ("Listening History"(듣기 기록) 목록을 만든다 — [ReviewHistoryService]의
/// 영구 기록에 있는, 예전에 학습했던 문장들 중 TTS 캐시에 아직 오디오가
/// 남아있는 것만 최신순으로 골라낸다. 새로운 영구 저장소를 도입하는 대신
/// 기존 서비스들을 조합해서 만드는데, 이는 `ReviewSessionService`가 같은
/// 원본 데이터 위에 자신만의 필터링/정렬된 뷰를 만드는 방식과 동일한
/// 원리다.)
///
/// `listeningHistoryServiceProvider`(`service_providers.dart`)를 통해
/// 노출되며, `listening_history_screen.dart`가 화면 진입 시
/// `buildHistory()`를 호출해 목록을 구성한다.
class ListeningHistoryService {
  /// 필요한 하위 서비스들을 주입받아 생성한다(테스트에서 모킹 가능하도록).
  /// 모두 생략하면 각각 기본 구현을 새로 만들어 사용한다.
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
  /// (캐시된 오디오가 있는 문장들을, [ReviewRecord.firstLearnedAt] 내림차순
  /// (가장 최근에 학습한 것이 먼저)으로 정렬하고 [kMaxListeningHistorySize]로
  /// 개수를 제한해 반환한다. 캐시된 클립이 이미 evict되어 사라진 문장은
  /// 재생 버튼이 고장난 채로 보여주는 대신 목록에서 아예 제외한다 —
  /// `ReviewSessionService.buildReviewSet`이 review 대상을 고를 때 쓰는
  /// 것과 동일한 원칙이다.)
  ///
  /// `listening_history_screen.dart`의 상태 초기화(`initState`)에서
  /// 호출되어 화면에 표시할 목록을 비동기로 가져온다.
  /// 반환값: 재생 가능한(캐시가 살아있는) [ReviewRecord] 목록, 최신순.
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
