import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/learning_session_snapshot.dart';
import '../models/level_test_question.dart';
import 'api_key_storage_service.dart';

/// Classification of why a Gemini call failed, used to pick a
/// user-facing message and to decide how the UI should react.
enum GeminiFailureReason { authError, network, rateLimit, other }

/// Turns a [GeminiFailureReason] into an English message a user can act on.
String userMessageForFailure(GeminiFailureReason reason, [String? rawError]) {
  switch (reason) {
    case GeminiFailureReason.authError:
      return 'This API key was rejected. Please check that you copied it '
          'correctly, or generate a new key.';
    case GeminiFailureReason.network:
      return 'Could not reach Gemini. Please check your internet connection '
          'and try again.';
    case GeminiFailureReason.rateLimit:
      return 'This key has hit its usage limit. Please wait a moment and '
          'try again.';
    case GeminiFailureReason.other:
      return rawError == null || rawError.isEmpty
          ? 'Something went wrong. Please try again.'
          : 'Something went wrong: $rawError';
  }
}

class GeminiValidationResult {
  const GeminiValidationResult.success()
      : success = true,
        reason = null,
        rawError = null;

  const GeminiValidationResult.failure(this.reason, [this.rawError]) : success = false;

  final bool success;
  final GeminiFailureReason? reason;
  final String? rawError;
}

/// Thrown by [GeminiService] calls other than [GeminiService.validateApiKey],
/// which report failure via a result object instead.
class GeminiApiException implements Exception {
  GeminiApiException(this.reason, this.message);

  final GeminiFailureReason reason;
  final String message;

  @override
  String toString() => 'GeminiApiException($reason, $message)';
}

/// Calls the Gemini REST API directly over `http` (no SDK package).
class GeminiService {
  GeminiService({http.Client? client, ApiKeyStorageService? apiKeyStorage})
      : _client = client ?? http.Client(),
        _apiKeyStorage = apiKeyStorage ?? ApiKeyStorageService();

  static const _model = 'gemini-flash-lite-latest';
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  final http.Client _client;
  final ApiKeyStorageService _apiKeyStorage;

  Future<GeminiValidationResult> validateApiKey(String apiKey) async {
    try {
      await _generateText(apiKey, 'ping');
      return const GeminiValidationResult.success();
    } on GeminiApiException catch (e) {
      return GeminiValidationResult.failure(e.reason, e.message);
    } on TimeoutException catch (e) {
      return GeminiValidationResult.failure(GeminiFailureReason.network, e.toString());
    } on SocketException catch (e) {
      return GeminiValidationResult.failure(GeminiFailureReason.network, e.toString());
    } on http.ClientException catch (e) {
      return GeminiValidationResult.failure(GeminiFailureReason.network, e.toString());
    } catch (e) {
      return GeminiValidationResult.failure(GeminiFailureReason.other, e.toString());
    }
  }

  Future<List<LevelTestQuestion>> generateLevelTest(
    String nativeLang,
    String targetLang,
  ) async {
    final apiKey = await _requireApiKey();
    final prompt = '''
Generate a language placement test with exactly 10 questions to assess a
learner's ability to translate between $nativeLang and $targetLang.

- Exactly 5 questions must have "sourceLang": "native" — the "prompt" sentence
  is written in $nativeLang, and the learner will translate it into $targetLang.
- Exactly 5 questions must have "sourceLang": "target" — the "prompt" sentence
  is written in $targetLang, and the learner will translate it into $nativeLang.
- Order the 10 questions from easiest to hardest, mixing both directions
  throughout rather than grouping them.
- "direction" should be a short instruction for the learner, e.g.
  "Translate to $targetLang:" or "Translate to $nativeLang:".

Return ONLY raw JSON with no markdown code fences and no extra explanation,
matching exactly this schema:
{
  "questions": [
    { "prompt": "sentence to display", "sourceLang": "native | target", "direction": "short instruction" }
  ]
}
''';
    final text = await _generateText(apiKey, prompt);
    final decoded = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
    final questions = decoded['questions'] as List;
    return questions
        .map((q) => LevelTestQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  Future<String> evaluateLevelTest({
    required String nativeLang,
    required String targetLang,
    required List<LevelTestQuestion> questions,
    required List<String> answers,
  }) async {
    final apiKey = await _requireApiKey();
    final transcript = StringBuffer();
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final answer = i < answers.length ? answers[i] : '';
      transcript
        ..writeln('${i + 1}. (${q.sourceLang}) ${q.prompt}')
        ..writeln('   Instruction: ${q.direction}')
        ..writeln('   Learner answer: $answer');
    }
    final prompt = '''
You are grading a language learner's placement test between $nativeLang and
$targetLang. Below are 10 translation questions and the learner's answers.

$transcript

Assess the learner's overall proficiency across all 10 answers and return
ONLY a single CEFR level token: one of A1, A2, B1, B2, C1, C2. Return raw
text only — no explanation, no punctuation, no JSON.
''';
    final text = await _generateText(apiKey, prompt);
    return text.trim();
  }

  Future<String> generateHandoffSummary(LearningSessionSnapshot snapshot) async {
    final apiKey = await _requireApiKey();
    final historyText = snapshot.conversationHistory.isEmpty
        ? '(No recorded session notes yet.)'
        : snapshot.conversationHistory.map((m) => '${m.role}: ${m.text}').join('\n');
    final prompt = '''
A language learner is switching away from studying ${snapshot.targetLanguage}
(their native language is ${snapshot.nativeLanguage}). Their current level in
${snapshot.targetLanguage} is ${snapshot.difficultyLevel ?? 'unknown'}.

Session notes so far:
$historyText

Write a short handoff summary in English (a few plain-text sentences) that
captures where this learner left off in ${snapshot.targetLanguage}, so that
if they resume studying it later, a tutor could pick up right where they
stopped. Mention their level and anything notable from the session notes.
Return plain text only — no JSON, no markdown, no headings.
''';
    final text = await _generateText(apiKey, prompt);
    return text.trim();
  }

  Future<String> _requireApiKey() async {
    final apiKey = await _apiKeyStorage.readApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw GeminiApiException(GeminiFailureReason.authError, 'No API key configured.');
    }
    return apiKey;
  }

  Future<String> _generateText(String apiKey, String prompt) async {
    final uri = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw GeminiApiException(GeminiFailureReason.network, 'Request timed out.');
    } on SocketException catch (e) {
      throw GeminiApiException(GeminiFailureReason.network, e.toString());
    } on http.ClientException catch (e) {
      throw GeminiApiException(GeminiFailureReason.network, e.toString());
    }

    if (response.statusCode != 200) {
      throw GeminiApiException(_reasonForStatusCode(response.statusCode), response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw GeminiApiException(GeminiFailureReason.other, 'Gemini returned no candidates.');
    }
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw GeminiApiException(GeminiFailureReason.other, 'Gemini returned no content.');
    }
    return parts.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '').join();
  }

  GeminiFailureReason _reasonForStatusCode(int statusCode) {
    if (statusCode == 401 || statusCode == 403) return GeminiFailureReason.authError;
    if (statusCode == 429) return GeminiFailureReason.rateLimit;
    return GeminiFailureReason.other;
  }

  String _stripCodeFences(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      if (t.endsWith('```')) {
        t = t.substring(0, t.length - 3);
      }
    }
    return t.trim();
  }
}
