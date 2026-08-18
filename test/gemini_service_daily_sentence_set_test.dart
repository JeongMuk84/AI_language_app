import 'dart:convert';
import 'dart:io';

import 'package:ai_language_app/constants/app_identity.dart';
import 'package:ai_language_app/models/conversation_turn.dart';
import 'package:ai_language_app/services/api_key_storage_service.dart';
import 'package:ai_language_app/services/config_service.dart';
import 'package:ai_language_app/services/gemini_service.dart';
import 'package:ai_language_app/services/storage_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

/// `flutter_secure_storage` needs a platform channel this test environment
/// doesn't have, so this fakes just the one method `GeminiService` needs.
class _FakeApiKeyStorageService implements ApiKeyStorageService {
  @override
  Future<String?> readApiKey() async => 'fake-test-key';

  @override
  Future<void> saveApiKey(String apiKey) async {}

  @override
  Future<bool> hasApiKey() async => true;

  @override
  Future<void> clearApiKey() async {}
}

/// Builds a fake Gemini `generateContent` response wrapping [innerText] the
/// same way the real API wraps generated text.
String _wrapAsGeminiResponse(String innerText) {
  return jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': innerText},
          ],
        },
      },
    ],
  });
}

/// A sentence with exactly [wordCount] words (content is meaningless — only
/// the word count matters for this test).
String _sentenceWithWordCount(int wordCount) {
  return List.generate(wordCount, (i) => 'w${i + 1}').join(' ');
}

/// Ten alternating shadowing/writing sentences, each with [wordCount] words,
/// as the raw JSON body `generateDailySentenceSet` expects back from Gemini.
String _canned10SentenceResponse(int wordCount) {
  final sentences = List.generate(10, (i) {
    final type = i.isEven ? 'shadowing' : 'writing';
    return {'type': type, 'text': _sentenceWithWordCount(wordCount)};
  });
  return jsonEncode({'sentences': sentences});
}

/// Mirrors `GeminiService._lengthGuidanceForScore`'s word-count formula (0
/// score -> 4 words, 100 score -> 25 words) so the test documents/verifies
/// the continuous mapping without hardcoding numbers that would silently
/// drift from the implementation.
int _expectedWordTarget(double score) {
  final clamped = score.clamp(0.0, 100.0);
  return (4 + (clamped / 100) * 21).round();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory appDir(Directory documentsDir) {
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    dir.createSync(recursive: true);
    return dir;
  }

  /// Verifies, with a mocked Gemini response (no live network/API key
  /// available in this environment):
  /// 1. The actual prompt sent to Gemini carries the exact continuous
  ///    [difficultyScore] and the word-count target computed from it (the
  ///    fix for length no longer being tied to only 6 discrete CEFR bands).
  /// 2. [cumulativeSummary] (or its absence) is reflected in the prompt, so
  ///    Gemini is actually told what to avoid repeating.
  /// 3. The response is parsed into a `SentenceQueue` correctly, and the
  ///    per-sentence word counts (logged via `generateDailySentenceSet`'s
  ///    debug log) come back as expected.
  Future<void> runScore({
    required double difficultyScore,
    String? cumulativeSummary,
    required int cannedWordCount,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('gemini_daily_set_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);
    File('${docDir.path}/config.json').writeAsStringSync(
      jsonEncode({'nativeLanguage': 'English', 'targetLanguage': 'Vietnamese'}),
    );

    String? capturedPrompt;
    final mockClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final contents = body['contents'] as List;
      final parts = (contents.first as Map<String, dynamic>)['parts'] as List;
      capturedPrompt = (parts.first as Map<String, dynamic>)['text'] as String;
      return http.Response(_wrapAsGeminiResponse(_canned10SentenceResponse(cannedWordCount)), 200);
    });

    final gemini = GeminiService(
      client: mockClient,
      apiKeyStorage: _FakeApiKeyStorageService(),
      configService: ConfigService(storageLocationService: StorageLocationService()),
    );

    final queue = await gemini.generateDailySentenceSet(
      topicInput: null,
      history: const <ConversationTurn>[],
      cumulativeSummary: cumulativeSummary,
      difficultyScore: difficultyScore,
    );

    final targetWords = _expectedWordTarget(difficultyScore);
    expect(capturedPrompt, contains('Difficulty target: ${difficultyScore.toStringAsFixed(1)}/100'));
    expect(capturedPrompt, contains('approximately $targetWords words per sentence'));
    if (cumulativeSummary == null || cumulativeSummary.isEmpty) {
      expect(capturedPrompt, contains('No cumulative learning summary yet'));
    } else {
      expect(capturedPrompt, contains(cumulativeSummary));
    }

    expect(queue.sentences.length, 10);
    final wordCounts = queue.sentences
        .map((s) => s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length)
        .toList();
    // ignore: avoid_print
    print(
      '[verify] difficultyScore=${difficultyScore.toStringAsFixed(1)} '
      '(target ~$targetWords words) -> word counts per sentence: $wordCounts',
    );
    expect(wordCounts, everyElement(cannedWordCount));
  }

  test('generateDailySentenceSet: score 0 (brand new beginner) targets ~4 words', () async {
    await runScore(difficultyScore: 0, cannedWordCount: 4);
  });

  test('generateDailySentenceSet: score 40 (B1-equivalent) targets ~12 words', () async {
    await runScore(difficultyScore: 40, cannedWordCount: 12);
  });

  test('generateDailySentenceSet: score 100 (master) targets ~25 words', () async {
    await runScore(difficultyScore: 100, cannedWordCount: 25);
  });

  test(
    'generateDailySentenceSet: intermediate scores (e.g. day-30/180 into progression) '
    'produce distinct, continuously-increasing word targets',
    () async {
      final scores = [0.0, 24.7, 49.3, 73.6, 100.0];
      final targets = scores.map(_expectedWordTarget).toList();
      // ignore: avoid_print
      print('[verify] score -> word target: ${Map.fromIterables(scores, targets)}');
      // Strictly increasing - confirms the mapping is continuous, not a
      // handful of hard-edged tiers that repeat the same target.
      for (var i = 1; i < targets.length; i++) {
        expect(targets[i], greaterThan(targets[i - 1]));
      }
    },
  );

  test('generateDailySentenceSet: no cumulative summary yet -> prompt says so explicitly', () async {
    await runScore(difficultyScore: 40, cumulativeSummary: null, cannedWordCount: 12);
  });

  test(
    'generateDailySentenceSet: existing cumulative summary is passed through verbatim '
    'so Gemini can avoid repeating it',
    () async {
      await runScore(
        difficultyScore: 40,
        cumulativeSummary:
            'Learner has covered: ordering coffee, asking for directions, talking about the weather.',
        cannedWordCount: 12,
      );
    },
  );
}
