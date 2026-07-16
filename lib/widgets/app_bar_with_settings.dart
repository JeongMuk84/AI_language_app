import 'package:flutter/material.dart';

import 'settings_icon_button.dart';

/// Builds the standard AppBar shape used by every screen after
/// ApiKeyScreen: a title plus the shared [SettingsIconButton] action. Use
/// this instead of hand-rolling `AppBar(actions: [SettingsIconButton()])`
/// so all of them stay visually identical.
AppBar buildAppBarWithSettings(BuildContext context, String title) {
  return AppBar(title: Text(title), actions: const [SettingsIconButton()]);
}
