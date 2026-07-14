import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_key_storage_service.dart';
import '../services/config_service.dart';
import '../services/gemini_service.dart';
import '../services/handoff_service.dart';

final configServiceProvider = Provider<ConfigService>((ref) => ConfigService());

final apiKeyStorageServiceProvider =
    Provider<ApiKeyStorageService>((ref) => ApiKeyStorageService());

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService(apiKeyStorage: ref.read(apiKeyStorageServiceProvider));
});

final handoffServiceProvider = Provider<HandoffService>((ref) => HandoffService());
