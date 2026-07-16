import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_key_storage_service.dart';
import '../services/config_service.dart';
import '../services/gemini_service.dart';
import '../services/handoff_service.dart';
import '../services/history_service.dart';
import '../services/session_state_service.dart';

final configServiceProvider = Provider<ConfigService>((ref) => ConfigService());

final apiKeyStorageServiceProvider =
    Provider<ApiKeyStorageService>((ref) => ApiKeyStorageService());

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService(
    apiKeyStorage: ref.read(apiKeyStorageServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

final handoffServiceProvider = Provider<HandoffService>((ref) => HandoffService());

final sessionStateServiceProvider =
    Provider<SessionStateService>((ref) => SessionStateService());

final historyServiceProvider = Provider<HistoryService>((ref) {
  return HistoryService(sessionStateService: ref.read(sessionStateServiceProvider));
});
