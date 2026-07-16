import 'package:flutter/material.dart';

import 'settings_icon_button.dart';

/// Builds the standard AppBar shape used by every screen after
/// ApiKeyScreen: a title plus the shared [SettingsIconButton] action. Use
/// this instead of hand-rolling `AppBar(actions: [SettingsIconButton()])`
/// so all of them stay visually identical.
///
/// [progressLabel], when given (e.g. "Today: 3/10"), is shown as a single
/// plain `Text` action to the title's left — not folded into a multi-line
/// `title` `Column`. A freshly-mounted multi-child-parentData widget (like
/// `Column`) built during this screen's own route transition previously
/// tripped a real Flutter framework bug (`!semantics.parentDataDirty`, see
/// `HoldToResetButton`'s history) — a single `Text` avoids that risk
/// entirely.
AppBar buildAppBarWithSettings(BuildContext context, String title, {String? progressLabel}) {
  return AppBar(
    title: Text(title),
    actions: [
      if (progressLabel != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(progressLabel, style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      const SettingsIconButton(),
    ],
  );
}
