import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../theme/app_theme.dart';

/// The active theme. Loaded fresh from config.json on every build (so a
/// restart via `RestartWidget` re-reads it from scratch), defaulting new
/// users (no `themeMode` field yet) to [AppThemeMode.black].
class ThemeModeViewModel extends AsyncNotifier<AppThemeMode> {
  @override
  Future<AppThemeMode> build() async {
    final config = await ref.read(configServiceProvider).readConfig();
    return AppThemeMode.fromConfigValue(config.effectiveThemeMode);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(configServiceProvider).updateConfig(
          (current) => current.copyWith(themeMode: mode.configValue),
        );
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeViewModel, AppThemeMode>(
  ThemeModeViewModel.new,
);
