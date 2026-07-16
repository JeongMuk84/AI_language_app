import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../screens/settings_dialog.dart';
import '../services/audio_playback_registry.dart';

/// Standard "open Settings" AppBar action, used on every screen after
/// ApiKeyScreen. Not shown on ApiKeyScreen — there's nothing to configure
/// yet. Normally reached via [buildAppBarWithSettings] rather than used
/// directly.
///
/// Pulled into one widget so all three screens stay in sync: relies on
/// `AppBarTheme.foregroundColor` (set per White/Black theme) to color the
/// icon, rather than hardcoding a color here, so it can't end up blending
/// into the AppBar background in either theme.
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  Future<void> _openSettings(BuildContext context) async {
    // Mitigates a known unfixed audioplayers_windows threading bug (see
    // AudioPlaybackRegistry) — pause any playing audio before the modal
    // opens, since that's the trigger that made it reproducible.
    await AudioPlaybackRegistry.pauseAll();
    if (!context.mounted) return;

    // Load config.json BEFORE opening the dialog, instead of inside
    // SettingsDialog's initState. Loading it after the dialog is already
    // showing meant its content swapped via setState — a small loading
    // placeholder to the full form, mid-flight during the dialog route's own
    // ~150ms entrance transition. That structural size change racing the
    // transition is what was tripping the framework's
    // '!semantics.parentDataDirty' assertion, confirmed via a Windows
    // integration-test repro that reproduced it deterministically even with
    // zero audio involved (a bare Scaffold + this button was enough).
    // Reading config.json is fast local file I/O, so doing it up front
    // avoids any loading placeholder in the dialog at all.
    final config = await ProviderScope.containerOf(
      context,
    ).read(configServiceProvider).readConfig();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(initialConfig: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
      onPressed: () => _openSettings(context),
    );
  }
}
