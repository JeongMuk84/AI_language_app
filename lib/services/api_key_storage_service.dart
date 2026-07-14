import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Gemini API key in secure storage. This is the single source
/// of truth for "is the key configured" — never mirrored into config.json.
class ApiKeyStorageService {
  static const _apiKeyStorageKey = 'gemini_api_key';

  final _storage = const FlutterSecureStorage();

  Future<String?> readApiKey() => _storage.read(key: _apiKeyStorageKey);

  Future<void> saveApiKey(String apiKey) =>
      _storage.write(key: _apiKeyStorageKey, value: apiKey);

  Future<bool> hasApiKey() async {
    final value = await readApiKey();
    return value != null && value.trim().isNotEmpty;
  }

  /// Wipes everything this app has written to secure storage (currently
  /// just the API key). Used by the `RESET_APP` dev/test flag.
  Future<void> deleteAll() => _storage.deleteAll();
}
