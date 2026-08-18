import 'dart:convert';
import 'dart:io';

import 'package:ai_language_app/constants/app_identity.dart';
import 'package:ai_language_app/services/config_service.dart';
import 'package:ai_language_app/services/day_boundary_service.dart';
import 'package:ai_language_app/services/difficulty_progression_service.dart';
import 'package:ai_language_app/services/storage_location_service.dart';
import 'package:ai_language_app/utils/language_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:timezone/data/latest.dart' as tz_data;

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

/// Mirrors `DifficultyProgressionService.readTodayScore`'s formula so the
/// test documents/verifies it without hardcoding numbers that could
/// silently drift from the implementation.
double _expectedScore({required double initialScore, required int elapsedDays}) {
  final progressRatio = (elapsedDays / 365).clamp(0.0, 1.0);
  return initialScore + (100 - initialScore) * progressRatio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  Directory appDir(Directory documentsDir) {
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> setUpAppDir() async {
    final tempDir = await Directory.systemTemp.createTemp('difficulty_progression_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    return appDir(tempDir);
  }

  void writeConfig(Directory docDir, {required String targetLanguage, String? difficultyLevel}) {
    File('${docDir.path}/config.json').writeAsStringSync(
      jsonEncode({
        'nativeLanguage': 'English',
        'targetLanguage': targetLanguage,
        'difficultyLevel': ?difficultyLevel,
      }),
    );
  }

  void seedProgression(
    Directory docDir, {
    required String targetLanguage,
    required DateTime startDate,
    required double initialScore,
  }) {
    final key = languageStorageKey(targetLanguage);
    final dir = Directory('${docDir.path}/difficulty_progression/$key')..createSync(recursive: true);
    File('${dir.path}/progression.json').writeAsStringSync(
      jsonEncode({'startDate': startDate.toIso8601String(), 'initialScore': initialScore}),
    );
  }

  DifficultyProgressionService buildService() {
    final storageLocationService = StorageLocationService();
    return DifficultyProgressionService(
      storageLocationService: storageLocationService,
      configService: ConfigService(storageLocationService: storageLocationService),
      dayBoundaryService: DayBoundaryService(),
    );
  }

  test('readTodayScore: no progression yet -> initializes from CEFR-mapped start score, day 0', () async {
    final docDir = await setUpAppDir();
    writeConfig(docDir, targetLanguage: 'Vietnamese', difficultyLevel: 'A1');

    final score = await buildService().readTodayScore();

    // Freshly initialized today (elapsedDays == 0) -> score == initialScore
    // for A1 (0).
    expect(score, 0);

    final saved = jsonDecode(
      File(
        '${docDir.path}/difficulty_progression/${languageStorageKey('Vietnamese')}/progression.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(saved['initialScore'], 0);
  });

  test('readTodayScore: 30 days elapsed produces a small, still-early score', () async {
    final docDir = await setUpAppDir();
    writeConfig(docDir, targetLanguage: 'Vietnamese', difficultyLevel: 'A1');
    final startDate = DateTime.now().subtract(const Duration(days: 30));
    seedProgression(docDir, targetLanguage: 'Vietnamese', startDate: startDate, initialScore: 0);

    final score = await buildService().readTodayScore();
    final expected = _expectedScore(initialScore: 0, elapsedDays: 30);

    // ignore: avoid_print
    print('[verify] 30 days elapsed (A1 start=0) -> score=$score (expected ~$expected)');
    expect(score, closeTo(expected, 0.5));
    expect(score, lessThan(10)); // "체감상 거의 못 느낄 정도로 미세" — still barely moved.
  });

  test('readTodayScore: 180 days elapsed produces a meaningfully higher score than 30 days', () async {
    final docDir = await setUpAppDir();
    writeConfig(docDir, targetLanguage: 'Vietnamese', difficultyLevel: 'A1');
    final startDate = DateTime.now().subtract(const Duration(days: 180));
    seedProgression(docDir, targetLanguage: 'Vietnamese', startDate: startDate, initialScore: 0);

    final score = await buildService().readTodayScore();
    final expected = _expectedScore(initialScore: 0, elapsedDays: 180);

    // ignore: avoid_print
    print('[verify] 180 days elapsed (A1 start=0) -> score=$score (expected ~$expected)');
    expect(score, closeTo(expected, 0.5));
    expect(score, closeTo(49.3, 1)); // 180/365 * 100 ~= 49.3
  });

  test('readTodayScore: 400 days elapsed (over a year) clamps to the master score (100)', () async {
    final docDir = await setUpAppDir();
    writeConfig(docDir, targetLanguage: 'Vietnamese', difficultyLevel: 'A1');
    final startDate = DateTime.now().subtract(const Duration(days: 400));
    seedProgression(docDir, targetLanguage: 'Vietnamese', startDate: startDate, initialScore: 0);

    final score = await buildService().readTodayScore();

    // ignore: avoid_print
    print('[verify] 400 days elapsed (>365) -> score=$score (expect exactly 100, clamped)');
    expect(score, 100);
  });

  test(
    'readTodayScore: a higher CEFR starting level (e.g. C1=80) needs less runway to reach '
    'the same score as a beginner further along',
    () async {
      final docDir = await setUpAppDir();
      writeConfig(docDir, targetLanguage: 'Vietnamese', difficultyLevel: 'C1');
      final startDate = DateTime.now().subtract(const Duration(days: 30));
      seedProgression(docDir, targetLanguage: 'Vietnamese', startDate: startDate, initialScore: 80);

      final score = await buildService().readTodayScore();
      final expected = _expectedScore(initialScore: 80, elapsedDays: 30);

      // ignore: avoid_print
      print('[verify] 30 days elapsed (C1 start=80) -> score=$score (expected ~$expected)');
      expect(score, closeTo(expected, 0.5));
      expect(score, greaterThan(80));
      expect(score, lessThan(82)); // still barely moved off the C1 start point.
    },
  );

  test(
    'readTodayScore: switching target language keeps each language\'s progression independent '
    'and continuous (Vietnamese progress is untouched by studying Spanish)',
    () async {
      final docDir = await setUpAppDir();

      // Vietnamese: 180 days into progression from A1.
      seedProgression(
        docDir,
        targetLanguage: 'Vietnamese',
        startDate: DateTime.now().subtract(const Duration(days: 180)),
        initialScore: 0,
      );

      // Switch to Spanish (brand new language, day 0, fresh B1 level test).
      writeConfig(docDir, targetLanguage: 'Spanish', difficultyLevel: 'B1');
      final spanishScore = await buildService().readTodayScore();
      expect(spanishScore, 40); // Day 0 for Spanish -> exactly its initial (B1) score.

      // Switch back to Vietnamese - its 180-day progress must still be there,
      // not reset by having studied Spanish in between.
      writeConfig(docDir, targetLanguage: 'Vietnamese', difficultyLevel: 'A1');
      final vietnameseScore = await buildService().readTodayScore();
      final expectedVietnamese = _expectedScore(initialScore: 0, elapsedDays: 180);

      // ignore: avoid_print
      print(
        '[verify] language switch continuity -> Spanish(day0)=$spanishScore, '
        'Vietnamese(day180, resumed)=$vietnameseScore (expected ~$expectedVietnamese)',
      );
      expect(vietnameseScore, closeTo(expectedVietnamese, 0.5));
      expect(vietnameseScore, greaterThan(40)); // resumed, not reset to 0.
    },
  );
}
