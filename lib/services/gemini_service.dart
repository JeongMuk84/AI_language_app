import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/learning_constants.dart';
import '../models/conversation_turn.dart';
import '../models/dictation_result.dart';
import '../models/exercise_type.dart';
import '../models/learning_session_snapshot.dart';
import '../models/level_test_question.dart';
import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import '../utils/wav_utils.dart';
import 'api_key_storage_service.dart';
import 'config_service.dart';

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
  GeminiService({
    http.Client? client,
    ApiKeyStorageService? apiKeyStorage,
    ConfigService? configService,
  }) : _client = client ?? http.Client(),
       _apiKeyStorage = apiKeyStorage ?? ApiKeyStorageService(),
       _configService = configService ?? ConfigService();

  static const _model = 'gemini-flash-lite-latest';

  /// Text-to-speech capable model. Returns raw PCM audio inline (see
  /// [synthesizeSpeech]), not a standard container — this is a Gemini API
  /// behavior this app hasn't been able to verify against a live key in
  /// this environment, so the exact response shape is a best-effort guess
  /// based on Gemini's documented TTS response format.
  static const _ttsModel = 'gemini-2.5-flash-preview-tts';

  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  final http.Client _client;
  final ApiKeyStorageService _apiKeyStorage;
  final ConfigService _configService;

  /// Requests currently in flight, keyed by a signature of method+args.
  /// A second call with the same signature while the first is still
  /// pending reuses that same Future instead of firing a duplicate
  /// network request (e.g. a screen's initState racing a rebuild).
  final Map<String, Future<Object?>> _inFlight = {};

  Future<T> _dedupe<T>(String key, Future<T> Function() run) {
    final existing = _inFlight[key];
    if (existing != null) {
      _log('$key: reusing in-flight request');
      return existing.then((value) => value as T);
    }
    final future = run();
    _inFlight[key] = future;
    // `.whenComplete()` returns a distinct Future from `future` itself, so
    // it needs its own error handler — otherwise, whenever `run()` throws,
    // this discarded chain surfaces as an unhandled exception (and crashes
    // the app on desktop) even though the caller's own try/catch on
    // `future` handles the error correctly.
    unawaited(future.then((_) {}, onError: (_) {}).whenComplete(() => _inFlight.remove(key)));
    return future;
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GeminiService] $message');
    }
  }

  Future<GeminiValidationResult> validateApiKey(String apiKey) async {
    return _dedupe('validateApiKey:$apiKey', () async {
      try {
        await _generateText(apiKey, 'ping', label: 'validateApiKey');
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
    });
  }

  Future<List<LevelTestQuestion>> generateLevelTest(
    String nativeLang,
    String targetLang,
  ) async {
    return _dedupe('generateLevelTest:$nativeLang:$targetLang', () async {
      final apiKey = await _requireApiKey();
      final prompt = '''
Write a 10-question placement test for a learner translating between
$nativeLang and $targetLang: 5 questions with "sourceLang":"native"
($nativeLang prompt, translate to $targetLang), 5 with "sourceLang":"target"
($targetLang prompt, translate to $nativeLang). Order easiest to hardest,
mixing both directions. "direction" = short instruction, e.g. "Translate to
$targetLang:".

Return ONLY raw JSON, no markdown fences:
{"questions":[{"prompt":"...","sourceLang":"native|target","direction":"..."}]}
''';
      final text = await _generateText(apiKey, prompt, label: 'generateLevelTest');
      final decoded = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
      final questions = decoded['questions'] as List;
      return questions
          .map((q) => LevelTestQuestion.fromJson(q as Map<String, dynamic>))
          .toList();
    });
  }

  Future<String> evaluateLevelTest({
    required String nativeLang,
    required String targetLang,
    required List<LevelTestQuestion> questions,
    required List<String> answers,
  }) async {
    final transcript = StringBuffer();
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final answer = i < answers.length ? answers[i] : '';
      transcript.writeln('${i + 1}. (${q.sourceLang}) ${q.prompt} -> $answer');
    }
    return _dedupe('evaluateLevelTest:$nativeLang:$targetLang:${transcript.toString().hashCode}', () async {
      final apiKey = await _requireApiKey();
      final prompt = '''
Grade this $nativeLang<->$targetLang placement test (question, then the
learner's answer):

$transcript

Return ONLY a single CEFR level token: A1, A2, B1, B2, C1, or C2. No other
text.
''';
      final text = await _generateText(apiKey, prompt, label: 'evaluateLevelTest');
      return text.trim();
    });
  }

  Future<String> generateHandoffSummary(LearningSessionSnapshot snapshot) async {
    final apiKey = await _requireApiKey();
    final historyText = snapshot.conversationHistory.isEmpty
        ? '(none yet)'
        : snapshot.conversationHistory.map((m) => '${m.role}: ${m.text}').join('\n');
    final prompt = '''
Learner is pausing ${snapshot.targetLanguage} study (native: ${snapshot.nativeLanguage},
level ${snapshot.difficultyLevel ?? 'unknown'}). Session notes:
$historyText

Write a short plain-text handoff (a few sentences, English) so a tutor could
pick up where they left off later. No JSON, no markdown.
''';
    final text = await _generateText(apiKey, prompt, label: 'generateHandoffSummary');
    return text.trim();
  }

  /// Generates the next sentence in the running shadowing/writing session.
  /// [direction] is `'target'` for a target-language sentence (shadowing)
  /// or `'native'` for a native-language sentence (writing). Only the last
  /// [kHistoryContextWindow] turns of [history] are sent as context — the
  /// full session history isn't needed for a natural continuation, and
  /// sending it all would make every prompt bigger as the session grows.
  Future<String> generateNextSentence({
    required String direction,
    required List<ConversationTurn> history,
  }) async {
    final apiKey = await _requireApiKey();
    final config = await _configService.readConfig();
    final nativeLanguage = config.nativeLanguage ?? 'the native language';
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final languageForSentence = direction == 'target' ? targetLanguage : nativeLanguage;

    final recentHistory = history.length > kHistoryContextWindow
        ? history.sublist(history.length - kHistoryContextWindow)
        : history;
    final historyText = recentHistory.isEmpty
        ? '(first sentence — no prior context)'
        : recentHistory
              .map((t) {
                final shown = t.type == ExerciseType.shadowing
                    ? t.sentenceInTarget
                    : t.sentenceInNative;
                return '(${t.type.value}) ${shown ?? ''}';
              })
              .join('\n');

    final exerciseHint = direction == 'target'
        ? 'a dictation exercise (learner listens, then writes what they heard)'
        : 'a writing exercise (learner translates it into $targetLanguage)';

    return _dedupe(
      'generateNextSentence:$direction:${recentHistory.length}:'
      '${recentHistory.isNotEmpty ? recentHistory.last.turnId : 'none'}',
      () async {
        final prompt = '''
Continuing a conversation-style practice session for a learner studying
$targetLanguage (native: $nativeLanguage). Recent lines, in order:
$historyText

Write ONE new sentence ENTIRELY in $languageForSentence that naturally
continues this conversation, suitable for $exerciseHint. IMPORTANT: output
ONLY the $languageForSentence sentence itself — do not translate it, do not
add a $nativeLanguage gloss, do not mix languages. Plain text only — no
quotes, no labels, no markdown.
''';
        final text = await _generateText(apiKey, prompt, label: 'generateNextSentence');
        return text.trim();
      },
    );
  }

  /// Grades a shadowing dictation attempt and, in the same call, returns a
  /// native-language translation and a brief analysis of the sentence —
  /// bundled here rather than as a separate request to avoid doubling the
  /// number of calls per turn.
  Future<DictationResult> validateDictation({
    required String original,
    required String userInput,
  }) async {
    final apiKey = await _requireApiKey();
    final config = await _configService.readConfig();
    final nativeLanguage = config.nativeLanguage ?? 'the native language';
    final targetLanguage = config.targetLanguage ?? 'the target language';
    return _dedupe('validateDictation:$original:$userInput', () async {
      final prompt = '''
Dictation check. The learner is studying $targetLanguage (native language:
$nativeLanguage). The original sentence below is written in $targetLanguage
— it is NOT in the learner's native language.
Original ($targetLanguage): "$original"
Learner wrote: "$userInput"
Judge correctness (minor punctuation/capitalization differences OK, wording
must match). Do NOT echo the original or the learner's answer back in the
JSON — the app already has both; only return the three fields below.

Field-by-field language rules (do not mix these up):
- "feedback": 1-2 sentences on what differs (if anything), written in
  $nativeLanguage.
- "translation": a $nativeLanguage translation of the ORIGINAL ($targetLanguage)
  sentence.
- "analysis": brief notes on key words/structure, written in
  $nativeLanguage, but quote the actual $targetLanguage word or phrase
  first and give its $nativeLanguage meaning in parentheses right after
  (e.g. "간다(khong đi)") — do not paraphrase the $targetLanguage words away
  entirely.

Return ONLY raw JSON, no markdown fences:
{"isCorrect":true|false,
"feedback":"...in $nativeLanguage",
"translation":"...in $nativeLanguage",
"analysis":"...in $nativeLanguage, with $targetLanguage words quoted + gloss in parentheses"}
''';
      final text = await _generateText(apiKey, prompt, label: 'validateDictation');
      final decoded = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
      return DictationResult.fromJson(decoded);
    });
  }

  /// Grades a writing (translation) attempt by meaning rather than exact
  /// wording, and returns a natural model translation for the follow-up
  /// listening/pronunciation exercise.
  Future<TranslationResult> validateTranslation({
    required String nativeSentence,
    required String userTranslation,
  }) async {
    final apiKey = await _requireApiKey();
    final config = await _configService.readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final nativeLanguage = config.nativeLanguage ?? 'the native language';
    return _dedupe('validateTranslation:$nativeSentence:$userTranslation', () async {
      final prompt = '''
Translation check. The learner is translating FROM $nativeLanguage TO
$targetLanguage.
Native ($nativeLanguage) sentence given to the learner: "$nativeSentence"
Learner's $targetLanguage translation attempt: "$userTranslation"

Judge by MEANING, not exact wording — accept any natural, correct
translation. Note grammar/word-choice issues in the feedback. Do NOT echo
the native sentence or the learner's attempt back in the JSON — the app
already has both; only return the two fields below.

Field-by-field language rules (do not mix these up):
- "feedback": 1-2 sentences on grammar/wording, written in $nativeLanguage.
- "referenceTranslation": a natural, correct translation of the native
  sentence, written ENTIRELY in $targetLanguage. This is the exact sentence
  the learner will read/say aloud next — it must be the translated
  sentence itself, NOT a $nativeLanguage explanation of it.

Return ONLY raw JSON, no markdown fences:
{"isCorrect":true|false,"feedback":"1-2 sentences in $nativeLanguage on grammar/wording",
"referenceTranslation":"a natural, correct $targetLanguage translation"}
''';
      final text = await _generateText(apiKey, prompt, label: 'validateTranslation');
      final decoded = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
      return TranslationResult.fromJson(decoded);
    });
  }

  /// Sends a recorded pronunciation attempt to Gemini for multimodal
  /// analysis against [targetSentence].
  Future<PronunciationResult> analyzePronunciation({
    required Uint8List audioBytes,
    required String targetSentence,
  }) async {
    final config = await _configService.readConfig();
    final nativeLanguage = config.nativeLanguage ?? 'the native language';
    final targetLanguage = config.targetLanguage ?? 'the target language';
    return _dedupe('analyzePronunciation:$targetSentence:${audioBytes.length}', () async {
      final apiKey = await _requireApiKey();
      final prompt = '''
Learner recorded themselves saying this $targetLanguage sentence aloud:
"$targetSentence"
Listen to the recording, transcribe what they actually said, and assess how
closely it matches the target sentence.

Field-by-field language rules (do not mix these up):
- "recognizedText": transcribe exactly what you heard, written in
  $targetLanguage — the language they were speaking. Do NOT translate it
  into $nativeLanguage; the learner needs to see what their pronunciation
  actually sounded like, in the language they were practicing.
- "feedback": your assessment/notes, written in $nativeLanguage (the
  learner's native language), not English unless $nativeLanguage is
  English. If accuracyPercent is below $kPronunciationPassThreshold,
  briefly and encouragingly note (still in $nativeLanguage) that they
  should try again; otherwise don't mention the threshold at all.

Return ONLY raw JSON, no markdown fences:
{"recognizedText":"...in $targetLanguage, transcribing what you heard",
"feedback":"a few sentences in $nativeLanguage on pronunciation notes",
"accuracyPercent":0-100 estimate of how closely it matches the target sentence}
''';
      _log('analyzePronunciation: prompt ~${prompt.length} chars + audio ${audioBytes.length}B');
      final decoded = await _generateContent(apiKey, [
        {'text': prompt},
        {
          'inlineData': {'mimeType': 'audio/wav', 'data': base64Encode(audioBytes)},
        },
      ]);
      final text = _extractText(decoded);
      final json = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
      return PronunciationResult.fromJson(json);
    });
  }

  /// Synthesizes [text] to speech and returns playable WAV bytes.
  ///
  /// Not verified against a live Gemini API key in this environment — the
  /// TTS response is documented to return raw PCM inline audio, which this
  /// wraps in a WAV header (see [pcm16ToWav]) so `audioplayers` can play
  /// it directly from memory. If Gemini's actual response shape differs,
  /// adjust the parsing here.
  Future<Uint8List> synthesizeSpeech(String text) async {
    return _dedupe('synthesizeSpeech:$text', () async {
      final apiKey = await _requireApiKey();
      final decoded = await _generateContent(
        apiKey,
        [
          {'text': text},
        ],
        model: _ttsModel,
        generationConfig: {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': 'Kore'},
            },
          },
        },
        label: 'synthesizeSpeech',
      );

      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw GeminiApiException(GeminiFailureReason.other, 'Gemini returned no audio.');
      }
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      final inlineData = parts
          ?.whereType<Map<String, dynamic>>()
          .map((p) => p['inlineData'] as Map<String, dynamic>?)
          .firstWhere((d) => d != null, orElse: () => null);
      if (inlineData == null) {
        throw GeminiApiException(GeminiFailureReason.other, 'Gemini returned no audio data.');
      }

      final base64Data = inlineData['data'] as String? ?? '';
      final mimeType = inlineData['mimeType'] as String? ?? 'audio/L16;rate=24000';
      final pcmBytes = base64Decode(base64Data);
      final sampleRate = _parseSampleRate(mimeType) ?? 24000;
      return pcm16ToWav(pcmBytes, sampleRate: sampleRate);
    });
  }

  int? _parseSampleRate(String mimeType) {
    final match = RegExp(r'rate=(\d+)').firstMatch(mimeType);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<String> _requireApiKey() async {
    final apiKey = await _apiKeyStorage.readApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw GeminiApiException(GeminiFailureReason.authError, 'No API key configured.');
    }
    return apiKey;
  }

  Future<String> _generateText(String apiKey, String prompt, {required String label}) async {
    final decoded = await _generateContent(apiKey, [
      {'text': prompt},
    ], label: label);
    return _extractText(decoded);
  }

  Future<Map<String, dynamic>> _generateContent(
    String apiKey,
    List<Map<String, dynamic>> parts, {
    String? model,
    Map<String, dynamic>? generationConfig,
    String label = 'generateContent',
  }) async {
    final promptChars = parts
        .map((p) => (p['text'] as String?)?.length ?? 0)
        .fold<int>(0, (a, b) => a + b);
    _log('$label -> ${model ?? _model} (~$promptChars prompt chars)');

    final uri = Uri.parse('$_baseUrl/${model ?? _model}:generateContent?key=$apiKey');
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {'parts': parts},
              ],
              'generationConfig': ?generationConfig,
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
      _log('$label <- HTTP ${response.statusCode}');
      throw GeminiApiException(_reasonForStatusCode(response.statusCode), response.body);
    }
    _log('$label <- OK');

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractText(Map<String, dynamic> decoded) {
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
