import 'dart:convert';
import 'dart:io';

import '../models/handoff_data.dart';
import 'storage_location_service.dart';

/// Reads/writes per-language handoff files (`handoff_<language>.json`) in
/// the app's storage directory (see `StorageLocationService`), used to
/// resume a previously-studied language without repeating the level test.
class HandoffService {
  HandoffService({StorageLocationService? storageLocationService})
      : _storageLocationService = storageLocationService ?? StorageLocationService();

  final StorageLocationService _storageLocationService;

  Future<File> _fileFor(String language) async {
    final dir = await _storageLocationService.baseDirectory();
    return File('${dir.path}/handoff_${_slug(language)}.json');
  }

  String _slug(String language) =>
      language.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  Future<bool> exists(String language) async => (await _fileFor(language)).exists();

  Future<HandoffData?> read(String language) async {
    final file = await _fileFor(language);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return HandoffData.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }

  Future<void> write(String language, HandoffData data) async {
    final file = await _fileFor(language);
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  /// Deletes every language's handoff file. Used by the `RESET_APP` dev/
  /// test flag and Settings' "Reset All Data".
  Future<void> clearHandoffFiles() async {
    final dir = await _storageLocationService.baseDirectory();
    final entries = await dir.list().toList();
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = _basename(entry.path);
      if (name.startsWith('handoff_') && name.endsWith('.json')) {
        await entry.delete();
      }
    }
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
