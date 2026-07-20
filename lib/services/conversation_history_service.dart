import 'dart:convert';
import 'dart:io';

import '../models/conversation_turn.dart';
import '../utils/language_key.dart';
import 'config_service.dart';
import 'storage_location_service.dart';

/// Reads/writes the running conversation context (`generateNextSentence`'s
/// `history` argument) — kept strictly per target language under
/// `conversation_history/<languageKey>/history.json`, so switching target
/// languages can never mix one language's turns into another's prompt
/// context. Resolves "which language" from the current `config.json` on
/// every call rather than being told explicitly, since a turn is always
/// recorded/read while that language is still the active one (language
/// switches go through a restart before anything reads/writes here again).
///
/// Deliberately separate from `SessionStateService`: that owns the single,
/// language-agnostic "what am I doing right this second" fields
/// (current sentence/turn/sub-step), which get explicitly cleared on a
/// language switch (see `SettingsViewModel.save`) since resuming mid-turn
/// across a switch makes no sense. This history, by contrast, is meant to
/// survive a switch-away-and-back within the same language.
class ConversationHistoryService {
  ConversationHistoryService({StorageLocationService? storageLocationService, ConfigService? configService})
    : _storageLocationService = storageLocationService ?? StorageLocationService(),
      _configService = configService ?? ConfigService();

  final StorageLocationService _storageLocationService;
  final ConfigService _configService;

  Future<File> _historyFile() async {
    final config = await _configService.readConfig();
    final key = languageStorageKey(config.targetLanguage ?? 'unknown');
    final base = await _storageLocationService.baseDirectory();
    final dir = Directory('${base.path}/conversation_history/$key');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/history.json');
  }

  Future<List<ConversationTurn>> readAll() async {
    final file = await _historyFile();
    if (!await file.exists()) return const [];
    final content = await file.readAsString();
    if (content.trim().isEmpty) return const [];
    final list = jsonDecode(content) as List;
    return list.map((t) => ConversationTurn.fromJson(t as Map<String, dynamic>)).toList();
  }

  /// Appends [turn] to the current target language's history.
  Future<void> append(ConversationTurn turn) async {
    final existing = await readAll();
    await _writeAll([...existing, turn]);
  }

  Future<void> _writeAll(List<ConversationTurn> turns) async {
    final file = await _historyFile();
    await file.writeAsString(jsonEncode(turns.map((t) => t.toJson()).toList()));
  }

  /// Clears the current target language's history only — used when
  /// finalizing a session (see `HistoryService.finalizeSession`), same as
  /// the old single-file behavior. Does NOT touch any other language's
  /// history; use [clearAllLanguages] for a full reset.
  Future<void> clear() async {
    final file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes every language's conversation history. Used by the
  /// `RESET_APP` dev/test flag and Settings' "Reset All Data" — distinct
  /// from [clear], which only affects the current language.
  Future<void> clearAllLanguages() async {
    final base = await _storageLocationService.baseDirectory();
    final dir = Directory('${base.path}/conversation_history');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
