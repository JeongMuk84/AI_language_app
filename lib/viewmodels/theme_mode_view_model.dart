import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../theme/app_theme.dart';

/// 현재 활성화된 앱 테마([AppThemeMode]). `main.dart`의 `MaterialApp`이 이
/// provider를 watch해서 실제 테마를 적용하며, ApiKeyScreen/SettingsDialog의
/// 테마 선택 SegmentedButton도 이 값을 읽고 바꾼다. 매 build마다 config.json에서
/// 새로 읽어오므로(`RestartWidget`을 통한 재시작이 다시 처음부터 읽게 된다),
/// 아직 `themeMode` 필드가 없는 신규 사용자는 [AppThemeMode.black]으로
/// 기본값이 설정된다.
class ThemeModeViewModel extends AsyncNotifier<AppThemeMode> {
  /// `configServiceProvider`에서 config.json을 읽어 현재 테마 모드를
  /// 계산한다. Riverpod이 이 provider가 처음 watch/read될 때, 그리고
  /// invalidate된 뒤 다시 watch될 때 자동으로 호출한다.
  @override
  Future<AppThemeMode> build() async {
    final config = await ref.read(configServiceProvider).readConfig();
    return AppThemeMode.fromConfigValue(config.effectiveThemeMode);
  }

  /// ApiKeyScreen/SettingsDialog의 테마 선택 SegmentedButton에서 호출된다.
  /// [mode]로 state를 즉시 갱신해 UI가 바로 반응하게 한 뒤,
  /// `configServiceProvider.updateConfig`로 config.json에도 영구 저장한다.
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(configServiceProvider).updateConfig(
          (current) => current.copyWith(themeMode: mode.configValue),
        );
  }
}

/// [ThemeModeViewModel]/[AppThemeMode]를 노출하는 provider. `main.dart`,
/// ApiKeyScreen, SettingsDialog에서 `ref.watch`로 현재 테마를 읽고,
/// SettingsViewModel/SettingsDialog에서 `ref.read(...notifier)`로
/// `setThemeMode`를 호출한다.
final themeModeProvider = AsyncNotifierProvider<ThemeModeViewModel, AppThemeMode>(
  ThemeModeViewModel.new,
);
