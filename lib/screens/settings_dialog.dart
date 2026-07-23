import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_config.dart';
import '../theme/app_theme.dart';
import '../viewmodels/settings_view_model.dart';
import '../widgets/hold_to_reset_button.dart';
import '../widgets/restart_widget.dart';

/// 설정 화면. `SettingsIconButton`에서(모든 화면의 Settings 아이콘 버튼을
/// 통해) 모달 다이얼로그로 열린다. [SettingsViewModel]을 통해 모국어/학습
/// 언어/테마 저장, 학습 언어 전환, 전체 데이터 초기화를 처리한다.
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key, required this.initialConfig});

  /// 이 다이얼로그가 표시되기 전에 호출한 쪽(SettingsIconButton 참고)이 미리
  /// 읽어서 넘겨준 현재 설정값 — 그래서 다이얼로그의 내용이 첫 build부터
  /// 완전한 상태로 만들어지며, 전환 도중에 비동기 setState로 내용이
  /// 바뀌는 일이 없다.
  final AppConfig initialConfig;

  /// 이 위젯의 상태 객체([_SettingsDialogState])를 생성한다.
  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

/// [SettingsDialog]의 State. 모국어/학습 언어 입력 컨트롤러, 선택된 테마
/// 모드, 그리고 앱 버전 정보를 로컬로 관리한다.
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

  /// `PackageInfo.fromPlatform()`이 완료되기 전까지는 null이다 — 그동안
  /// 버전 줄은 다이얼로그가 열리는 것을 막지 않고 임시 텍스트를 보여준다.
  PackageInfo? _packageInfo;

  /// 화면이 처음 마운트될 때 [_loadPackageInfo]를 (완료를 기다리지 않고)
  /// 시작시킨다.
  @override
  void initState() {
    super.initState();
    unawaited(_loadPackageInfo());
  }

  /// `PackageInfo.fromPlatform()`으로 앱 버전/빌드 번호를 읽어와
  /// [_packageInfo]에 저장하고 다시 그리게 한다.
  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  /// `PackageInfo`를 통해 `pubspec.yaml`의 `version` 필드(예: `1.0.0+1`)에서
  /// 곧바로 읽어온 버전 + 빌드 번호 문자열을 만든다 — 절대 하드코딩하지
  /// 않으므로, 릴리즈를 올릴 때는 pubspec.yaml만 수정하면 된다.
  String _versionLabel() {
    final info = _packageInfo;
    if (info == null) return 'Version …';
    return 'Version ${info.version} (${info.buildNumber})';
  }

  /// 위젯이 트리에서 제거될 때 두 텍스트필드 컨트롤러를 해제해 메모리
  /// 누수를 막는다.
  @override
  void dispose() {
    _nativeController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  /// [HoldToResetButton]에서 눌러서 확정되면 호출된다.
  /// [SettingsViewModel.resetAllData]로 모든 저장 데이터를 지운 뒤
  /// 다이얼로그를 닫고 `RestartWidget.restartApp`으로 앱을 재시작시킨다.
  Future<void> _resetAllData() async {
    await ref.read(settingsViewModelProvider.notifier).resetAllData();
    if (!mounted) return;
    Navigator.of(context).pop();
    RestartWidget.restartApp(context);
  }

  /// Save 버튼이 눌리면 호출된다. [SettingsViewModel.save]로 입력된
  /// 모국어/학습 언어/테마를 저장한다. 결과([SettingsSaveResult])에 따라
  /// 검증 실패면 다이얼로그를 열어둔 채로 두고, 저장만 됐으면 다이얼로그를
  /// 닫고, 학습 언어가 바뀌어 재시작이 필요하면 다이얼로그를 닫은 뒤
  /// `RestartWidget.restartApp`으로 앱을 재시작시킨다.
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

  /// [SettingsViewModel]을 watch해 설정 다이얼로그 UI(언어 입력 필드, 테마
  /// 선택, 안내/에러 메시지, 초기화 버튼, 푸터의 제작자/버전 정보, Save/Cancel
  /// 버튼)를 그린다.
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
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            // Quiet footer info, not a setting — reuses `labelSmall`, which
            // is already themed to DESIGN.md's secondary-text color
            // (`slate` in White, `onDarkMuted` in Black) via
            // `onSurfaceMuted` in app_theme.dart, so it's never hardcoded
            // here and stays correct if those tokens ever change.
            Text('Created by JeongMuk84', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Text(_versionLabel(), style: Theme.of(context).textTheme.labelSmall),
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
