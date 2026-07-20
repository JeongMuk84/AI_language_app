import 'package:flutter/material.dart';

import '../screens/listening_history_screen.dart';
import '../services/audio_playback_registry.dart';

/// Standard "open Listening History" AppBar action — mirrors
/// [DictionaryIconButton]/`SettingsIconButton` in structure and placement
/// (see `buildAppBarWithSettings`).
class ListeningHistoryIconButton extends StatelessWidget {
  const ListeningHistoryIconButton({super.key});

  Future<void> _openListeningHistory(BuildContext context) async {
    // Same mitigation as SettingsIconButton/DictionaryIconButton, for the
    // same reason (see AudioPlaybackRegistry).
    await AudioPlaybackRegistry.pauseAll();
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (context) => const ListeningHistoryScreen());
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.headphones),
      tooltip: 'Listening History',
      onPressed: () => _openListeningHistory(context),
    );
  }
}
