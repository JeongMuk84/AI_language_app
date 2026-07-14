import 'package:flutter/material.dart';

import '../screens/settings_dialog.dart';

/// Standard "open Settings" AppBar action, used on every screen after
/// ApiKeyScreen (LanguageSelectScreen, LevelTestScreen, LearningScreen).
/// Not shown on ApiKeyScreen — there's nothing to configure yet.
///
/// Pulled into one widget so all three screens stay in sync: relies on
/// `AppBarTheme.foregroundColor` (set per White/Black theme) to color the
/// icon, rather than hardcoding a color here, so it can't end up blending
/// into the AppBar background in either theme.
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => const SettingsDialog(),
      ),
    );
  }
}
