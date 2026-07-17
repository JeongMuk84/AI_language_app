import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_key_storage_service.dart';
import '../services/config_service.dart';
import '../services/gemini_service.dart';
import '../services/handoff_service.dart';
import '../services/history_service.dart';
import '../services/review_history_service.dart';
import '../services/review_session_service.dart';
import '../services/session_state_service.dart';
import '../services/storage_location_service.dart';
import '../services/tts_cache_service.dart';

final storageLocationServiceProvider =
    Provider<StorageLocationService>((ref) => StorageLocationService());

final configServiceProvider = Provider<ConfigService>((ref) {
  return ConfigService(storageLocationService: ref.read(storageLocationServiceProvider));
});

final apiKeyStorageServiceProvider =
    Provider<ApiKeyStorageService>((ref) => ApiKeyStorageService());

final ttsCacheServiceProvider = Provider<TtsCacheService>((ref) {
  return TtsCacheService(storageLocationService: ref.read(storageLocationServiceProvider));
});

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService(
    apiKeyStorage: ref.read(apiKeyStorageServiceProvider),
    configService: ref.read(configServiceProvider),
    ttsCacheService: ref.read(ttsCacheServiceProvider),
  );
});

final handoffServiceProvider = Provider<HandoffService>((ref) {
  return HandoffService(storageLocationService: ref.read(storageLocationServiceProvider));
});

final sessionStateServiceProvider = Provider<SessionStateService>((ref) {
  return SessionStateService(storageLocationService: ref.read(storageLocationServiceProvider));
});

final historyServiceProvider = Provider<HistoryService>((ref) {
  return HistoryService(
    sessionStateService: ref.read(sessionStateServiceProvider),
    storageLocationService: ref.read(storageLocationServiceProvider),
  );
});

final reviewHistoryServiceProvider = Provider<ReviewHistoryService>((ref) {
  return ReviewHistoryService(storageLocationService: ref.read(storageLocationServiceProvider));
});

final reviewSessionServiceProvider = Provider<ReviewSessionService>((ref) {
  return ReviewSessionService(
    reviewHistoryService: ref.read(reviewHistoryServiceProvider),
    ttsCacheService: ref.read(ttsCacheServiceProvider),
    configService: ref.read(configServiceProvider),
  );
});

/// Turns completed today (0-[kDailyTurnLimit]). Cached until explicitly
/// invalidated — callers that change the count (turn completion, resets)
/// must `ref.invalidate(dailyTurnCountProvider)` afterward so screens that
/// watch it pick up the new value.
final dailyTurnCountProvider = FutureProvider<int>((ref) {
  return ref.read(sessionStateServiceProvider).readDailyTurnCount();
});
