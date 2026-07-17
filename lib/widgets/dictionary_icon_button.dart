import 'package:flutter/material.dart';

import '../screens/dictionary_screen.dart';
import '../services/audio_playback_registry.dart';

/// Standard "open Dictionary" AppBar action — mirrors [SettingsIconButton]
/// in structure and placement (see [buildAppBarWithSettings]).
class DictionaryIconButton extends StatelessWidget {
  const DictionaryIconButton({super.key});

  Future<void> _openDictionary(BuildContext context) async {
    // Same mitigation as SettingsIconButton, for the same reason: a modal
    // opening while audio is playing is what reproduces a known
    // audioplayers_windows threading bug (see AudioPlaybackRegistry) — not
    // specific to Settings, so any dialog opened from these screens needs
    // it.
    await AudioPlaybackRegistry.pauseAll();
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (context) => const DictionaryScreen());
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_book),
      tooltip: 'Dictionary',
      onPressed: () => _openDictionary(context),
    );
  }
}
