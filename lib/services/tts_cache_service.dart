import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../utils/language_key.dart';
import 'config_service.dart';
import 'storage_location_service.dart';

/// A cached TTS clip, plus the voice it was originally synthesized with.
/// (캐시된 TTS 클립과, 원래 합성될 때 쓰인 음성을 함께 담는 값 객체.)
/// [TtsCacheService.get]이 캐시 히트 시 반환하는 결과 타입이며,
/// `GeminiService.speakCached`가 재생용 오디오 바이트를 얻을 때, 여러
/// 화면(`review_screen.dart` 등)의 `audioLoader` 콜백이 캐시에서 직접
/// 오디오를 읽어올 때 사용한다.
class TtsCacheHit {
  /// [audioBytes]와 [voice]로 캐시 히트 결과를 만든다.
  const TtsCacheHit({required this.audioBytes, required this.voice});

  /// 캐시에서 읽어온 재생 가능한 WAV 오디오 바이트.
  final Uint8List audioBytes;
  /// 이 클립이 합성될 때 쓰인 TTS 음성 이름.
  final String voice;
}

/// Where a cached clip lives on disk, plus its voice — returned by [peek],
/// which doesn't load the audio itself.
/// (캐시된 클립이 디스크의 어디에 있는지와 그 음성을 담는 값 객체 — 오디오
/// 자체를 로드하지 않는 [TtsCacheService.peek]이 반환한다.)
/// `ReviewSessionService.buildReviewSet`과
/// `ListeningHistoryService.buildHistory`가 어떤 문장이 재생 가능한지(캐시가
/// 살아있는지)만 저비용으로 확인할 때 사용한다.
class TtsCacheLocation {
  /// [path]와 [voice]로 캐시 위치 정보를 만든다.
  const TtsCacheLocation({required this.path, required this.voice});

  /// The cached `.wav` file's name WITHIN the current target language's
  /// `audio_cache/<languageKey>/` directory — deliberately just a bare
  /// filename, not an absolute path, so it stays valid regardless of where
  /// `StorageLocationService.baseDirectory()` resolves to on a given
  /// machine/run. Resolve against `StorageLocationService` +
  /// `'audio_cache/<languageKey>'` if a real file path is ever needed;
  /// currently nothing reads this for actual playback (see `ReviewScreen`,
  /// which re-resolves via `TtsCacheService.get` instead).
  /// (현재 대상 언어의 `audio_cache/<languageKey>/` 디렉터리 *안에서의*
  /// 캐시된 `.wav` 파일 이름 — 의도적으로 절대 경로가 아니라 파일명만
  /// 담는데, 이는 `StorageLocationService.baseDirectory()`가 특정
  /// 기기/실행에서 어디로 해석되든 상관없이 이 값이 유효하도록 하기
  /// 위함이다. 실제 파일 경로가 필요하면 `StorageLocationService` +
  /// `'audio_cache/<languageKey>'`와 조합해 계산해야 한다; 현재는 실제
  /// 재생을 위해 이 값을 직접 읽는 곳이 없다(`ReviewScreen`은 대신
  /// `TtsCacheService.get`으로 다시 조회한다).)
  final String path;
  /// 이 클립이 합성될 때 쓰인 TTS 음성 이름.
  final String voice;
}

/// Caches synthesized TTS audio on disk, keyed by (sentence, language), so
/// the same sentence is never sent to the TTS API twice — a cache hit
/// (including replaying the same sentence again later, or resuming a
/// session across app restarts) never calls Gemini.
///
/// Kept strictly per target language, under
/// `audio_cache/<languageKey>/manifest.json` + `.wav` files (see
/// [languageStorageKey]) — resolved from the CURRENT `config.json` on every
/// call, so switching target languages transparently switches which
/// language's cache is read/written without any caller needing to know
/// about it. The [_maxEntries] LRU cap applies per language folder: a full
/// Vietnamese cache never evicts Spanish entries or vice versa.
/// (합성된 TTS 오디오를 (문장, 언어) 조합을 키로 디스크에 캐시해서, 같은
/// 문장이 TTS API로 두 번 전송되는 일이 없게 한다 — 캐시 히트(나중에 같은
/// 문장을 다시 재생하는 경우나, 앱을 재시작한 뒤 세션을 재개하는 경우
/// 포함)는 절대 Gemini를 호출하지 않는다.
///
/// 대상 언어별로 철저히 분리되어 `audio_cache/<languageKey>/manifest.json`
/// + `.wav` 파일들([languageStorageKey] 참고) 아래에 저장되며, "지금 어느
/// 언어인지"는 매번 호출 시점의 현재 `config.json`에서 판단한다. 그래서
/// 대상 언어를 전환하면 호출자가 이를 전혀 몰라도 투명하게 읽고 쓰는
/// 캐시가 그 언어의 것으로 바뀐다. [_maxEntries] LRU 상한은 언어 폴더별로
/// 각각 적용된다: 베트남어 캐시가 가득 찬다고 스페인어 항목이 evict되는
/// 일은 없으며 그 반대도 마찬가지다.)
///
/// `ttsCacheServiceProvider`(`service_providers.dart`)를 통해 노출되며,
/// `GeminiService.speakCached`가 재생 전 캐시를 확인/저장할 때,
/// `ReviewSessionService`와 `ListeningHistoryService`가 어떤 문장이 재생
/// 가능한지 필터링할 때, `ReviewViewModel`/`review_screen.dart`/
/// `shadowing_pronunciation_screen.dart`/`listening_history_screen.dart`가
/// 저장된 오디오를 직접 재생할 때 사용한다.
class TtsCacheService {
  /// 필요한 하위 서비스들을 주입받아 생성한다(테스트에서 모킹 가능하도록).
  /// 모두 생략하면 각각 기본 구현을 새로 만들어 사용한다.
  TtsCacheService({StorageLocationService? storageLocationService, ConfigService? configService})
    : _storageLocationService = storageLocationService ?? StorageLocationService(),
      _configService = configService ?? ConfigService();

  final StorageLocationService _storageLocationService;
  final ConfigService _configService;

  /// 언어별 폴더 하나당 유지하는 최대 캐시 항목 수. 이를 넘으면 LRU
  /// (least-recently-used, 가장 오래 사용되지 않은 것)부터 evict된다.
  static const _maxEntries = 100;

  /// Parent of every language's cache folder — used only by [clearCache]
  /// (full reset, all languages) since normal reads/writes always go
  /// through [_cacheDir] for the current language.
  /// (모든 언어의 캐시 폴더의 상위 디렉터리 — 일반적인 읽기/쓰기는 항상
  /// 현재 언어를 위한 [_cacheDir]를 거치므로, 이 메서드는 전체 초기화(모든
  /// 언어 대상)를 하는 [clearCache]에서만 사용된다.)
  Future<Directory> _rootCacheDir() async {
    final dir = await _storageLocationService.baseDirectory();
    return Directory('${dir.path}/audio_cache');
  }

  /// 현재 대상 언어에 해당하는 캐시 디렉터리(`audio_cache/<languageKey>/`)
  /// 핸들을 반환한다. `config.json`에서 `targetLanguage`를 읽어
  /// `languageStorageKey`로 키를 만들고, 필요하면 디렉터리를 생성한다.
  /// 이 클래스의 다른 메서드들이 내부적으로 사용하는 헬퍼다.
  /// 부작용: 대상 언어별 디렉터리가 없으면 새로 만든다.
  Future<Directory> _cacheDir() async {
    final config = await _configService.readConfig();
    final key = languageStorageKey(config.targetLanguage ?? 'unknown');
    final root = await _rootCacheDir();
    final cacheDir = Directory('${root.path}/$key');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// 현재 대상 언어 캐시 디렉터리 안의 `manifest.json` 파일 핸들을
  /// 반환한다. [_readManifest]와 [_writeManifest]가 사용하는 헬퍼다.
  Future<File> _manifestFile() async {
    final dir = await _cacheDir();
    return File('${dir.path}/manifest.json');
  }

  /// Manifest keys are the raw `"language::sentence"` string — no need to
  /// hash it, since a JSON object key can be any string. Only the on-disk
  /// *filename* needs to be filesystem-safe, so that's separately derived
  /// via [_fnv1aHex].
  /// (manifest의 키는 `"language::sentence"` 원본 문자열 그대로다 — JSON
  /// 객체의 키는 어떤 문자열이든 될 수 있으므로 해시할 필요가 없다.
  /// 파일시스템에 안전해야 하는 것은 디스크상의 *파일명*뿐이며, 그건
  /// [_fnv1aHex]로 별도 계산한다.)
  ///
  /// [get], [peek], [put]이 manifest Map을 조회/기록할 때 쓸 키를 만들기
  /// 위해 호출한다.
  /// [sentence]: 대상 언어 문장.
  /// [language]: 대상 언어 이름.
  /// 반환값: manifest Map의 키로 쓸 `"language::sentence"` 문자열.
  String _manifestKey(String sentence, String language) => '$language::$sentence';

  /// 현재 대상 언어의 manifest.json을 읽어 원본 JSON Map으로 반환한다.
  /// 파일이 없거나 비어있으면 빈 Map을 반환한다. [get], [peek], [put]이
  /// 내부적으로 사용하는 헬퍼다.
  Future<Map<String, dynamic>> _readManifest() async {
    final file = await _manifestFile();
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return {};
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// [manifest] Map을 JSON으로 직렬화해 현재 대상 언어의 manifest.json에
  /// 덮어쓴다. [get](엔트리 없음 정리 시), [put], [_evictLruIfNeeded]
  /// 호출 이후 저장에 쓰인다.
  /// 부작용: manifest.json 파일을 덮어쓴다.
  Future<void> _writeManifest(Map<String, dynamic> manifest) async {
    final file = await _manifestFile();
    await file.writeAsString(jsonEncode(manifest));
  }

  /// Returns the cached clip for (sentence, language), touching its
  /// last-used time, or null if nothing is cached for it yet.
  /// ((문장, 언어)에 대한 캐시된 클립을 반환하고, 그 항목의 마지막 사용
  /// 시각을 갱신한다. 아직 캐시된 것이 없으면 null을 반환한다.)
  ///
  /// `GeminiService.speakCached`가 TTS를 다시 합성하기 전에 캐시 히트가
  /// 있는지 확인할 때, `review_screen.dart`/
  /// `shadowing_pronunciation_screen.dart`/`listening_history_screen.dart`의
  /// `audioLoader` 콜백이 캐시된 오디오만으로(새 TTS 호출 없이) 재생할 때
  /// 호출한다.
  /// [sentence]: 대상 언어 문장(캐시 키의 일부).
  /// [language]: 대상 언어 이름(캐시 키의 일부).
  /// 반환값: 캐시 히트 시 [TtsCacheHit], 캐시가 없거나 파일이 사라졌으면
  /// `null`.
  /// 부작용: 히트 시 manifest의 `lastUsedAt`을 갱신하고 저장한다. manifest와
  /// 실제 파일이 어긋나 있으면(파일이 수동으로 지워진 경우 등) 낡은
  /// manifest 항목을 제거하고 저장한다.
  Future<TtsCacheHit?> get({required String sentence, required String language}) async {
    final manifest = await _readManifest();
    final key = _manifestKey(sentence, language);
    final entry = manifest[key] as Map<String, dynamic>?;
    if (entry == null) return null;

    final fileName = entry['fileName'] as String?;
    final voice = entry['voice'] as String?;
    if (fileName == null || voice == null) return null;

    final dir = await _cacheDir();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) {
      // Manifest and disk disagree (e.g. file was manually removed) —
      // drop the stale entry rather than returning a hit with no bytes.
      // (manifest와 실제 디스크 상태가 어긋난 경우다(예: 파일이 수동으로
      // 삭제됨) — 바이트 없는 히트를 반환하는 대신 낡은 항목을 제거한다.)
      manifest.remove(key);
      await _writeManifest(manifest);
      return null;
    }

    entry['lastUsedAt'] = DateTime.now().toIso8601String();
    await _writeManifest(manifest);
    return TtsCacheHit(audioBytes: await file.readAsBytes(), voice: voice);
  }

  /// Checks whether (sentence, language) has cached audio, without loading
  /// its bytes or touching its last-used time — used by
  /// `ReviewSessionService` to filter to reviewable sentences without
  /// artificially extending their LRU lifetime just by checking. Use [get]
  /// instead when actually about to play the clip.
  /// ((문장, 언어)에 대한 캐시된 오디오가 있는지만 확인한다 — 바이트를
  /// 로드하거나 마지막 사용 시각을 갱신하지 않는다. `ReviewSessionService`가
  /// 단지 확인만 하는 것으로 LRU 수명을 인위적으로 늘리지 않으면서 복습
  /// 가능한 문장을 필터링할 때 사용한다. 실제로 클립을 재생하려는
  /// 것이라면 [get]을 대신 사용할 것.)
  ///
  /// `ReviewSessionService.buildReviewSet`과
  /// `ListeningHistoryService.buildHistory`가 어떤 문장이 재생 가능한지
  /// 필터링할 때, `ReviewViewModel`이 복습 진행 상황을 만들 때 호출한다.
  /// [sentence]: 대상 언어 문장.
  /// [language]: 대상 언어 이름.
  /// 반환값: 캐시가 있으면 파일명과 음성을 담은 [TtsCacheLocation], 없으면
  /// `null`.
  Future<TtsCacheLocation?> peek({required String sentence, required String language}) async {
    final manifest = await _readManifest();
    final entry = manifest[_manifestKey(sentence, language)] as Map<String, dynamic>?;
    final fileName = entry?['fileName'] as String?;
    final voice = entry?['voice'] as String?;
    if (fileName == null || voice == null) return null;

    final dir = await _cacheDir();
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) return null;
    return TtsCacheLocation(path: fileName, voice: voice);
  }

  /// Stores newly-synthesized audio for (sentence, language), evicting the
  /// least-recently-used entry first if this would exceed [_maxEntries]
  /// (within this language's own folder only).
  /// (새로 합성된 (문장, 언어)의 오디오를 저장하며, 이로 인해
  /// [_maxEntries]를 초과하게 되면(오직 이 언어 자신의 폴더 안에서만)
  /// 가장 오래 사용되지 않은 항목부터 먼저 evict한다.)
  ///
  /// `GeminiService.speakCached`가 캐시 미스로 새로 TTS를 합성한 직후,
  /// 그 결과를 캐시에 저장하기 위해 호출한다.
  /// [sentence]: 대상 언어 문장(캐시 키의 일부).
  /// [language]: 대상 언어 이름(캐시 키의 일부).
  /// [audioBytes]: 저장할 WAV 오디오 바이트.
  /// [voice]: 합성에 사용된 TTS 음성 이름.
  /// 부작용: `.wav` 파일을 쓰고 manifest를 갱신하며, 상한 초과 시 LRU
  /// 항목을 evict한다.
  Future<void> put({
    required String sentence,
    required String language,
    required Uint8List audioBytes,
    required String voice,
  }) async {
    final dir = await _cacheDir();
    final key = _manifestKey(sentence, language);
    final fileName = '${_fnv1aHex(key)}.wav';
    await File('${dir.path}/$fileName').writeAsBytes(audioBytes);

    final manifest = await _readManifest();
    manifest[key] = {
      'fileName': fileName,
      'lastUsedAt': DateTime.now().toIso8601String(),
      'voice': voice,
    };
    await _evictLruIfNeeded(manifest, dir);
    await _writeManifest(manifest);
  }

  /// [manifest]의 항목 수가 [_maxEntries]를 초과하면, `lastUsedAt`이 가장
  /// 오래된(least-recently-used) 항목부터 초과분만큼 manifest에서 제거하고
  /// 대응하는 `.wav` 파일도 디스크에서 삭제한다. [put]이 새 항목을 추가한
  /// 직후 호출하는 헬퍼다.
  /// [manifest]: (변경 가능한) 현재 언어의 manifest Map.
  /// [dir]: 이 언어의 캐시 디렉터리(파일 삭제 경로 계산용).
  /// 부작용: [manifest]에서 오래된 항목을 제거하고, 대응하는 `.wav` 파일을
  /// 디스크에서 삭제한다.
  Future<void> _evictLruIfNeeded(Map<String, dynamic> manifest, Directory dir) async {
    if (manifest.length <= _maxEntries) return;

    final byLastUsed = manifest.entries.toList()
      ..sort((a, b) {
        final aTime = DateTime.parse((a.value as Map<String, dynamic>)['lastUsedAt'] as String);
        final bTime = DateTime.parse((b.value as Map<String, dynamic>)['lastUsedAt'] as String);
        return aTime.compareTo(bTime);
      });

    final overflow = manifest.length - _maxEntries;
    for (var i = 0; i < overflow; i++) {
      final entry = byLastUsed[i];
      manifest.remove(entry.key);
      final fileName = (entry.value as Map<String, dynamic>)['fileName'] as String?;
      if (fileName != null) {
        final file = File('${dir.path}/$fileName');
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Deletes every language's cache. Used by the `RESET_APP` dev/test flag
  /// and Settings' "Reset All Data" — a target-language switch must NOT
  /// call this (see `SettingsViewModel.save`); each language's cache stays
  /// intact so switching back to a previously-studied language finds its
  /// audio (and thus its `ListeningHistoryScreen` entries) still there.
  /// (모든 언어의 캐시를 삭제한다. `main.dart`의 `RESET_APP` 개발/테스트용
  /// 플래그와 Settings 화면의 "Reset All Data"(`SettingsViewModel`)에서
  /// 사용된다 — 대상 언어를 전환하는 것만으로는 절대 이 메서드를 호출해서는
  /// 안 된다(`SettingsViewModel.save` 참고); 각 언어의 캐시는 그대로
  /// 남아있어야, 예전에 공부했던 언어로 다시 돌아왔을 때 그 오디오(그리고
  /// 그로 인한 `ListeningHistoryScreen` 항목들)가 여전히 남아있게 된다.)
  /// 부작용: `audio_cache` 디렉터리 전체를 재귀적으로 삭제한다.
  Future<void> clearCache() async {
    final dir = await _rootCacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 32-bit FNV-1a hash, hex-encoded — deterministic and filesystem-safe.
  /// Not cryptographic; collisions are astronomically unlikely at the
  /// ~100-entry scale this cache runs at (per language).
  /// (32비트 FNV-1a 해시를 16진수로 인코딩한다 — 결정적(deterministic)이고
  /// 파일시스템에 안전하다. 암호학적 해시가 아니며, 이 캐시가 언어당
  /// 운용되는 ~100개 규모에서는 충돌 가능성이 천문학적으로 낮다.)
  ///
  /// [put]이 manifest 키로부터 파일시스템에 안전한 `.wav` 파일명을 만들
  /// 때 호출하는 헬퍼다.
  /// [input]: 해시할 원본 문자열(manifest 키, `"language::sentence"`).
  /// 반환값: 8자리 16진수 해시 문자열.
  String _fnv1aHex(String input) {
    const fnvPrime = 0x01000193;
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ byte) * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
