import 'dart:convert';
import 'dart:io';

import 'package:ai_language_app/constants/app_identity.dart';
import 'package:ai_language_app/constants/learning_constants.dart';
import 'package:ai_language_app/services/review_session_service.dart';
import 'package:ai_language_app/services/tts_cache_service.dart';
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

  /// Writes review_history.json + a matching TTS cache manifest (one clip
  /// per record) + config.json. [records] maps sentence -> its review
  /// record JSON; a record whose key is also in [uncached] gets no manifest
  /// entry (so it's not reviewable). [dailyReviewCount] is written to
  /// config.json only when non-null.
  ///
  /// [phantomCacheEntries] adds that many extra manifest entries with NO
  /// backing `.wav` file and NO review record — they don't affect the
  /// review pool (peek() checks the file exists) but they DO count toward
  /// `TtsCacheService.count()`, which is how these tests push the live
  /// cache count up to the ramp-up threshold cheaply (no 590 real files).
  Future<void> seed(
    Directory docDir, {
    required Map<String, Map<String, dynamic>> records,
    Set<String> uncached = const {},
    int? dailyReviewCount,
    int phantomCacheEntries = 0,
  }) async {
    await File(
      '${reviewHistoryDir(docDir).path}/review_history.json',
    ).writeAsString(jsonEncode(records));

    final cacheDir = audioCacheDir(docDir);
    final manifest = <String, dynamic>{};
    final now = DateTime.now();
    for (final sentence in records.keys) {
      if (uncached.contains(sentence)) continue;
      final fileName = 'clip_${manifest.length}.wav';
      await File('${cacheDir.path}/$fileName').writeAsBytes([0]);
      manifest['target_language::$sentence'] = {
        'fileName': fileName,
        'lastUsedAt': now.toIso8601String(),
        'voice': 'Kore',
      };
    }
    for (var i = 0; i < phantomCacheEntries; i++) {
      manifest['target_language::__phantom_$i'] = {
        'fileName': '__phantom_$i.wav',
        'lastUsedAt': now.toIso8601String(),
        'voice': 'Kore',
      };
    }
    await File('${cacheDir.path}/manifest.json').writeAsString(jsonEncode(manifest));

    final config = <String, dynamic>{
      'targetLanguage': 'target_language',
      'nativeLanguage': 'native',
    };
    if (dailyReviewCount != null) config['dailyReviewCount'] = dailyReviewCount;
    await File('${docDir.path}/config.json').writeAsString(jsonEncode(config));
  }

  Map<String, Map<String, dynamic>> spreadRecords(int count, {int reviewCount = 0}) {
    final now = DateTime.now();
    return {
      for (var i = 0; i < count; i++)
        'sentence_$i': {
          'sentenceInTarget': 'sentence_$i',
          'sentenceInNative': 'native_$i',
          'firstLearnedAt': now.subtract(Duration(days: count - i)).toIso8601String(),
          'reviewCount': reviewCount,
        },
    };
  }

  /// 40 records `s_0`..`s_39`, `firstLearnedAt` oldest-first (s_0 oldest),
  /// with `reviewCount` banded so ramp-up's "most-worn, then oldest" order
  /// is unambiguous: s_0..9 => 6, s_10..29 => 1, s_30..39 => 0.
  Map<String, Map<String, dynamic>> bandedRecords() {
    final now = DateTime.now();
    int wearFor(int i) => i < 10
        ? 6
        : i < 30
            ? 1
            : 0;
    return {
      for (var i = 0; i < 40; i++)
        's_$i': {
          'sentenceInTarget': 's_$i',
          'sentenceInNative': 'n_$i',
          'firstLearnedAt': now.subtract(Duration(days: 40 - i)).toIso8601String(),
          'reviewCount': wearFor(i),
        },
    };
  }

  test('buildReviewSet: pool > target picks exactly dailyReviewCount with no '
      'duplicates, and the 10 most-recently-first-learned are always included', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    // 20 records across 20 distinct days; lastReviewedAt left null for all.
    await seed(docDir, records: spreadRecords(20), dailyReviewCount: 15);

    final result = await ReviewSessionService().buildReviewSet();

    expect(result.length, 15, reason: 'must cap at dailyReviewCount');
    final targets = result.map((e) => e.sentenceInTarget).toSet();
    expect(targets.length, 15, reason: 'no duplicates');

    // sentence_10..sentence_19 are the 10 most-recently-first-learned.
    final mostRecent10 = {for (var i = 10; i < 20; i++) 'sentence_$i'};
    expect(
      targets.intersection(mostRecent10).length,
      10,
      reason: 'all 10 most-recently-learned sentences must be included',
    );

    // The remaining 5 must come from the older half (sentence_0..9).
    final oldHalf = {for (var i = 0; i < 10; i++) 'sentence_$i'};
    expect(targets.intersection(oldHalf).length, 5);
  });

  test('buildReviewSet: default config (no dailyReviewCount) uses '
      'kDefaultDailyReviewCount as the target size', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_default');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    await seed(docDir, records: spreadRecords(kDefaultDailyReviewCount + 6));

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, kDefaultDailyReviewCount);
  });

  test('buildReviewSet: pool <= target returns every reviewable sentence', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_small');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    await seed(docDir, records: spreadRecords(5), dailyReviewCount: 20);

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, 5);
  });

  test('buildReviewSet: dailyReviewCount <= 10 takes that many of the '
      'most-recently-learned, no weighted random fill', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_lt10');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    await seed(docDir, records: spreadRecords(20), dailyReviewCount: 10);

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, 10);
    // Exactly the 10 most-recently-first-learned: sentence_10..sentence_19.
    expect(
      result.map((e) => e.sentenceInTarget).toSet(),
      {for (var i = 10; i < 20; i++) 'sentence_$i'},
    );
  });

  test('buildReviewSet: sentences reviewed kReviewRetireThreshold+ times are '
      'excluded from the pool', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_retired');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final now = DateTime.now();
    await seed(docDir, dailyReviewCount: 20, records: {
      'fresh': {
        'sentenceInTarget': 'fresh',
        'sentenceInNative': 'n1',
        'firstLearnedAt': now.toIso8601String(),
        'reviewCount': kReviewRetireThreshold - 1,
      },
      'retired': {
        'sentenceInTarget': 'retired',
        'sentenceInNative': 'n2',
        'firstLearnedAt': now.toIso8601String(),
        'reviewCount': kReviewRetireThreshold,
      },
      'over_retired': {
        'sentenceInTarget': 'over_retired',
        'sentenceInNative': 'n3',
        'firstLearnedAt': now.toIso8601String(),
        'reviewCount': kReviewRetireThreshold + 3,
      },
    });

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.map((e) => e.sentenceInTarget), ['fresh']);
  });

  test('buildReviewSet: sentences with no cached audio are excluded', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_nocache');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final now = DateTime.now();
    await seed(docDir, uncached: {'no_audio'}, records: {
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
    });

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, 1);
    expect(result.single.sentenceInTarget, 'has_audio');
  });

  test('buildReviewSet: carries each sentence\'s cumulative reviewCount onto '
      'the ReviewItem', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_count');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final now = DateTime.now();
    await seed(docDir, dailyReviewCount: 20, records: {
      'twice': {
        'sentenceInTarget': 'twice',
        'sentenceInNative': 'n',
        'firstLearnedAt': now.toIso8601String(),
        'reviewCount': 2,
      },
    });

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.single.reviewCount, 2);
  });

  test('rampUpExtraCount: 0 below the threshold, linear in the overshoot above it', () {
    expect(rampUpExtraCount(kReviewRampUpThreshold - 20), 0);
    expect(rampUpExtraCount(kReviewRampUpThreshold - 1), 0);
    expect(rampUpExtraCount(kReviewRampUpThreshold), 0);
    expect(rampUpExtraCount(kReviewRampUpThreshold + 5), 5 * kReviewRampUpSlope);
    expect(
      rampUpExtraCount(kTtsCacheMaxEntries),
      (kTtsCacheMaxEntries - kReviewRampUpThreshold) * kReviewRampUpSlope,
    );
    // Strictly grows as the cache fills further past the threshold.
    expect(
      rampUpExtraCount(kReviewRampUpThreshold + 9) >
          rampUpExtraCount(kReviewRampUpThreshold + 3),
      isTrue,
    );
  });

  test('buildReviewSet: cache below the ramp-up threshold adds no extras — '
      'plain dailyReviewCount size (also how it returns to normal after draining)', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_below_ramp');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    // 40 reviewable records, live cache count pushed to just under 590.
    await seed(
      docDir,
      records: spreadRecords(40),
      dailyReviewCount: 20,
      phantomCacheEntries: (kReviewRampUpThreshold - 5) - 40,
    );

    final result = await ReviewSessionService().buildReviewSet();
    expect(result.length, 20, reason: 'no ramp-up extras below the threshold');
  });

  test('buildReviewSet: cache at/above the threshold appends extras chosen by '
      'most-reviewed-then-oldest', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_ramp_pick');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    // dailyReviewCount 10 => normal selection is deterministic: the 10
    // most-recently-first-learned (s_30..s_39). Live cache = 595 => extra
    // = 5 * slope = 10, taken from the rest by (reviewCount desc, oldest).
    // rest = s_0..s_29; top 10 by that order = s_0..s_9 (reviewCount 6).
    await seed(
      docDir,
      records: bandedRecords(),
      dailyReviewCount: 10,
      phantomCacheEntries: (kReviewRampUpThreshold + 5) - 40,
    );

    final result = await ReviewSessionService().buildReviewSet();
    final got = result.map((e) => e.sentenceInTarget).toSet();

    expect(result.length, 10 + 5 * kReviewRampUpSlope);
    expect(got, {
      for (var i = 0; i < 10; i++) 's_$i', // ramp-up extras (most worn, oldest)
      for (var i = 30; i < 40; i++) 's_$i', // normal 10 most-recent
    });
    // A middle band (reviewCount 1) sentence must NOT have been pulled in.
    expect(got.contains('s_15'), isFalse);
  });

  test('buildReviewSet: the closer the cache is to the cap, the more extras '
      'are added', () async {
    final tempDir = await Directory.systemTemp.createTemp('review_test_ramp_grow');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);

    final records = spreadRecords(40);

    await seed(docDir, records: records, dailyReviewCount: 10, phantomCacheEntries: 592 - 40);
    final near = await ReviewSessionService().buildReviewSet();

    await seed(docDir, records: records, dailyReviewCount: 10, phantomCacheEntries: 599 - 40);
    final full = await ReviewSessionService().buildReviewSet();

    expect(near.length, 10 + (592 - kReviewRampUpThreshold) * kReviewRampUpSlope);
    expect(full.length, 10 + (599 - kReviewRampUpThreshold) * kReviewRampUpSlope);
    expect(full.length, greaterThan(near.length));
  });
}
