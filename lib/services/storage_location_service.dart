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
/// (앱이 디스크에 파일을 저장하는 위치에 대한 유일한 기준(single source of
/// truth) — 모든 파일이 Documents 루트에 흩어지는 대신
/// `<Documents>/$kAppFolderName/` 아래에 모여 있다. 파일/디렉터리 경로가
/// 필요한 다른 모든 서비스는 `getApplicationDocumentsDirectory()`를 직접
/// 호출하는 대신 반드시 [baseDirectory]를 거쳐야 한다 — 다른 어딘가에서
/// 단 한 번이라도 직접 호출하면 데이터가 두 위치로 다시 쪼개지게 되는데,
/// 그것이 바로 이 서비스가 존재하는 이유인 문제 그 자체다.)
///
/// `storageLocationServiceProvider`(`service_providers.dart`)를 통해
/// 노출되며, `ConfigService`, `TtsCacheService`, `HistoryService`,
/// `ReviewHistoryService`, `ConversationHistoryService`, `HandoffService`,
/// `SessionStateService` 등 파일 시스템에 접근하는 거의 모든 서비스가
/// 이 서비스를 통해 저장 경로를 얻는다. `main.dart`가 앱 시작 시
/// [migrateLegacyDataIfNeeded]와 [migrateToPerLanguageStorageIfNeeded]를
/// 순서대로 호출해 과거 버전의 데이터 배치를 최신 구조로 마이그레이션한다.
class StorageLocationService {
  Directory? _cachedBaseDir;

  /// Resolves (creating if necessary) the app's base storage directory.
  /// Cached after the first successful resolution within this process,
  /// since the directory doesn't move mid-run.
  /// (앱의 기본 저장 디렉터리를 찾아내고, 없으면 생성한다. 실행 중에는
  /// 디렉터리가 옮겨지지 않으므로 이 프로세스 안에서 처음 성공적으로
  /// 찾은 이후에는 결과를 캐시한다.)
  ///
  /// `ConfigService`, `TtsCacheService`, `HistoryService`,
  /// `ReviewHistoryService`, `ConversationHistoryService`,
  /// `HandoffService`, `SessionStateService`를 비롯해 파일 경로가 필요한
  /// 모든 서비스가 내부적으로 호출하며, `main.dart`도 시작 시 로그 출력을
  /// 위해 직접 호출한다.
  /// 반환값: 앱 전용 저장 디렉터리(`<Documents>/$kAppFolderName/`)의
  /// `Directory` 핸들.
  /// 부작용: 디렉터리가 없으면 생성하고, 결과를 인스턴스 내부에 캐시한다.
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
  /// (예전에 모든 것이 `<Documents>/$kAppFolderName/` 아래로 통합되기
  /// 전에는 `<Documents>/` 바로 아래에 흩어져 있던 파일들을 한 번만
  /// 옮긴다. 완료 여부는 NEW 기본 디렉터리 안의 플래그 파일로
  /// 표시한다 — config.json에 표시하지 않는 이유는, config.json 자체가
  /// 이번에 옮겨지는 대상 중 하나라서 거기에 플래그를 쓰면 바로 그
  /// config.json을 옮기는 마이그레이션 자체와 경합(race)하게 되기
  /// 때문이다. 그래서 이 방식으로는 절대 재실행되지 않으며, 최초 실행
  /// 이후에는 매 실행마다 플래그 파일 존재 확인 한 번의 비용만 든다.
  ///
  /// 원본 파일은 절대 삭제하지 않으며, 원본 *디렉터리*는 그 안의 모든
  /// 파일이 문제없이 다 옮겨졌을 때만 삭제한다. 도중에 실패하면 그냥
  /// 로그만 남기고 손대지 않은 원본을 그대로 남겨둔다 — 데이터 손실이
  /// 남아있는 자잘한 파일 하나보다 훨씬 나쁘기 때문이다.)
  ///
  /// `main.dart`가 앱 시작 시 [baseDirectory] 확보 직후,
  /// [migrateToPerLanguageStorageIfNeeded]보다 먼저 한 번 호출한다.
  /// 부작용: `config.json`, `session_state.json`, `daily_progress.json`,
  /// `review_progress.json`, `review_history.json`, `handoff_*.json`,
  /// `history/`, `tts_cache/` 등을 새 기본 디렉터리로 옮기고, 완료 시
  /// `.migration_complete` 플래그 파일을 쓴다.
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
        // (이미 무언가 있다면(예: 이전에 중간까지 실행된 적이 있는 경우) —
        // 절대 덮어쓰지 않는다; 어느 쪽이 더 최신인지 추측하는 대신 예전
        // 사본을 그대로 둔다.)
        return;
      }
      try {
        await source.rename(destination.path);
        movedCount++;
        debugPrint('[Migration] Moved $name');
      } catch (e) {
        // rename() can fail across filesystem/volume boundaries — fall
        // back to copy-then-delete-original.
        // (rename()은 파일시스템/볼륨 경계를 넘을 때 실패할 수 있다 — 이
        // 경우 복사 후 원본 삭제 방식으로 대체한다.)
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
      // (여기서의 정리 작업은 어디까지나 최선을 다하는 수준일 뿐이다 —
      // 해가 없는 빈 레거시 폴더가 남는 것은 괜찮지만, 정리 실패(예: 위의
      // 이동 직후 일시적으로 걸리는 Windows/OneDrive 파일 잠금 —
      // 실제로 "PathAccessException: Deletion failed... Access denied"가
      // 관측된 적 있음) 때문에 나머지 마이그레이션이 중단되는 것은
      // 용납할 수 없다. 이 시점에는 각 파일의 실제 내용은 여기서 무슨
      // 일이 일어나든 상관없이 이미 다 옮겨진 상태다.)
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
    // (각 단계는 독립적으로 보호된다 — 파일/폴더 하나를 옮기다가 실패해도
    // 나머지 단계를 시도하는 것을 절대 막아서는 안 된다.)
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
    // (handoff_<language>.json — 언어 이름을 미리 알 수 없으므로, 목록을
    // 나열하는 대신 패턴을 스캔한다.)
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
  /// (`review_progress.json`의 `reviewItemList[].cachedAudioPath`는 예전에는
  /// (OLD 기본 디렉터리를 기준으로 만들어진) 절대 경로를 저장했었다 —
  /// 디렉터리를 옮기고 나면 이 경로는 낡고 틀린 값이 된다. 방금 옮겨진
  /// 사본 안의 그런 항목들을, 지금 `TtsCacheService.peek`가 저장하는
  /// 방식과 맞춰 파일명만 남긴 형태로 다시 써준다. 파일이 없거나 고칠 것이
  /// 없으면(현재 코드로 새로 만들어진 review set은 이미 파일명만
  /// 저장하므로) 아무 일도 하지 않는다.)
  ///
  /// [migrateLegacyDataIfNeeded]가 파일 이동 단계들을 마친 마지막
  /// 단계로 호출한다.
  /// [base]: 이미 옮겨진 새 기본 저장 디렉터리.
  /// 부작용: 필요하면 `review_progress.json`을 다시 쓴다.
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
  /// ((예전에는 언어와 무관하게 단일 구조였던) 평평한(flat)
  /// `tts_cache/`/`review_history.json`을 대상 언어별 폴더
  /// (`audio_cache/<languageKey>/`, `review_history/<languageKey>/`)로 한
  /// 번만 옮긴다 — `TtsCacheService`/`ReviewHistoryService` 참고.
  /// [migrateLegacyDataIfNeeded](이미 기존 설치에 대해 플래그로 관리되고
  /// 완료된 별개의 마이그레이션)와는 별도의 자체 플래그 파일을 가지므로,
  /// 그쪽 상태와 무관하게 독립적으로 정확히 한 번만 실행된다.
  ///
  /// 발견된 모든 데이터는 현재 `config.json`의 대상 언어에 귀속시킨다 —
  /// 평평한 구조의 cache/history에 내용이 쌓였다는 것 자체가 실제로 어떤
  /// 언어를 공부했었다는 뜻일 수밖에 없기 때문이다. 설정된 대상 언어가
  /// 없다면(데이터를 귀속시킬 대상이 없다면) 추측하는 대신 이번 실행에서는
  /// 완전히 건너뛰고, 나중에 대상 언어가 설정된 뒤 다음 실행에서 다시
  /// 시도할 수 있다. [migrateLegacyDataIfNeeded]와 동일한 데이터 안전
  /// 규칙을 따른다: 원본 파일은 절대 삭제하지 않고, 원본 디렉터리는 안의
  /// 모든 것이 옮겨졌을 때만 삭제하며, 파일/폴더 하나의 실패가 나머지를
  /// 중단시키지 않는다.)
  ///
  /// `main.dart`가 앱 시작 시 [migrateLegacyDataIfNeeded] 이후에 호출한다.
  /// [configService]: 대상 언어를 읽기 위한 [ConfigService](생략 시 새로
  /// 만들어 사용).
  /// 부작용: `review_history.json`을 `review_history/<key>/`로,
  /// `tts_cache/`의 내용을 `audio_cache/<key>/`로 옮기고, 완료 시
  /// `.migration_per_language_complete` 플래그 파일을 쓴다. 대상 언어가
  /// 아직 없으면 아무 것도 하지 않고 반환한다.
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
      // (migrateLegacyDataIfNeeded와 같은 이유로, 이 정리 작업도 어디까지나
      // 최선을 다하는 수준일 뿐이다: 남아있는 빈 레거시 폴더는 무해하며,
      // 정리 실패가 마치 마이그레이션 자체가 실패한 것처럼 보여서는 안
      // 된다.)
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
