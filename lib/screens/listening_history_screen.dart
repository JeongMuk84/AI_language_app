import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review_record.dart';
import '../providers/service_providers.dart';
import '../services/audio_playback_registry.dart';
import '../theme/design_tokens.dart';
import '../widgets/audio_play_button.dart';

/// 독립적인 "예전에 학습했던 문장들을 다시 들어보기" 화면.
/// `ListeningHistoryIconButton`에서 모달 다이얼로그로 열리며,
/// ReviewScreen/DictionaryScreen과는 완전히 별개다. 열릴 때
/// [ListeningHistoryService]로 목록을 한 번만 불러온다(이런 일회성 읽기에는
/// 별도의 Riverpod StateNotifier/ViewModel이 필요 없다 — DictionaryScreen/
/// SettingsDialog의 로컬 상태 방식과 같은 접근이다); 이 다이얼로그가 열려있는
/// 동안 뒤쪽 화면은 계속 마운트된 채로 손대지 않고 남아있는다.
class ListeningHistoryScreen extends ConsumerStatefulWidget {
  const ListeningHistoryScreen({super.key});

  /// 이 위젯의 상태 객체([_ListeningHistoryScreenState])를 생성한다.
  @override
  ConsumerState<ListeningHistoryScreen> createState() => _ListeningHistoryScreenState();
}

/// [ListeningHistoryScreen]의 State. 리스닝 히스토리 목록을 담을
/// `Future`를 로컬로 보관한다.
class _ListeningHistoryScreenState extends ConsumerState<ListeningHistoryScreen> {
  late final Future<List<ReviewRecord>> _historyFuture;

  /// 화면이 처음 마운트될 때 `listeningHistoryServiceProvider.buildHistory()`를
  /// 한 번 호출해 [_historyFuture]에 담아둔다.
  @override
  void initState() {
    super.initState();
    _historyFuture = ref.read(listeningHistoryServiceProvider).buildHistory();
  }

  /// [_historyFuture]를 `FutureBuilder`로 구독해 로딩/빈 목록/실제 목록에
  /// 맞는 UI를 그린다.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Listening History'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: FutureBuilder<List<ReviewRecord>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snapshot.data!;
            if (records.isEmpty) {
              return Center(
                child: Text(
                  'No sentences yet',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            // ListView.builder (not rendering all up-front) matters here:
            // this list can have up to kMaxListeningHistorySize (100) rows.
            return ListView.separated(
              itemCount: records.length,
              separatorBuilder: (context, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _ListeningHistoryRow(record: records[index]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// 리스닝 히스토리 목록의 한 행. 문장 텍스트와 함께, 캐시된 오디오만
/// 재생하는 [AudioPlayButton]을 보여준다.
class _ListeningHistoryRow extends ConsumerWidget {
  const _ListeningHistoryRow({required this.record});

  /// 이 행이 표시할 리뷰 기록(문장/오디오 캐시 조회에 필요한 정보).
  final ReviewRecord record;

  /// 문장 텍스트와 재생 버튼으로 이루어진 한 행을 그린다.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xs, horizontal: DesignSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(record.sentenceInTarget, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: DesignSpacing.sm),
          AudioPlayButton(
            key: ValueKey('listening-history-${record.sentenceInTarget}'),
            tooltip: 'Play sentence',
            // Independent per row, but starting one must stop whichever
            // other row is mid-playback rather than overlap audio.
            onBeforePlay: AudioPlaybackRegistry.pauseAll,
            // Cache-only — never falls back to a fresh TTS call.
            // `ListeningHistoryService.buildHistory` already guaranteed
            // this sentence has cached audio; if it's since been evicted
            // this returns null and the button shows its own error state
            // rather than synthesizing (same principle as ReviewScreen).
            audioLoader: () async {
              final config = await ref.read(configServiceProvider).readConfig();
              final hit = await ref
                  .read(ttsCacheServiceProvider)
                  .get(
                    sentence: record.sentenceInTarget,
                    language: config.targetLanguage ?? 'the target language',
                  );
              if (hit == null) {
                throw StateError('No cached audio for this sentence.');
              }
              return hit.audioBytes;
            },
          ),
        ],
      ),
    );
  }
}
