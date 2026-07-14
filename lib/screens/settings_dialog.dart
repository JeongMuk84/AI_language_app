import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import '../viewmodels/settings_view_model.dart';
import '../widgets/restart_widget.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final _nativeController = TextEditingController();
  final _targetController = TextEditingController();
  AppThemeMode _themeMode = AppThemeMode.black;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final config = await ref.read(configServiceProvider).readConfig();
    if (!mounted) return;
    setState(() {
      _nativeController.text = config.nativeLanguage ?? '';
      _targetController.text = config.targetLanguage ?? '';
      _themeMode = AppThemeMode.fromConfigValue(config.effectiveThemeMode);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    super.dispose();
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
      content: _loading
          ? const SizedBox(
              height: 96,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
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
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: state.isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_loading || state.isSaving) ? null : _save,
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
