import 'dart:convert';
import 'dart:io';

import 'package:ai_language_app/constants/app_identity.dart';
import 'package:ai_language_app/services/review_session_service.dart';
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

  /// All app data now lives under `<Documents>/$kAppFolderName/` (see
  /// `StorageLocationService`) rather than directly in the fake documents
  /// root — this mirrors that one level of nesting so these tests still
  /// exercise the real (non-mocked) `ReviewSessionService`/
  /// `TtsCacheService`/`ReviewHistoryService`/`ConfigService` code against
  /// real files, just at the path those services now actually resolve to.
  Directory appDir(Directory documentsDir) {
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    dir.createSync(recursive: true);
    return dir;
  }

  test('buildReviewSet: pool > 15 selects exactly 15 with no duplicates, '
      'and the 10 most-recently-first-learned are always included', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    // 20 review records, firstLearnedAt spread across 20 distinct days so
    // "most recent 10" is unambiguous. lastReviewedAt left null for all
    // (maximally "overdue") so the weighted sample only has to prove it
    // draws *some* 5 of the remaining 10 without duplicating the first 10.
    final now = DateTime.now();
    final records = <Map<String, dynamic>>[
      for (var i = 0; i < 20; i++)
        {
          'sentenceInTarget': 'sentence_$i',
          'sentenceInNative': 'native_$i',
          'firstLearnedAt': now.subtract(Duration(days: 20 - i)).toIso8601String(),
          'reviewCount': 0,
        },
    ];
    final reviewHistoryRaw = {for (final r in records) r['sentenceInTarget'] as String: r};
    await File('${docDir.path}/review_history.json').writeAsString(jsonEncode(reviewHistoryRaw));

    // TTS cache: every sentence has a cached clip.
    final cacheDir = Directory('${docDir.path}/tts_cache')..createSync();
    final manifest = <String, dynamic>{};
    for (var i = 0; i < 20; i++) {
      final fileName = 'clip_$i.wav';
      await File('${cacheDir.path}/$fileName').writeAsBytes([0]);
      manifest['target_language::sentence_$i'] = {
        'fileName': fileName,
        'lastUsedAt': now.toIso8601String(),
        'voice': 'Kore',
      };
    }
    await File('${cacheDir.path}/manifest.json').writeAsString(jsonEncode(manifest));

    // config.json with a target language matching the cache keys above.
    await File(
      '${docDir.path}/config.json',
    ).writeAsString(jsonEncode({'targetLanguage': 'target_language', 'nativeLanguage': 'native'}));

    final service = ReviewSessionService();
    final result = await service.buildReviewSet();

    expect(result.length, 15, reason: 'must cap at kMaxReviewSetSize');
    final targets = result.map((e) => e.sentenceInTarget).toSet();
    expect(targets.length, 15, reason: 'no duplicates');

    // sentence_10..sentence_19 are the 10 most-recently-first-learned.
    final mostRecent10 = {for (var i = 10; i < 20; i++) 'sentence_$i'};
    expect(
      targets.intersection(mostRecent10).length,
      10,
      reason: 'all 10 most-recently-learned sentences must be included',
    );

    // The remaining 5 must come from the older half (sentence_0..9), not
    // be extra copies of the recent 10.
    final oldHalf = {for (var i = 0; i < 10; i++) 'sentence_$i'};
    expect(targets.intersection(oldHalf).length, 5);
  });

  test('buildReviewSet: pool <= 15 returns every reviewable sentence', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_small');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final now = DateTime.now();
    final records = <String, dynamic>{
      for (var i = 0; i < 5; i++)
        'sentence_$i': {
          'sentenceInTarget': 'sentence_$i',
          'sentenceInNative': 'native_$i',
          'firstLearnedAt': now.toIso8601String(),
          'reviewCount': 0,
        },
    };
    await File('${docDir.path}/review_history.json').writeAsString(jsonEncode(records));

    final cacheDir = Directory('${docDir.path}/tts_cache')..createSync();
    final manifest = <String, dynamic>{};
    for (var i = 0; i < 5; i++) {
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

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, 5);
  });

  test('buildReviewSet: sentences with no cached audio are excluded', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_nocache');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final now = DateTime.now();
    await File('${docDir.path}/review_history.json').writeAsString(
      jsonEncode({
        'has_audio': {
          'sentenceInTarget': 'has_audio',
          'sentenceInNative': 'n1',
          'firstLearnedAt': now.toIso8601String(),
          'reviewCount': 0,
        },
        'no_audio': {
          'sentenceInTarget': 'no_audio',
          'sentenceInNative': 'n2',
          'firstLearnedAt': now.toIso8601String(),
          'reviewCount': 0,
        },
      }),
    );

    final cacheDir = Directory('${docDir.path}/tts_cache')..createSync();
    await File('${cacheDir.path}/clip.wav').writeAsBytes([0]);
    await File('${cacheDir.path}/manifest.json').writeAsString(
      jsonEncode({
        'target_language::has_audio': {
          'fileName': 'clip.wav',
          'lastUsedAt': now.toIso8601String(),
          'voice': 'Kore',
        },
        // no_audio intentionally absent from the manifest.
      }),
    );
    await File(
      '${docDir.path}/config.json',
    ).writeAsString(jsonEncode({'targetLanguage': 'target_language', 'nativeLanguage': 'native'}));

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, 1);
    expect(result.single.sentenceInTarget, 'has_audio');
  });
}
