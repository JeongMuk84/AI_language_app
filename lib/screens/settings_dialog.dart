import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';
import '../theme/app_theme.dart';
import '../viewmodels/settings_view_model.dart';
import '../widgets/hold_to_reset_button.dart';
import '../widgets/restart_widget.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key, required this.initialConfig});

  /// Loaded by the caller before this dialog is shown (see
  /// SettingsIconButton), so the dialog's content is fully-formed on its
  /// very first build — no async setState swaps the content mid-transition.
  final AppConfig initialConfig;

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  late final _nativeController = TextEditingController(
    text: widget.initialConfig.nativeLanguage ?? '',
  );
  late final _targetController = TextEditingController(
    text: widget.initialConfig.targetLanguage ?? '',
  );
  late AppThemeMode _themeMode = AppThemeMode.fromConfigValue(
    widget.initialConfig.effectiveThemeMode,
  );

  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _resetAllData() async {
    await ref.read(settingsViewModelProvider.notifier).resetAllData();
    if (!mounted) return;
    Navigator.of(context).pop();
    RestartWidget.restartApp(context);
  }

  Future<void> _save() async {
    final result = await ref.read(settingsViewModelProvider.notifier).save(
          nativeLanguage: _nativeController.text,
          targetLanguage: _targetController.text,
          themeMode: _themeMode,
        );
    if (!mounted) return;

    switch (result) {
      case SettingsSaveResult.validationFailed:
        break;
      case SettingsSaveResult.saved:
        Navigator.of(context).pop();
      case SettingsSaveResult.savedWithRestart:
        Navigator.of(context).pop();
        RestartWidget.restartApp(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsViewModelProvider);

    return AlertDialog(
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Native language'),
            const SizedBox(height: 4),
            TextField(controller: _nativeController, enabled: !state.isSaving),
            const SizedBox(height: 16),
            const Text('Language to learn'),
            const SizedBox(height: 4),
            TextField(controller: _targetController, enabled: !state.isSaving),
            const SizedBox(height: 16),
            const Text('Theme'),
            const SizedBox(height: 8),
            SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(value: AppThemeMode.white, label: Text('White')),
                ButtonSegment(value: AppThemeMode.black, label: Text('Black')),
              ],
              selected: {_themeMode},
              onSelectionChanged: state.isSaving
                  ? null
                  : (selection) => setState(() => _themeMode = selection.first),
            ),
            if (state.infoMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                state.infoMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            HoldToResetButton(onConfirmed: _resetAllData),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: state.isSaving ? null : _save,
          child: state.isSaving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
