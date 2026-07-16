import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'services/api_key_storage_service.dart';
import 'services/config_service.dart';
import 'services/handoff_service.dart';
import 'services/history_service.dart';
import 'services/session_state_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/theme_mode_view_model.dart';
import 'widgets/restart_widget.dart';

/// Dev/test convenience flags, applied before normal startup routing runs.
/// See README.md's "Development" section for usage examples.
///
/// `RESET_APP=true` clears everything (API key, config.json, session
/// state, history, handoff files) — equivalent to the three flags below
/// combined, plus config.json and handoff files (which have no flag of
/// their own since a partial reset that drops native/target language
/// wouldn't be a meaningful "full" reset).
const _resetApp = bool.fromEnvironment('RESET_APP');

/// Clears only the secure-storage API key.
const _resetKey = bool.fromEnvironment('RESET_KEY');

/// Clears only the in-progress session state.
const _resetSession = bool.fromEnvironment('RESET_SESSION');

/// Clears only the saved history files.
const _resetHistory = bool.fromEnvironment('RESET_HISTORY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configService = ConfigService();
  debugPrint('[ai_language_app] config.json path: ${await configService.configFilePath()}');

  await applyResetFlags(configService: configService);

  runApp(
    const RestartWidget(
      child: ProviderScope(child: MyApp()),
    ),
  );
}

/// Applies whichever `RESET_*` dart-defines were passed, before any normal
/// routing logic runs. Each resource is cleared through the owning
/// service's own `clear*` method — the same ones Settings' "Reset All
/// Data" button uses — so this is just flag-reading glue, not a second
/// copy of the reset logic.
Future<void> applyResetFlags({required ConfigService configService}) async {
  final targets = <String, bool>{
    'API Key': _resetApp || _resetKey,
    'config.json': _resetApp,
    'session state': _resetApp || _resetSession,
    'history': _resetApp || _resetHistory,
    'handoff files': _resetApp,
  };

  if (!targets.values.any((shouldClear) => shouldClear)) {
    return;
  }

  if (targets['API Key']!) {
    await ApiKeyStorageService().clearApiKey();
  }
  if (targets['config.json']!) {
    await configService.clearConfig();
  }
  if (targets['session state']!) {
    await SessionStateService().clearSession();
  }
  if (targets['history']!) {
    await HistoryService().clearHistory();
  }
  if (targets['handoff files']!) {
    await HandoffService().clearHandoffFiles();
  }

  final cleared = targets.entries.where((e) => e.value).map((e) => e.key).join(', ');
  final preserved = targets.entries.where((e) => !e.value).map((e) => e.key).join(', ');
  debugPrint(
    '[RESET] Cleared: $cleared.'
    '${preserved.isEmpty ? '' : ' Preserved: $preserved.'}',
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
