import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'services/api_key_storage_service.dart';
import 'services/config_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/theme_mode_view_model.dart';
import 'widgets/restart_widget.dart';

/// Dev/test convenience: `flutter run --dart-define=RESET_APP=true` wipes
/// all saved state (the secure-storage API key, config.json) before the app
/// starts, so normal startup routing lands back on ApiKeyScreen. No effect
/// when the flag is absent/false.
const _resetAppOnStart = bool.fromEnvironment('RESET_APP');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configService = ConfigService();
  debugPrint('[ai_language_app] config.json path: ${await configService.configFilePath()}');

  if (_resetAppOnStart) {
    debugPrint('[ai_language_app] RESET_APP=true — clearing all saved state...');
    await ApiKeyStorageService().deleteAll();
    await configService.deleteConfig();
    debugPrint('[ai_language_app] Reset complete.');
  }

  runApp(
    const RestartWidget(
      child: ProviderScope(child: MyApp()),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeModeAsync = ref.watch(themeModeProvider);

    return themeModeAsync.when(
      data: (mode) => MaterialApp.router(
        title: 'AI Language App',
        theme: themeDataFor(mode),
        routerConfig: router,
      ),
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (error, stackTrace) => MaterialApp(
        home: Scaffold(body: Center(child: Text('Failed to load settings: $error'))),
      ),
    );
  }
}
