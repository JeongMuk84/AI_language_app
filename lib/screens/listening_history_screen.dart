import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review_record.dart';
import '../providers/service_providers.dart';
import '../services/audio_playback_registry.dart';
import '../theme/design_tokens.dart';
import '../widgets/audio_play_button.dart';

/// Standalone "listen back to previously-learned sentences" screen, opened
/// as a modal dialog (see `ListeningHistoryIconButton`) — entirely
/// independent of ReviewScreen/DictionaryScreen. Loads its list once on
/// open via [ListeningHistoryService] (no separate Riverpod
/// StateNotifier/ViewModel needed for a one-shot read like this, matching
/// DictionaryScreen/SettingsDialog's local-state approach); the screen
/// behind this dialog stays mounted and untouched for as long as it's open.
class ListeningHistoryScreen extends ConsumerStatefulWidget {
  const ListeningHistoryScreen({super.key});

  @override
  ConsumerState<ListeningHistoryScreen> createState() => _ListeningHistoryScreenState();
}

class _ListeningHistoryScreenState extends ConsumerState<ListeningHistoryScreen> {
  late final Future<List<ReviewRecord>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = ref.read(listeningHistoryServiceProvider).buildHistory();
  }

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

class _ListeningHistoryRow extends ConsumerWidget {
  const _ListeningHistoryRow({required this.record});

  final ReviewRecord record;

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
