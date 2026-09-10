import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_language_app/constants/app_identity.dart';
import 'package:ai_language_app/models/pronunciation_result.dart';
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

/// Builds a fake Gemini `generateContent` response wrapping [innerJson] the
/// same way the real API wraps generated text.
String _wrapAsGeminiResponse(Map<String, dynamic> innerJson) {
  return jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': jsonEncode(innerJson)},
          ],
        },
      },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory appDir(Directory documentsDir) {
    final dir = Directory('${documentsDir.path}/$kAppFolderName');
    dir.createSync(recursive: true);
    return dir;
  }

  /// Verifies, with a mocked Gemini response (no live network/API key/mic
  /// available in this environment), that `analyzePronunciation`:
  /// 1. Sends a prompt that actually asks for the two-step
  ///    transcribe-then-compare schema (STEP 1/STEP 2, noSpeechDetected,
  ///    matchPercentage, and the anti-verbatim-fallback instruction).
  /// 2. Correctly parses whatever [mockedRecognizedText]/[mockedMatch]/
  ///    [mockedNoSpeech] Gemini claims to have transcribed/scored into the
  ///    resulting [PronunciationResult] — i.e. the wire contract
  ///    (`matchPercentage` -> `accuracyPercent`) is wired correctly end to
  ///    end. This does not (and cannot, without a live mic + API key)
  ///    verify Gemini's actual transcription judgment quality — that's the
  ///    part only a real recording can exercise.
  Future<void> runScenario({
    required String label,
    required String targetSentence,
    required String mockedRecognizedText,
    required bool mockedNoSpeech,
    required num mockedMatch,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('gemini_pronunciation_test');
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
      return http.Response(
        _wrapAsGeminiResponse({
          'recognizedText': mockedRecognizedText,
          'noSpeechDetected': mockedNoSpeech,
          'matchPercentage': mockedMatch,
          'feedback': 'mock feedback',
        }),
        200,
        // Vietnamese sentences in the mocked body aren't representable in
        // Latin1 (http.Response's default) - without this, Response's
        // constructor throws before the test even reaches GeminiService.
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final gemini = GeminiService(
      client: mockClient,
      apiKeyStorage: _FakeApiKeyStorageService(),
      configService: ConfigService(storageLocationService: StorageLocationService()),
    );

    // Fake WAV bytes - content doesn't matter here, only that the prompt
    // and response-parsing plumbing work end to end.
    final audioBytes = Uint8List.fromList(List.filled(4000, 1));
    final result = await gemini.analyzePronunciation(
      audioBytes: audioBytes,
      targetSentence: targetSentence,
    );

    // Prompt actually asks for the two-step schema, not a one-shot
    // audio-vs-target judgement - this is the fix for the original bug
    // (silence scoring 100% because there was nothing concrete to compare
    // against).
    expect(capturedPrompt, contains('STEP 1'));
    expect(capturedPrompt, contains('STEP 2'));
    expect(capturedPrompt, contains('noSpeechDetected'));
    expect(capturedPrompt, contains('matchPercentage'));
    expect(capturedPrompt, contains('strictly forbidden'));

    // ignore: avoid_print
    print(
      '[verify:$label] target="$targetSentence" -> '
      'recognizedText="${result.recognizedText}", accuracyPercent=${result.accuracyPercent}',
    );
    expect(result.recognizedText, mockedRecognizedText);
    expect(result.accuracyPercent, mockedMatch.toDouble());
  }

  test(
    '무음/잡음: Gemini가 noSpeechDetected+빈 recognizedText+matchPercentage 0을 '
    '반환하면 PronunciationResult도 그대로 0%/빈 텍스트로 파싱된다',
    () async {
      await runScenario(
        label: 'silence',
        targetSentence: 'Tôi thích học tiếng Việt.',
        mockedRecognizedText: '',
        mockedNoSpeech: true,
        mockedMatch: 0,
      );
    },
  );

  test(
    '오발음/누락: recognizedText가 원문과 다르게(단어 누락) 돌아오면 '
    '원문으로 대체되지 않고 그 차이가 그대로 노출된다',
    () async {
      const target = 'Tôi thích học tiếng Việt mỗi ngày.';
      // Learner dropped "mỗi ngày" (every day) - the mocked transcript
      // reflects that omission instead of echoing the full target back.
      const heard = 'Tôi thích học tiếng Việt.';
      await runScenario(
        label: 'mispronounced/dropped-word',
        targetSentence: target,
        mockedRecognizedText: heard,
        mockedNoSpeech: false,
        mockedMatch: 55,
      );
    },
  );

  test('정상 발음: recognizedText가 원문과 일치하면 높은 matchPercentage가 그대로 전달된다', () async {
    const target = 'Xin chào, bạn khỏe không?';
    await runScenario(
      label: 'accurate',
      targetSentence: target,
      mockedRecognizedText: target,
      mockedNoSpeech: false,
      mockedMatch: 97,
    );
  });

  test(
    'PronunciationResult.fromJson: Gemini 응답의 matchPercentage 키를 '
    'accuracyPercent로 읽어온다',
    () {
      final result = PronunciationResult.fromJson({
        'recognizedText': 'xin chào',
        'noSpeechDetected': false,
        'matchPercentage': 72,
        'feedback': 'ok',
      });
      expect(result.recognizedText, 'xin chào');
      expect(result.accuracyPercent, 72.0);
    },
  );

  test(
    'PronunciationResult.noSpeechDetected: 클라이언트 측 무음 감지(진폭 기반, API 호출 없음) '
    '결과가 Gemini의 noSpeechDetected 응답과 동일한 모양(빈 텍스트, 0점)이다',
    () {
      final result = PronunciationResult.noSpeechDetected();
      expect(result.recognizedText, isEmpty);
      expect(result.accuracyPercent, 0);
    },
  );
}
