import 'dart:convert';
import 'dart:io';

import 'package:ai_language_app/constants/app_identity.dart';
import 'package:ai_language_app/services/listening_history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mirrors `review_session_service_test.dart`'s helper — all app data
  /// lives under `<Documents>/$kAppFolderName/` (see `StorageLocationService`).
  Directory appDir(Directory documentsDir) {
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    dir.createSync(recursive: true);
    return dir;
  }

  /// `TtsCacheService`/`ReviewHistoryService` now key everything by target
  /// language (see `languageStorageKey`) — 'target_language' (the language
  /// every test below configures) sanitizes to itself unchanged.
  Directory reviewHistoryDir(Directory docDir) {
    final dir = Directory('${docDir.path}/review_history/target_language');
    dir.createSync(recursive: true);
    return dir;
  }

  Directory audioCacheDir(Directory docDir) {
    final dir = Directory('${docDir.path}/audio_cache/target_language');
    dir.createSync(recursive: true);
    return dir;
  }

  test(
    'buildHistory: only cache-backed sentences are included, sorted newest-first '
    'by firstLearnedAt, capped at kMaxListeningHistorySize',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('listening_history_test');
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      addTearDown(() => tempDir.delete(recursive: true));
      final docDir = appDir(tempDir);

      // 105 learned sentences, firstLearnedAt spread across 105 distinct
      // days so "most recent 100" is unambiguous - every one of them has
      // cached audio, so the cap alone (not the cache filter) determines
      // what's excluded.
      final now = DateTime.now();
      final total = kMaxListeningHistorySize + 5;
      final reviewHistoryRaw = <String, dynamic>{
        for (var i = 0; i < total; i++)
          'sentence_$i': {
            'sentenceInTarget': 'sentence_$i',
            'sentenceInNative': 'native_$i',
            'firstLearnedAt': now.subtract(Duration(days: total - i)).toIso8601String(),
            'reviewCount': 0,
          },
        // Plus 3 more sentences with NO cached audio, deliberately learned
        // more recently than everything above - these must never appear in
        // the result no matter how recent they are.
        for (var i = 0; i < 3; i++)
          'uncached_$i': {
            'sentenceInTarget': 'uncached_$i',
            'sentenceInNative': 'uncached_native_$i',
            'firstLearnedAt': now.add(Duration(days: i + 1)).toIso8601String(),
            'reviewCount': 0,
          },
      };
      await File(
        '${reviewHistoryDir(docDir).path}/review_history.json',
      ).writeAsString(jsonEncode(reviewHistoryRaw));

      // TTS cache: every "sentence_N" has a cached clip; "uncached_N" never
      // gets a manifest entry at all.
      final cacheDir = audioCacheDir(docDir);
      final manifest = <String, dynamic>{};
      for (var i = 0; i < total; i++) {
        final fileName = 'clip_$i.wav';
        await File('${cacheDir.path}/$fileName').writeAsBytes([0]);
        manifest['target_language::sentence_$i'] = {
          'fileName': fileName,
          'lastUsedAt': now.toIso8601String(),
          'voice': 'Kore',
        };
      }
      await File('${cacheDir.path}/manifest.json').writeAsString(jsonEncode(manifest));

      await File(
        '${docDir.path}/config.json',
      ).writeAsString(jsonEncode({'targetLanguage': 'target_language', 'nativeLanguage': 'native'}));

      final result = await ListeningHistoryService().buildHistory();

      expect(result.length, kMaxListeningHistorySize, reason: 'must cap at kMaxListeningHistorySize');
      expect(
        result.every((r) => r.sentenceInTarget.startsWith('sentence_')),
        isTrue,
        reason: 'uncached sentences must never appear, even though they were learned most recently',
      );

      // Sorted newest-first: firstLearnedAt must be non-increasing down the list.
      for (var i = 0; i < result.length - 1; i++) {
        expect(
          result[i].firstLearnedAt.isAfter(result[i + 1].firstLearnedAt) ||
              result[i].firstLearnedAt.isAtSameMomentAs(result[i + 1].firstLearnedAt),
          isTrue,
          reason: 'result must be sorted by firstLearnedAt descending',
        );
      }

      // The cap must keep the MOST recently learned 100, i.e. sentence_5..sentence_104
      // (sentence_0..sentence_4, the 5 oldest, must be dropped).
      final resultIndices = result
          .map((r) => int.parse(r.sentenceInTarget.substring('sentence_'.length)))
          .toSet();
      for (var i = 0; i < 5; i++) {
        expect(resultIndices.contains(i), isFalse, reason: 'oldest entries beyond the cap must be dropped');
      }
      for (var i = 5; i < total; i++) {
        expect(resultIndices.contains(i), isTrue, reason: 'the 100 most-recently-learned must all be kept');
      }
    },
  );

  test('buildHistory: pool under the cap returns every cache-backed sentence, none dropped', () async {
    final tempDir = await Directory.systemTemp.createTemp('listening_history_test_small');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final now = DateTime.now();
    final records = <String, dynamic>{
      for (var i = 0; i < 4; i++)
        'sentence_$i': {
          'sentenceInTarget': 'sentence_$i',
          'sentenceInNative': 'native_$i',
          'firstLearnedAt': now.subtract(Duration(days: 4 - i)).toIso8601String(),
          'reviewCount': 0,
        },
      'no_audio': {
        'sentenceInTarget': 'no_audio',
        'sentenceInNative': 'n',
        'firstLearnedAt': now.toIso8601String(),
        'reviewCount': 0,
      },
    };
    await File(
      '${reviewHistoryDir(docDir).path}/review_history.json',
    ).writeAsString(jsonEncode(records));

    final cacheDir = audioCacheDir(docDir);
    final manifest = <String, dynamic>{};
    for (var i = 0; i < 4; i++) {
      final fileName = 'clip_$i.wav';
      await File('${cacheDir.path}/$fileName').writeAsBytes([0]);
      manifest['target_language::sentence_$i'] = {
        'fileName': fileName,
        'lastUsedAt': now.toIso8601String(),
        'voice': 'Kore',
      };
    }
    // 'no_audio' intentionally absent from the manifest.
    await File('${cacheDir.path}/manifest.json').writeAsString(jsonEncode(manifest));
    await File(
      '${docDir.path}/config.json',
    ).writeAsString(jsonEncode({'targetLanguage': 'target_language', 'nativeLanguage': 'native'}));

    final result = await ListeningHistoryService().buildHistory();
    expect(result.length, 4);
    expect(result.map((r) => r.sentenceInTarget), isNot(contains('no_audio')));
    // Newest-first: sentence_3 was learned last, so it must come first.
    expect(result.first.sentenceInTarget, 'sentence_3');
    expect(result.last.sentenceInTarget, 'sentence_0');
  });

  test('buildHistory: no learned sentences yet returns an empty list', () async {
    final tempDir = await Directory.systemTemp.createTemp('listening_history_test_empty');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    appDir(tempDir);

    final result = await ListeningHistoryService().buildHistory();
    expect(result, isEmpty);
  });
}
