import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_identity.dart';
import '../utils/language_key.dart';
import 'config_service.dart';

/// Single source of truth for where the app stores its files on disk —
/// everything lives under `<Documents>/$kAppFolderName/` instead of
/// scattered loose across the Documents root. Every other service that
/// needs a file/directory path must go through [baseDirectory] instead of
/// calling `getApplicationDocumentsDirectory()` directly — a single direct
/// call anywhere else re-splits data across two locations, which is
/// exactly the problem this service exists to fix.
class StorageLocationService {
  Directory? _cachedBaseDir;

  /// Resolves (creating if necessary) the app's base storage directory.
  /// Cached after the first successful resolution within this process,
  /// since the directory doesn't move mid-run.
  Future<Directory> baseDirectory() async {
    final cached = _cachedBaseDir;
    if (cached != null) return cached;

    final documentsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedBaseDir = dir;
    return dir;
  }

  /// One-time move of files that used to live loose directly in
  /// `<Documents>/`, from before everything moved under
  /// `<Documents>/$kAppFolderName/`. Marks itself done via a flag file
  /// inside the NEW base directory — not config.json, since config.json
  /// is itself one of the things being moved, so writing a flag into it
  /// would race the very migration that relocates it — so this never
  /// re-runs, and costs only a flag-file existence check on every launch
  /// after the first.
  ///
  /// Never deletes a source file, and only ever deletes a source
  /// *directory* once every file inside it made it across cleanly. A
  /// failure partway through just logs and leaves the untouched original
  /// in place — data loss is worse than a leftover stray file.
  Future<void> migrateLegacyDataIfNeeded() async {
    final base = await baseDirectory();
    final flagFile = File('${base.path}/.migration_complete');
    if (await flagFile.exists()) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    var movedCount = 0;
    var failedCount = 0;

    Future<void> moveFile(String name) async {
      final source = File('${documentsDir.path}/$name');
      if (!await source.exists()) return;
      final destination = File('${base.path}/$name');
      if (await destination.exists()) {
        // Something's already there (e.g. a previous partial run) — never
        // overwrite; leave the legacy copy alone rather than guess which
        // one is newer.
        return;
      }
      try {
        await source.rename(destination.path);
        movedCount++;
        debugPrint('[Migration] Moved $name');
      } catch (e) {
        // rename() can fail across filesystem/volume boundaries — fall
        // back to copy-then-delete-original.
        try {
          await destination.writeAsBytes(await source.readAsBytes());
          await source.delete();
          movedCount++;
          debugPrint('[Migration] Moved $name (via copy)');
        } catch (e2) {
          failedCount++;
          debugPrint('[Migration] FAILED to move $name: $e2');
        }
      }
    }

    Future<void> moveDirectoryContents(String name) async {
      final source = Directory('${documentsDir.path}/$name');
      if (!await source.exists()) return;
      final destination = Directory('${base.path}/$name');
      if (!await destination.exists()) {
        await destination.create(recursive: true);
      }

      var allOk = true;
      await for (final entry in source.list()) {
        if (entry is! File) continue;
        final fileName = entry.uri.pathSegments.last;
        final destFile = File('${destination.path}/$fileName');
        if (await destFile.exists()) continue;
        try {
          await entry.rename(destFile.path);
          movedCount++;
        } catch (e) {
          try {
            await destFile.writeAsBytes(await entry.readAsBytes());
            await entry.delete();
            movedCount++;
          } catch (e2) {
            failedCount++;
            allOk = false;
            debugPrint('[Migration] FAILED to move $name/$fileName: $e2');
          }
        }
      }
      debugPrint('[Migration] Moved contents of $name/');

      // Best-effort cleanup only — leaving a harmless empty legacy folder
      // behind is fine; letting a cleanup failure (e.g. a transient
      // Windows/OneDrive file-lock right after the moves above, seen live:
      // "PathAccessException: Deletion failed... Access denied") abort the
      // rest of the migration is not. Every file's actual content already
      // made it across by this point regardless of what happens here.
      if (allOk) {
        try {
          final remaining = await source.list().toList();
          if (remaining.isEmpty) {
            await source.delete();
          }
        } catch (e) {
          debugPrint('[Migration] Could not remove now-empty legacy folder $name/: $e');
        }
      }
    }

    // Each step is independently guarded — one file/folder failing to
    // move must never stop the rest from being attempted.
    Future<void> tryStep(String label, Future<void> Function() step) async {
      try {
        await step();
      } catch (e) {
        failedCount++;
        debugPrint('[Migration] FAILED step "$label": $e');
      }
    }

    await tryStep('config.json', () => moveFile('config.json'));
    await tryStep('session_state.json', () => moveFile('session_state.json'));
    await tryStep('daily_progress.json', () => moveFile('daily_progress.json'));
    await tryStep('review_progress.json', () => moveFile('review_progress.json'));
    await tryStep('review_history.json', () => moveFile('review_history.json'));

    // handoff_<language>.json — language names aren't known up front, so
    // scan for the pattern instead of listing them out.
    await tryStep('handoff files', () async {
      if (!await documentsDir.exists()) return;
      await for (final entry in documentsDir.list()) {
        if (entry is! File) continue;
        final fileName = entry.uri.pathSegments.last;
        if (fileName.startsWith('handoff_') && fileName.endsWith('.json')) {
          await moveFile(fileName);
        }
      }
    });

    await tryStep('history/', () => moveDirectoryContents('history'));
    await tryStep('tts_cache/', () => moveDirectoryContents('tts_cache'));

    await tryStep(
      'review_progress.json path sanitization',
      () => _sanitizeReviewProgressCachedPaths(base),
    );

    await flagFile.writeAsString(DateTime.now().toIso8601String());
    debugPrint('[Migration] Done — moved $movedCount file(s), $failedCount failure(s).');
  }

  /// `review_progress.json`'s `reviewItemList[].cachedAudioPath` used to
  /// store an absolute path (built from the OLD base directory) — stale
  /// and wrong after a move. Rewrites any such entries in the just-moved
  /// copy down to a bare filename, matching how `TtsCacheService.peek`
  /// stores it now. A no-op if the file doesn't exist or has nothing to
  /// fix (fresh review sets built by the current code already store bare
  /// filenames here).
  Future<void> _sanitizeReviewProgressCachedPaths(Directory base) async {
    final file = File('${base.path}/review_progress.json');
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final json = jsonDecode(content) as Map<String, dynamic>;
      final items = json['reviewItemList'] as List?;
      if (items == null) return;

      var changed = false;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final path = item['cachedAudioPath'] as String?;
        if (path == null) continue;
        final normalized = path.replaceAll('\\', '/');
        if (normalized.contains('/')) {
          item['cachedAudioPath'] = normalized.substring(normalized.lastIndexOf('/') + 1);
          changed = true;
        }
      }

      if (changed) {
        await file.writeAsString(jsonEncode(json));
        debugPrint('[Migration] Converted cachedAudioPath entries in review_progress.json to relative filenames.');
      }
    } catch (e) {
      debugPrint('[Migration] Could not sanitize review_progress.json paths: $e');
    }
  }

  /// One-time move of the (formerly language-agnostic) flat
  /// `tts_cache/`/`review_history.json` into per-target-language folders
  /// (`audio_cache/<languageKey>/`, `review_history/<languageKey>/`) — see
  /// `TtsCacheService`/`ReviewHistoryService`. Separate from
  /// [migrateLegacyDataIfNeeded] (a different migration, already flag-gated
  /// and completed for existing installs) with its own flag file, so it
  /// runs exactly once independently of that one's state.
  ///
  /// Everything found is attributed to the CURRENT `config.json` target
  /// language, since a flat cache/history could only have accumulated
  /// content by actually having studied some language — if there's no
  /// configured target language (nothing to attribute the data to), this
  /// is skipped entirely rather than guessing, and can retry on a later
  /// launch once one is set. Same data-safety rules as
  /// [migrateLegacyDataIfNeeded]: never deletes a source file, only ever
  /// deletes a source directory once everything inside made it across, and
  /// one file/folder failing never aborts the rest.
  Future<void> migrateToPerLanguageStorageIfNeeded({ConfigService? configService}) async {
    final base = await baseDirectory();
    final flagFile = File('${base.path}/.migration_per_language_complete');
    if (await flagFile.exists()) return;

    final config = await (configService ?? ConfigService(storageLocationService: this)).readConfig();
    final targetLanguage = config.targetLanguage;
    if (targetLanguage == null || targetLanguage.trim().isEmpty) {
      debugPrint('[Migration] No target language configured yet - skipping per-language migration for now.');
      return;
    }
    final key = languageStorageKey(targetLanguage);

    var movedCount = 0;
    var failedCount = 0;

    Future<bool> moveFile(File source, File destination) async {
      if (!await source.exists()) return true;
      if (await destination.exists()) return true;
      final destinationDir = destination.parent;
      if (!await destinationDir.exists()) {
        await destinationDir.create(recursive: true);
      }
      try {
        await source.rename(destination.path);
        movedCount++;
        debugPrint('[Migration] Moved ${source.path} to ${destination.path}');
        return true;
      } catch (e) {
        try {
          await destination.writeAsBytes(await source.readAsBytes());
          await source.delete();
          movedCount++;
          debugPrint('[Migration] Moved ${source.path} to ${destination.path} (via copy)');
          return true;
        } catch (e2) {
          failedCount++;
          debugPrint('[Migration] FAILED to move ${source.path}: $e2');
          return false;
        }
      }
    }

    Future<void> moveDirectoryContents(Directory source, Directory destination) async {
      if (!await source.exists()) return;
      if (!await destination.exists()) {
        await destination.create(recursive: true);
      }

      var allOk = true;
      await for (final entry in source.list()) {
        if (entry is! File) continue;
        final fileName = entry.uri.pathSegments.last;
        final destFile = File('${destination.path}/$fileName');
        if (await destFile.exists()) continue;
        try {
          await entry.rename(destFile.path);
          movedCount++;
        } catch (e) {
          try {
            await destFile.writeAsBytes(await entry.readAsBytes());
            await entry.delete();
            movedCount++;
          } catch (e2) {
            failedCount++;
            allOk = false;
            debugPrint('[Migration] FAILED to move ${entry.path}: $e2');
          }
        }
      }

      // Best-effort cleanup only, same reasoning as migrateLegacyDataIfNeeded:
      // a leftover empty legacy folder is harmless; a cleanup failure must
      // never look like the migration itself failed.
      if (allOk) {
        try {
          final remaining = await source.list().toList();
          if (remaining.isEmpty) {
            await source.delete();
          }
        } catch (e) {
          debugPrint('[Migration] Could not remove now-empty legacy folder ${source.path}: $e');
        }
      }
    }

    Future<void> tryStep(String label, Future<void> Function() step) async {
      try {
        await step();
      } catch (e) {
        failedCount++;
        debugPrint('[Migration] FAILED step "$label": $e');
      }
    }

    await tryStep(
      'review_history.json -> review_history/$key/',
      () => moveFile(
        File('${base.path}/review_history.json'),
        File('${base.path}/review_history/$key/review_history.json'),
      ),
    );
    await tryStep(
      'tts_cache/ -> audio_cache/$key/',
      () => moveDirectoryContents(
        Directory('${base.path}/tts_cache'),
        Directory('${base.path}/audio_cache/$key'),
      ),
    );

    await flagFile.writeAsString(DateTime.now().toIso8601String());
    debugPrint(
      '[Migration] Per-language migration done (target language: $targetLanguage) - '
      'moved $movedCount file(s), $failedCount failure(s).',
    );
  }
}
