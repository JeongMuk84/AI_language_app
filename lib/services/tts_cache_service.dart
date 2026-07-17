import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'storage_location_service.dart';

/// A cached TTS clip, plus the voice it was originally synthesized with.
class TtsCacheHit {
  const TtsCacheHit({required this.audioBytes, required this.voice});

  final Uint8List audioBytes;
  final String voice;
}

/// Where a cached clip lives on disk, plus its voice — returned by [peek],
/// which doesn't load the audio itself.
class TtsCacheLocation {
  const TtsCacheLocation({required this.path, required this.voice});

  /// The cached `.wav` file's name WITHIN the `tts_cache/` directory —
  /// deliberately just a bare filename, not an absolute path, so it stays
  /// valid regardless of where `StorageLocationService.baseDirectory()`
  /// resolves to on a given machine/run. Resolve against
  /// `StorageLocationService` + `'tts_cache'` if a real file path is ever
  /// needed; currently nothing reads this for actual playback (see
  /// `ReviewScreen`, which re-resolves via `TtsCacheService.get` instead).
  final String path;
  final String voice;
}

/// Caches synthesized TTS audio on disk, keyed by (sentence, language), so
/// the same sentence is never sent to the TTS API twice — a cache hit
/// (including replaying the same sentence again later, or resuming a
/// session across app restarts) never calls Gemini.
///
/// Cache metadata (which sentence maps to which audio file, when it was
/// last used, and which voice it was synthesized with) lives in a single
/// `manifest.json` alongside the cached `.wav` files, under the app's
/// storage directory (see `StorageLocationService`). Capped at
/// [_maxEntries] entries, evicted least-recently-used first.
class TtsCacheService {
  TtsCacheService({StorageLocationService? storageLocationService})
      : _storageLocationService = storageLocationService ?? StorageLocationService();

  final StorageLocationService _storageLocationService;

  static const _maxEntries = 100;

  Future<Directory> _cacheDir() async {
    final dir = await _storageLocationService.baseDirectory();
    final cacheDir = Directory('${dir.path}/tts_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<File> _manifestFile() async {
    final dir = await _cacheDir();
    return File('${dir.path}/manifest.json');
  }

  /// Manifest keys are the raw `"language::sentence"` string — no need to
  /// hash it, since a JSON object key can be any string. Only the on-disk
  /// *filename* needs to be filesystem-safe, so that's separately derived
  /// via [_fnv1aHex].
  String _manifestKey(String sentence, String language) => '$language::$sentence';

  Future<Map<String, dynamic>> _readManifest() async {
    final file = await _manifestFile();
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return {};
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<void> _writeManifest(Map<String, dynamic> manifest) async {
    final file = await _manifestFile();
    await file.writeAsString(jsonEncode(manifest));
  }

  /// Returns the cached clip for (sentence, language), touching its
  /// last-used time, or null if nothing is cached for it yet.
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
  /// least-recently-used entry first if this would exceed [_maxEntries].
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

  /// Deletes the entire cache. Used by the `RESET_APP` dev/test flag and
  /// Settings' "Reset All Data".
  Future<void> clearCache() async {
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 32-bit FNV-1a hash, hex-encoded — deterministic and filesystem-safe.
  /// Not cryptographic; collisions are astronomically unlikely at the
  /// ~100-entry scale this cache runs at.
  String _fnv1aHex(String input) {
    const fnvPrime = 0x01000193;
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ byte) * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
