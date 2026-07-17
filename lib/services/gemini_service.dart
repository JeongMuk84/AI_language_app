import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/learning_constants.dart';
import '../constants/tts_voices.dart';
import '../models/conversation_turn.dart';
import '../models/dictation_result.dart';
import '../models/exercise_type.dart';
import '../models/learning_session_snapshot.dart';
import '../models/level_test_question.dart';
import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import '../models/word_lookup_result.dart';
import '../utils/wav_utils.dart';
import 'api_key_storage_service.dart';
import 'config_service.dart';
import 'tts_cache_service.dart';

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
    TtsCacheService? ttsCacheService,
  }) : _client = client ?? http.Client(),
       _apiKeyStorage = apiKeyStorage ?? ApiKeyStorageService(),
       _configService = configService ?? ConfigService(),
       _ttsCache = ttsCacheService ?? TtsCacheService();

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
  final TtsCacheService _ttsCache;

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
        ? '(first sentence - no prior context)'
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
ONLY the $languageForSentence sentence itself - do not translate it, do not
add a $nativeLanguage gloss, do not mix languages. Plain text only - no
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
- it is NOT in the learner's native language.
Original ($targetLanguage): "$original"
Learner wrote: "$userInput"
Judge correctness (minor punctuation/capitalization differences OK, wording
must match). Do NOT echo the original or the learner's answer back in the
JSON - the app already has both; only return the fields below.

ERRORS: if anything the learner wrote differs from the original - wrong
word, misspelling, wrong spacing, or (for languages that use them) a wrong
tone/diacritic mark - you MUST report it as a structured entry in "errors".
NEVER give a vague statement like "there's a typo" with nothing else -
every issue needs exactly what the learner wrote, what it should be, and
why. Tone/diacritic mark mistakes are NOT minor: in a tonal language a
single wrong mark changes the meaning entirely, so name precisely which
mark goes where. If there are several separate issues, report each as its
own "errors" entry. Each entry's "shouldBe" is ONLY the corrected word/
phrase for that specific issue, never the full original sentence. If
nothing is wrong, return an empty array - do not invent problems that
aren't there.

Field-by-field language rules (do not mix these up):
- "feedback": 1-2 sentences of overall comment, written in $nativeLanguage.
  Point-by-point corrections go in "errors" below, not crammed in here.
- "translation": a $nativeLanguage translation of the ORIGINAL ($targetLanguage)
  sentence.
- "analysis": brief notes on key words/structure, written in
  $nativeLanguage, but quote the actual $targetLanguage word or phrase
  first and give its $nativeLanguage meaning in parentheses right after
  (e.g. "간다(khong đi)") - do not paraphrase the $targetLanguage words away
  entirely.
- "errors[].userWrote": the exact $targetLanguage word/phrase the learner
  wrote wrong, quoted verbatim.
- "errors[].shouldBe": the corrected word/phrase ONLY (not the full
  sentence), written in $targetLanguage.
- "errors[].explanation": why, written in $nativeLanguage - for tone/
  diacritic mistakes, name the specific mark and where it belongs.

Return ONLY raw JSON, no markdown fences:
{"isCorrect":true|false,
"feedback":"1-2 sentences in $nativeLanguage, overall comment only",
"translation":"...in $nativeLanguage",
"analysis":"...in $nativeLanguage, with $targetLanguage words quoted + gloss in parentheses",
"errors":[{"userWrote":"...exactly as written, in $targetLanguage","shouldBe":"...corrected word/phrase only, in $targetLanguage","explanation":"...in $nativeLanguage"}]}
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
Learner's attempt: "$userTranslation"

IMPORTANT: the learner's attempt may mix languages - they write the parts
they know in $targetLanguage and fall back to $nativeLanguage for words or
phrases they don't know yet (e.g. a $nativeLanguage speaker learning
Vietnamese might write "Tôi muốn 예약하다 nhà hàng", mixing $nativeLanguage
into an otherwise $targetLanguage sentence). This is expected learning
behavior, not an error: a $nativeLanguage segment means "the learner
doesn't know this yet," not "the learner got this wrong."

Grading rule: judge correctness based on the $targetLanguage portion(s) of
the attempt only - their grammar, word choice, and whether they fit
meaningfully into the sentence. Do NOT mark the answer wrong purely because
part of it is in $nativeLanguage; that part is simply ungraded here and
instead surfaced below as a learning opportunity.

If the attempt is incomplete as a sentence - just a word or two, or a
phrase that trails off - mark it incorrect ("isCorrect": false) and explain
in "feedback" what's missing (e.g. no verb, cut off mid-thought), the same
way you'd explain a grammar mistake.

If any part of the attempt is in $nativeLanguage, identify each such
segment (exactly as the learner wrote it) and, for each, provide how to say
it in $targetLanguage plus a short nuance/alternatives note. If the entire
attempt is already in $targetLanguage, return an empty array for
"mixedLanguageSegments".

Also produce "completedSentence": the learner's own attempt rewritten
entirely in $targetLanguage, with every $nativeLanguage segment replaced by
its $targetLanguage equivalent so the whole thing reads as one natural
$targetLanguage sentence (adjust grammar/word order around the substitution
as needed rather than pasting the replacement in verbatim if that would
read unnaturally). If the attempt was already entirely in $targetLanguage,
"completedSentence" is that same sentence (fix obvious typos only, don't
otherwise rewrite it).

ERRORS - within the $targetLanguage portion only (never for the
$nativeLanguage segments already covered by "mixedLanguageSegments" above;
don't report the same thing in both places): if anything in the
$targetLanguage portion is wrong - grammar, word choice, spelling, spacing,
or (for languages that use them) tone/diacritic marks - you MUST report it
as a structured entry in "errors". NEVER give a vague statement like
"there's a typo" or "grammar is off" with nothing else - every issue you
mention has to come with exactly what's wrong, what it should be, and why.
Tone/diacritic mark mistakes are NOT minor: in a tonal language a single
wrong mark can change the meaning entirely, so call out precisely which
mark goes where. If there are several separate issues, report each as its
own "errors" entry. If the $targetLanguage portion has no issues, return an
empty array - do not invent problems that aren't there.

Each "errors" entry's "shouldBe" must be ONLY the corrected word/phrase for
that specific issue - never the full corrected sentence. The learner should
have to recall the rest of the sentence themselves; don't hand them the
whole answer while pointing out one mistake.

Do NOT echo the native sentence back in the JSON - the app already has it;
only return the fields below.

Field-by-field language rules (do not mix these up):
- "feedback": 1-2 sentences of overall comment on the $targetLanguage
  portion, written in $nativeLanguage. Point-by-point corrections go in
  "errors" below, not crammed in here.
- "referenceTranslation": a natural, correct translation of the native
  sentence, written ENTIRELY in $targetLanguage. This is a model answer for
  comparison only - it is NOT what gets read/said aloud next (that's
  "completedSentence" below).
- "mixedLanguageSegments[].originalSegment": the $nativeLanguage text
  exactly as the learner wrote it.
- "mixedLanguageSegments[].suggestedTranslation": how to say that segment,
  written ENTIRELY in $targetLanguage.
- "mixedLanguageSegments[].explanation": nuance or alternative phrasings,
  written in $nativeLanguage.
- "errors[].userWrote": the exact $targetLanguage word/phrase the learner
  wrote wrong, quoted verbatim.
- "errors[].shouldBe": the corrected word/phrase ONLY (not the full
  sentence), written in $targetLanguage.
- "errors[].explanation": why, written in $nativeLanguage - for tone/
  diacritic mistakes, name the specific mark and where it belongs.
- "completedSentence": the learner's own sentence, ENTIRELY in
  $targetLanguage as described above. This IS the exact sentence the
  learner will read/say aloud next, so it must be natural and complete -
  never a $nativeLanguage explanation.

Return ONLY raw JSON, no markdown fences:
{"isCorrect":true|false,
"feedback":"1-2 sentences in $nativeLanguage, overall comment only",
"referenceTranslation":"a natural, correct $targetLanguage translation",
"mixedLanguageSegments":[{"originalSegment":"...exactly as the learner wrote it","suggestedTranslation":"...in $targetLanguage","explanation":"...in $nativeLanguage"}],
"errors":[{"userWrote":"...exactly as written, in $targetLanguage","shouldBe":"...corrected word/phrase only, in $targetLanguage","explanation":"...in $nativeLanguage"}],
"completedSentence":"the learner's sentence, entirely in $targetLanguage"}
''';
      final text = await _generateText(apiKey, prompt, label: 'validateTranslation');
      final decoded = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
      return TranslationResult.fromJson(decoded);
    });
  }

  /// Dictionary-style lookup for a single word/short phrase — distinct from
  /// [validateTranslation], which grades a full-sentence attempt. Detects
  /// whether [input] was written in [nativeLanguage] or [targetLanguage]
  /// and explains it from there (translation, meaning, synonyms,
  /// antonyms). Kept deliberately short-prompted since this is a quick
  /// word lookup, not a full explanation.
  ///
  /// The model intermittently puts the wrong language in "translation"/
  /// "synonyms"/"antonyms" (same class of instruction-following slip as
  /// other Gemini calls in this file, just more visible here since a
  /// single-word answer leaves nowhere for a stray wrong-language token to
  /// hide). [_hasObviousLanguageMixing] catches the cases it can reliably
  /// detect and retries ONCE; see that method's doc for what it can't
  /// catch.
  Future<WordLookupResult> lookupWord({
    required String input,
    required String nativeLanguage,
    required String targetLanguage,
  }) async {
    final apiKey = await _requireApiKey();
    return _dedupe('lookupWord:$nativeLanguage:$targetLanguage:$input', () async {
      final prompt = _lookupWordPrompt(
        input: input,
        nativeLanguage: nativeLanguage,
        targetLanguage: targetLanguage,
      );

      Future<WordLookupResult> attempt() async {
        final text = await _generateText(apiKey, prompt, label: 'lookupWord');
        final decoded = jsonDecode(_stripCodeFences(text)) as Map<String, dynamic>;
        return WordLookupResult.fromJson(decoded);
      }

      final first = await attempt();
      if (!_hasObviousLanguageMixing(first, nativeLanguage, targetLanguage)) {
        return first;
      }

      _log('lookupWord: detected likely language mixing, retrying once');
      final retry = await attempt();
      if (!_hasObviousLanguageMixing(retry, nativeLanguage, targetLanguage)) {
        return retry;
      }

      _log('lookupWord: retry still shows language mixing, giving up');
      throw GeminiApiException(
        GeminiFailureReason.other,
        'Please try again.',
      );
    });
  }

  String _lookupWordPrompt({
    required String input,
    required String nativeLanguage,
    required String targetLanguage,
  }) {
    return '''
Dictionary lookup for a learner studying $targetLanguage (native language:
$nativeLanguage). Input: "$input"

First determine whether this input is written in $nativeLanguage or
$targetLanguage. Keep the response short and to the point - this is a
single word/short phrase lookup, not a full explanation.

Field-by-field language rules (do not mix these up - getting the language
wrong on any single field is the most common mistake here, so follow this
exactly for every field below, not just once at the top):
- "detectedLanguage": exactly "native" or "target".
- "translation": the input's equivalent in the OTHER language (if the
  input was $nativeLanguage, give the $targetLanguage equivalent; if it
  was $targetLanguage, give the $nativeLanguage equivalent). MUST be
  written ENTIRELY in that other language - not one word of the input's
  own language.
- "meaning": a brief explanation of the meaning/nuance. MUST be written
  ENTIRELY in $nativeLanguage, no matter which language the input was.
- "synonyms": similar words/phrases in the SAME language as the input.
  MUST be written in the input's own language: if the input was
  $targetLanguage, each entry is the $targetLanguage word quoted followed
  by its $nativeLanguage gloss in parentheses (e.g. "간다(khong đi)"); if
  the input was $nativeLanguage, each entry MUST be ENTIRELY in
  $nativeLanguage, with no $targetLanguage text anywhere in it.
- "antonyms": same language/formatting rule as "synonyms" above. Empty
  array if none apply.

Example of the exact JSON shape and field-language pattern to follow (this
illustrates the pattern using English/Spanish only - your real answer must
use $nativeLanguage/$targetLanguage instead, never English/Spanish unless
one of those happens to be the actual language). Input "run", native
English, learner studying Spanish:
{"detectedLanguage":"native",
"translation":"correr",
"meaning":"To move quickly on foot.",
"synonyms":["sprint","jog","dash"],
"antonyms":["walk","stroll"]}
Note "translation" switched entirely to the OTHER language (Spanish),
while "synonyms"/"antonyms" stayed entirely in the SAME language as the
input (English, since "run" was English) - not Spanish.

Return ONLY raw JSON, no markdown fences:
{"detectedLanguage":"native|target",
"translation":"...entirely in the OTHER language from the input",
"meaning":"...entirely in $nativeLanguage",
"synonyms":["...entirely in the input's own language, per the rule above"],
"antonyms":["...entirely in the input's own language, per the rule above"]}
''';
  }

  /// Best-effort check for "translation"/"synonyms"/"antonyms" coming back
  /// in the wrong language. Only reliable when the expected language uses a
  /// distinct Unicode script from the other language (e.g. Korean vs.
  /// English, Japanese vs. English) - checked via [_scriptPatternFor]. For
  /// same-script pairs (e.g. English vs. Vietnamese, both Latin-based)
  /// there's no cheap way to tell "wrong language" from "right language"
  /// apart by character inspection alone, so this deliberately returns
  /// false rather than guess - the strengthened prompt above is the actual
  /// fix for that case, this is just a safety net for the cases it CAN
  /// reliably catch.
  bool _hasObviousLanguageMixing(
    WordLookupResult result,
    String nativeLanguage,
    String targetLanguage,
  ) {
    final isNativeInput = result.detectedLanguage == 'native';
    final translationExpected = isNativeInput ? targetLanguage : nativeLanguage;
    final sameLanguageExpected = isNativeInput ? nativeLanguage : targetLanguage;

    if (_isDefinitelyWrongLanguage(result.translation, translationExpected)) {
      return true;
    }
    if (result.synonyms.isNotEmpty &&
        _isDefinitelyWrongLanguage(result.synonyms.join(' '), sameLanguageExpected)) {
      return true;
    }
    if (result.antonyms.isNotEmpty &&
        _isDefinitelyWrongLanguage(result.antonyms.join(' '), sameLanguageExpected)) {
      return true;
    }
    return false;
  }

  /// True only when [expectedLanguage] maps to a distinct Unicode script
  /// (see [_scriptPatternFor]) and [text] contains not a single character
  /// of it - i.e. the field is entirely in some other script, which can
  /// only mean the wrong language was used. Returns false (not "wrong") for
  /// undetectable language pairs rather than risk a false-positive retry.
  bool _isDefinitelyWrongLanguage(String text, String expectedLanguage) {
    if (text.trim().isEmpty) return false;
    final pattern = _scriptPatternFor(expectedLanguage);
    if (pattern == null) return false;
    return !pattern.hasMatch(text);
  }

  /// Maps a handful of common non-Latin-script languages to a regex
  /// matching their Unicode block, keyed by a loose substring match on the
  /// language name (as freely typed by the user during onboarding, e.g.
  /// "Korean", "korean", "North Korean"). Returns null for anything else
  /// (Latin-script languages like English/Vietnamese/French, or any
  /// language name not recognized) - those pairs aren't distinguishable by
  /// script alone, so callers must treat null as "can't tell".
  RegExp? _scriptPatternFor(String languageName) {
    final lower = languageName.toLowerCase();
    if (lower.contains('korean')) return RegExp(r'[가-힣ᄀ-ᇿ㄰-㆏]');
    if (lower.contains('japanese')) {
      return RegExp(r'[぀-ゟ゠-ヿ一-鿿]');
    }
    if (lower.contains('chinese') || lower.contains('mandarin') || lower.contains('cantonese')) {
      return RegExp(r'[一-鿿]');
    }
    if (lower.contains('russian')) return RegExp(r'[Ѐ-ӿ]');
    if (lower.contains('arabic')) return RegExp(r'[؀-ۿ]');
    if (lower.contains('thai')) return RegExp(r'[฀-๿]');
    if (lower.contains('hindi')) return RegExp(r'[ऀ-ॿ]');
    return null;
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
  $targetLanguage - the language they were speaking. Do NOT translate it
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

  /// Synthesizes [text] to speech using [voice] (a name from
  /// [kGeminiTtsVoices]) and returns playable WAV bytes.
  ///
  /// Not verified against a live Gemini API key in this environment — the
  /// TTS response is documented to return raw PCM inline audio, which this
  /// wraps in a WAV header (see [pcm16ToWav]) so `audioplayers` can play
  /// it directly from memory. If Gemini's actual response shape differs,
  /// adjust the parsing here.
  ///
  /// Prefer [speakCached] over calling this directly — it's the same
  /// synthesis, but reuses a cached clip instead of re-spending a TTS call
  /// when one already exists for the sentence.
  Future<Uint8List> synthesizeSpeech(String text, {required String voice}) async {
    return _dedupe('synthesizeSpeech:$voice:$text', () async {
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
              'prebuiltVoiceConfig': {'voiceName': voice},
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

  /// Returns playable WAV bytes for [sentence] (always target-language —
  /// TTS is only ever used for target-language content in this app),
  /// reusing a cached clip when one already exists instead of spending a
  /// TTS call. A cache miss picks a fresh random voice from
  /// [kGeminiTtsVoices] and stores the result under it; a cache hit keeps
  /// whichever voice the sentence was originally synthesized with, so the
  /// same sentence doesn't change voice between replays.
  Future<Uint8List> speakCached(String sentence) async {
    final config = await _configService.readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    return _dedupe('speakCached:$targetLanguage:$sentence', () async {
      final cached = await _ttsCache.get(sentence: sentence, language: targetLanguage);
      if (cached != null) {
        _log('speakCached: hit (voice=${cached.voice})');
        return cached.audioBytes;
      }

      final voice = randomTtsVoice();
      _log('speakCached: miss, synthesizing with voice=$voice');
      final bytes = await synthesizeSpeech(sentence, voice: voice);
      await _ttsCache.put(
        sentence: sentence,
        language: targetLanguage,
        audioBytes: bytes,
        voice: voice,
      );
      return bytes;
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
