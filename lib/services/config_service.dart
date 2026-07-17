import 'dart:convert';
import 'dart:io';

import '../models/app_config.dart';
import 'storage_location_service.dart';

/// Reads and writes `config.json` in the app's storage directory (see
/// `StorageLocationService`).
///
/// Never stores the Gemini API key — that belongs in secure storage
/// (see `ApiKeyStorageService`).
class ConfigService {
  ConfigService({StorageLocationService? storageLocationService})
      : _storageLocationService = storageLocationService ?? StorageLocationService();

  final StorageLocationService _storageLocationService;

  Future<File> _configFile() async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/config.json');
  }

  /// Full path to config.json, for diagnostics/logging.
  Future<String> configFilePath() async => (await _configFile()).path;

  /// Deletes config.json if present. Used by the `RESET_APP` dev/test flag
  /// and Settings' "Reset All Data".
  Future<void> clearConfig() async {
    final file = await _configFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<AppConfig> readConfig() async {
    final file = await _configFile();
    if (!await file.exists()) {
      await file.writeAsString('{}');
      return AppConfig.fromJson(const {});
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return AppConfig.fromJson(const {});
    }
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    return AppConfig.fromJson(decoded);
  }

  Future<void> writeConfig(AppConfig config) async {
    final file = await _configFile();
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  Future<void> updateConfig(AppConfig Function(AppConfig current) update) async {
    final current = await readConfig();
    await writeConfig(update(current));
  }
}
