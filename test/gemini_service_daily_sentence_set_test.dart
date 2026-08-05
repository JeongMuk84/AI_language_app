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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory appDir(Directory documentsDir) {
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    dir.createSync(recursive: true);
    return dir;
  }

  /// Verifies two things per CEFR level with a mocked Gemini response (no
  /// live network/API key available in this environment):
  /// 1. The actual prompt sent to Gemini varies its target word-count band
  ///    by [difficultyLevel] — this is the fix for `generateNextSentence`
  ///    never having referenced `difficultyLevel` at all.
  /// 2. The response is parsed into a `SentenceQueue` correctly, and the
  ///    per-sentence word counts (logged via `generateDailySentenceSet`'s
  ///    debug log) come back distinct per level.
  Future<void> runLevel({
    required String difficultyLevel,
    required String expectedWordBandInPrompt,
    required int cannedWordCount,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('gemini_daily_set_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.delete(recursive: true));
    final docDir = appDir(tempDir);
    File('${docDir.path}/config.json').writeAsStringSync(
      jsonEncode({
        'nativeLanguage': 'English',
        'targetLanguage': 'Vietnamese',
        'difficultyLevel': difficultyLevel,
      }),
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
      configService: ConfigService(
        storageLocationService: StorageLocationService(),
      ),
    );

    final queue = await gemini.generateDailySentenceSet(
      topicInput: null,
      history: const <ConversationTurn>[],
      difficultyLevel: difficultyLevel,
    );

    expect(capturedPrompt, contains(expectedWordBandInPrompt));
    expect(queue.sentences.length, 10);

    final wordCounts = queue.sentences
        .map((s) => s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length)
        .toList();
    // ignore: avoid_print
    print('[verify] difficultyLevel=$difficultyLevel -> word counts per sentence: $wordCounts');
    expect(wordCounts, everyElement(cannedWordCount));
  }

  test('generateDailySentenceSet: A1 prompt requests short sentences (4-7 words)', () async {
    await runLevel(
      difficultyLevel: 'A1',
      expectedWordBandInPrompt: 'approximately 4-7 words',
      cannedWordCount: 5,
    );
  });

  test('generateDailySentenceSet: B1 prompt requests mid-length sentences (9-14 words)', () async {
    await runLevel(
      difficultyLevel: 'B1',
      expectedWordBandInPrompt: 'approximately 9-14 words',
      cannedWordCount: 11,
    );
  });

  test('generateDailySentenceSet: C1 prompt requests long sentences (15-22 words)', () async {
    await runLevel(
      difficultyLevel: 'C1',
      expectedWordBandInPrompt: 'approximately 15-22 words',
      cannedWordCount: 18,
    );
  });

  test('generateDailySentenceSet: unrecognized level falls back to B1 band (9-14 words)', () async {
    await runLevel(
      difficultyLevel: 'not-a-real-level',
      expectedWordBandInPrompt: 'approximately 9-14 words',
      cannedWordCount: 11,
    );
  });
}
