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

/// Gemini 호출이 왜 실패했는지를 분류하는 열거형. 사용자에게 보여줄 메시지를
/// 고르고 UI가 어떻게 반응할지(예: 재시도 버튼 노출 여부)를 결정하는 데
/// 쓰인다.
enum GeminiFailureReason { authError, network, rateLimit, other }

/// [GeminiFailureReason]을 사용자가 바로 이해하고 대응할 수 있는 영문
/// 메시지로 변환한다.
///
/// `ApiKeyViewModel`, `LevelTestViewModel`, `ReviewViewModel`,
/// `ShadowingViewModel`, `WritingViewModel`이 `GeminiApiException`이나
/// `GeminiValidationResult`의 실패 사유를 화면에 보여줄 에러 문구로 바꿀 때
/// 호출한다.
/// [reason]: 실패 분류.
/// [rawError]: `GeminiFailureReason.other`일 때 원본 에러 문자열을 메시지에
/// 덧붙이기 위해 선택적으로 전달한다.
/// 반환값: 사용자에게 보여줄 영문 안내 메시지.
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

/// [GeminiService.validateApiKey]의 결과를 담는 값 객체. API 키가 유효한지
/// 여부와, 유효하지 않다면 그 사유를 함께 전달한다. `ApiKeyViewModel`이
/// 사용자가 입력한 키를 검증한 뒤 이 결과를 보고 성공/실패 UI를 분기한다.
class GeminiValidationResult {
  /// 검증 성공을 나타내는 결과를 만든다. [success]는 `true`, [reason]/[rawError]는
  /// `null`이 된다.
  const GeminiValidationResult.success()
      : success = true,
        reason = null,
        rawError = null;

  /// 검증 실패를 나타내는 결과를 만든다.
  /// [reason]: 실패 사유 분류.
  /// [rawError]: 있다면 원본 에러 메시지/문자열.
  const GeminiValidationResult.failure(this.reason, [this.rawError]) : success = false;

  /// API 키 검증이 성공했는지 여부.
  final bool success;
  /// 실패했을 때의 사유. 성공 시에는 `null`.
  final GeminiFailureReason? reason;
  /// 실패했을 때의 원본 에러 문자열(있는 경우). 성공 시에는 `null`.
  final String? rawError;
}

/// Thrown by [GeminiService] calls other than [GeminiService.validateApiKey],
/// which report failure via a result object instead.
/// ([GeminiService.validateApiKey]를 제외한 [GeminiService]의 다른 모든
/// 호출에서 실패 시 던져지는 예외. `validateApiKey`만 예외 대신 결과
/// 객체([GeminiValidationResult])로 실패를 알린다.)
/// `ReviewViewModel`, `ShadowingViewModel`, `WritingViewModel`,
/// `LevelTestViewModel` 등이 이 예외를 catch해 [userMessageForFailure]로
/// 사용자 메시지로 변환한다.
class GeminiApiException implements Exception {
  /// [reason]과 사용자 표시용이 아닌 원본 [message]로 예외를 만든다.
  GeminiApiException(this.reason, this.message);

  /// 실패 사유 분류.
  final GeminiFailureReason reason;
  /// 원본 에러 메시지(디버그 로그/원인 파악용, 사용자에게 그대로 노출되지
  /// 않을 수 있음 — [userMessageForFailure] 참고).
  final String message;

  /// 디버그 출력을 위한 문자열 표현. `[GeminiService] ...` 로그나 예외
  /// 스택 출력 시 자동으로 사용된다.
  @override
  String toString() => 'GeminiApiException($reason, $message)';
}

/// Calls the Gemini REST API directly over `http` (no SDK package).
/// (SDK 패키지 없이 `http` 패키지로 Gemini REST API를 직접 호출하는 서비스.)
///
/// 문장 생성, 채점(dictation/translation), 발음 분석, 단어 사전 조회, 레벨
/// 테스트 생성/채점, TTS 음성 합성, 핸드오프 요약 등 이 앱이 Gemini에
/// 의존하는 모든 기능의 진입점이다. `geminiServiceProvider`
/// (`service_providers.dart`)를 통해 Riverpod provider로 노출되며,
/// `ShadowingViewModel`, `WritingViewModel`, `ReviewViewModel`,
/// `LevelTestViewModel`, `ApiKeyViewModel`, `SettingsViewModel`,
/// `dictionary_screen.dart` 등에서 사용한다.
class GeminiService {
  /// [client]/[apiKeyStorage]/[configService]/[ttsCacheService]를 주입받아
  /// 생성한다(테스트에서 모킹할 수 있도록). 모두 생략하면 기본 구현
  /// (`http.Client()`, `ApiKeyStorageService()`, `ConfigService()`,
  /// `TtsCacheService()`)을 새로 만들어 사용한다.
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

  /// Level returned by [evaluateLevelTest] outright (no Gemini call) when
  /// too few questions were answered to grade meaningfully.
  /// (답변된 문항이 너무 적어 의미 있게 채점할 수 없을 때 [evaluateLevelTest]가
  /// Gemini를 호출하지 않고 바로 반환하는 레벨.)
  static const _kEasiestLevel = 'A1';

  /// Minimum fraction of placement-test questions that must actually be
  /// answered before attempting real grading; below this, [evaluateLevelTest]
  /// returns [_kEasiestLevel] directly. 0.3 -> skip grading once 70%+ of
  /// the test is blank.
  /// (실제 채점을 시도하기 전에 실제로 답변되어 있어야 하는 배치고사 문항의
  /// 최소 비율. 이 비율 미만이면 [evaluateLevelTest]가 바로 [_kEasiestLevel]을
  /// 반환한다. 0.3이면 시험의 70% 이상이 공백일 때 채점 자체를 건너뛴다는
  /// 뜻이다.)
  static const _kMinAnsweredRatioForGrading = 0.3;

  /// Text-to-speech capable model. Returns raw PCM audio inline (see
  /// [synthesizeSpeech]), not a standard container — this is a Gemini API
  /// behavior this app hasn't been able to verify against a live key in
  /// this environment, so the exact response shape is a best-effort guess
  /// based on Gemini's documented TTS response format.
  /// (TTS(음성 합성)가 가능한 모델. [synthesizeSpeech]에서 보듯 표준 컨테이너가
  /// 아니라 원시(raw) PCM 오디오를 인라인으로 반환한다 — 이는 이 개발 환경에서
  /// 실제 키로 검증해보지 못한 Gemini API 동작이라, 정확한 응답 형태는 Gemini의
  /// 문서화된 TTS 응답 포맷을 기반으로 한 최선의 추측이다.)
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
  /// (현재 진행 중인 요청들을, 메서드명+인자로 만든 시그니처를 키로 삼아
  /// 저장해둔다. 같은 시그니처의 두 번째 호출이 첫 번째 호출이 아직 끝나기
  /// 전에 들어오면, 중복 네트워크 요청을 새로 보내는 대신 이미 진행 중인
  /// 동일한 Future를 재사용한다 — 예를 들어 화면의 initState가 rebuild와
  /// 경합하는 경우 등.)
  final Map<String, Future<Object?>> _inFlight = {};

  /// [key]로 식별되는 요청이 이미 `_inFlight`에 있으면 그 Future를 재사용하고,
  /// 없으면 [run]을 실행해 새 요청을 시작하며 완료/실패 시 `_inFlight`에서
  /// 자신을 제거한다. [validateApiKey]를 제외한 이 클래스의 거의 모든 공개
  /// 메서드가 실제 네트워크 요청을 이 헬퍼로 감싸 중복 호출을 방지한다.
  /// [key]: 요청을 식별하는 문자열(메서드명+인자 조합).
  /// [run]: 실제로 요청을 수행하는 콜백(최초 호출일 때만 실행됨).
  /// 반환값: 요청 결과를 담은 `Future<T>`.
  /// 부작용: `_inFlight` 맵에 항목을 추가/제거한다.
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
    // (`.whenComplete()`는 `future` 자체와는 별개의 새로운 Future를
    // 반환하므로 자체 에러 핸들러가 필요하다 — 그렇지 않으면 `run()`이
    // 예외를 던질 때마다, 호출자가 `future`에 건 try/catch가 에러를
    // 정상적으로 처리하고 있음에도 불구하고 이 버려지는(discarded)
    // 체인이 처리되지 않은 예외로 표면화되어 데스크톱에서 앱이
    // 크래시할 수 있다.)
    unawaited(future.then((_) {}, onError: (_) {}).whenComplete(() => _inFlight.remove(key)));
    return future;
  }

  /// 디버그 모드에서만 `[GeminiService] $message` 형식으로 콘솔에 로그를
  /// 남긴다. 이 클래스 전역에서 요청 시작/성공/실패, 생성된 문장, 캐시
  /// 히트/미스 등을 추적하기 위해 사용된다.
  /// [message]: 출력할 로그 메시지.
  /// 부작용: `kDebugMode`일 때 `debugPrint`를 호출한다.
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GeminiService] $message');
    }
  }

  /// [apiKey]가 유효한 Gemini API 키인지 실제로 짧은 ping 요청을 보내
  /// 검증한다. `ApiKeyViewModel`이 사용자가 최초 설정 화면에서 API 키를
  /// 제출했을 때 호출하며, 이 결과에 따라 키를 저장하고 다음 화면으로
  /// 진행할지 에러를 보여줄지 결정한다. 다른 메서드와 달리 실패를 예외로
  /// 던지지 않고 [GeminiValidationResult]로 감싸 반환한다.
  /// [apiKey]: 검증할 API 키 문자열.
  /// 반환값: 성공/실패와 실패 사유를 담은 [GeminiValidationResult].
  /// 부작용: 검증을 위해 실제로 Gemini API에 네트워크 요청을 보낸다.
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

  /// [nativeLang]과 [targetLang] 사이의 배치고사(placement test) 10문항을
  /// Gemini로 생성한다. `LevelTestViewModel`이 레벨 테스트 화면 진입 시
  /// 호출해 사용자에게 보여줄 문제 목록을 얻는다.
  /// [nativeLang]: 학습자의 모국어.
  /// [targetLang]: 학습 대상 언어.
  /// 반환값: 난이도 순으로 정렬된 [LevelTestQuestion] 10개 목록.
  /// 부작용: Gemini API에 네트워크 요청을 보낸다.
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

  /// 학습자가 [questions]에 대해 제출한 [answers]를 채점해 CEFR 레벨(A1~C2)
  /// 하나를 판정한다. `LevelTestViewModel`이 레벨 테스트 제출 시 호출하며,
  /// 결과 레벨은 이후 `config.json`의 `difficultyLevel`로 저장되어 학습
  /// 난이도를 결정한다. 답변된 문항이 [_kMinAnsweredRatioForGrading] 미만이면
  /// Gemini를 호출하지 않고 곧바로 [_kEasiestLevel]을 반환한다(빈 답이
  /// 대부분인 시험도 실제로는 모델이 "아무것도 모름"보다 한 단계 높은
  /// 레벨을 주는 경향이 있었기 때문에 둔, 프롬프트 지시만으로는 부족한
  /// 결정론적 안전장치).
  /// [nativeLang]: 학습자의 모국어.
  /// [targetLang]: 학습 대상 언어.
  /// [questions]: 출제된 문항 목록.
  /// [answers]: 각 문항에 대한 학습자의 답변(순서가 [questions]와 대응).
  /// 반환값: 판정된 CEFR 레벨 토큰 문자열(예: `"B1"`).
  /// 부작용: 채점 기준을 충족하면 Gemini API에 네트워크 요청을 보낸다.
  Future<String> evaluateLevelTest({
    required String nativeLang,
    required String targetLang,
    required List<LevelTestQuestion> questions,
    required List<String> answers,
  }) async {
    if (questions.isEmpty) return _kEasiestLevel;

    final blankCount = questions
        .asMap()
        .entries
        .where((e) => (e.key < answers.length ? answers[e.key] : '').trim().isEmpty)
        .length;
    final blankRatio = blankCount / questions.length;

    // Deterministic safeguard, not just a prompt instruction: a model that
    // sees mostly-blank answers has, in practice, still returned a level a
    // notch above "knows nothing" (e.g. A2 off 2/10 answered) rather than
    // reliably bottoming out at A1 - the same kind of intermittent
    // instruction-following gap seen elsewhere in this file. Below
    // [_kMinAnsweredRatioForGrading] answered, skip Gemini entirely (no
    // API call spent) and hand back the easiest level outright.
    // (프롬프트 지시만으로는 부족해서 둔 결정론적 안전장치: 대부분 공백인
    // 답안을 본 모델도 실제로는 "아무것도 모름"보다 한 단계 높은 레벨을
    // 돌려주곤 했다(예: 10문항 중 2개만 답해도 A1이 아니라 A2). 이는 이
    // 파일 다른 곳에서도 보이는, 모델이 지시를 간헐적으로 놓치는 것과 같은
    // 종류의 문제다. [_kMinAnsweredRatioForGrading] 미만으로 답했다면
    // Gemini를 아예 호출하지 않고(API 호출 비용 없이) 가장 쉬운 레벨을
    // 바로 돌려준다.)
    if (blankRatio >= 1 - _kMinAnsweredRatioForGrading) {
      _log('evaluateLevelTest: $blankCount/${questions.length} blank, skipping grading -> $_kEasiestLevel');
      return _kEasiestLevel;
    }

    final transcript = StringBuffer();
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final answer = i < answers.length ? answers[i] : '';
      final answerText = answer.trim().isEmpty ? '(left blank)' : answer;
      transcript.writeln('${i + 1}. (${q.sourceLang}) ${q.prompt} -> $answerText');
    }
    return _dedupe('evaluateLevelTest:$nativeLang:$targetLang:${transcript.toString().hashCode}', () async {
      final apiKey = await _requireApiKey();
      final prompt = '''
Grade this $nativeLang<->$targetLang placement test (question, then the
learner's answer):

$transcript

Grading rules:
- A question marked "(left blank)" was NOT answered - count it as WRONG,
  the same as a genuinely incorrect answer. Never simply exclude blank
  questions from grading or estimate the level from only the answered
  ones; the level must reflect all ${questions.length} questions.
- If only a small number of questions were actually answered, be
  conservative: when in doubt between two levels, pick the EASIER one.
  A couple of lucky/short correct answers on an otherwise blank test is
  not evidence of a higher level.

Return ONLY a single CEFR level token: A1, A2, B1, B2, C1, or C2. No other
text.
''';
      final text = await _generateText(apiKey, prompt, label: 'evaluateLevelTest');
      return text.trim();
    });
  }

  /// 학습을 잠시 중단하는 학습자를 위해, 지금까지의 세션 내용을 요약한
  /// 짧은 평문 핸드오프(handoff) 노트를 생성한다. `SettingsViewModel`이
  /// (설정 화면에서 세션을 마무리/일시정지하는 흐름에서) 호출하며, 생성된
  /// 요약은 이후 `HandoffService`를 통해 저장되어 다음에 재개할 때 참고
  /// 자료로 쓰인다.
  /// [snapshot]: 현재 언어/난이도/대화 history를 담은 학습 세션 스냅샷.
  /// 반환값: 튜터가 이어받아 볼 수 있는 짧은 영문 요약 문장.
  /// 부작용: Gemini API에 네트워크 요청을 보낸다.
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
  /// (진행 중인 shadowing/writing 세션의 다음 문장을 생성한다. [direction]이
  /// `'target'`이면 대상 언어 문장(shadowing용), `'native'`이면 모국어
  /// 문장(writing용)을 생성한다. [history]는 마지막 [kHistoryContextWindow]
  /// turn만 맥락으로 전송한다 — 자연스러운 이어짐을 위해 전체 세션 history가
  /// 필요하진 않고, 전부 보내면 세션이 길어질수록 프롬프트가 계속 커지기
  /// 때문이다.)
  ///
  /// `ShadowingViewModel.loadSentence()`가 `direction: 'target'`으로,
  /// `WritingViewModel.loadSentence()`가 `direction: 'native'`로 호출해
  /// 새 문장이 필요할 때마다 사용한다.
  /// [direction]: `'target'` 또는 `'native'`.
  /// [history]: 지금까지의 대화 turn 목록(전체, 내부에서 최근 window만 사용).
  /// 반환값: 생성된 문장 하나(따옴표/레이블 없는 순수 텍스트).
  /// 부작용: Gemini API에 네트워크 요청을 보내고, 생성된 문장을 디버그
  /// 로그로 남긴다.
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
        final trimmed = text.trim();
        // Logged so a "what got played doesn't match what got graded" report
        // can be checked against the exact text generated for this turn -
        // this, speakCached's, and validateDictation/validateTranslation's
        // logs below should always show the identical string for one turn.
        // ("재생된 것과 채점된 것이 다르다"는 버그 리포트가 들어왔을 때 이
        // turn에서 실제로 생성된 텍스트와 대조해볼 수 있도록 로그를 남긴다 -
        // 이 로그, speakCached의 로그, validateDictation/validateTranslation
        // 아래의 로그는 같은 turn이라면 항상 동일한 문자열을 보여줘야 한다.)
        _log('sentence generated for this turn -> "$trimmed"');
        return trimmed;
      },
    );
  }

  /// Grades a shadowing dictation attempt and, in the same call, returns a
  /// native-language translation and a brief analysis of the sentence —
  /// bundled here rather than as a separate request to avoid doubling the
  /// number of calls per turn.
  /// (shadowing dictation 답안을 채점하고, 같은 호출 안에서 모국어 번역과
  /// 문장에 대한 간단한 분석까지 함께 반환한다 — turn당 호출 수를 두 배로
  /// 늘리지 않기 위해 별도 요청으로 나누지 않고 한 번에 묶어서 처리한다.)
  ///
  /// `ShadowingViewModel`이 사용자가 받아쓰기(dictation) 답을 제출했을 때
  /// 호출해 정답 여부와 피드백을 얻는다.
  /// [original]: 실제로 재생된 대상 언어 원문 문장.
  /// [userInput]: 학습자가 받아쓴 내용.
  /// 반환값: 정답 여부, 피드백, 번역, 오류 목록 등을 담은 [DictationResult].
  /// 부작용: Gemini API에 네트워크 요청을 보내고, 채점 대상 원문을 디버그
  /// 로그로 남긴다.
  Future<DictationResult> validateDictation({
    required String original,
    required String userInput,
  }) async {
    // See the matching log in generateNextSentence - this must always read
    // the identical string for a given turn.
    // (generateNextSentence의 대응 로그 참고 - 같은 turn이라면 항상 동일한
    // 문자열을 읽어야 한다.)
    _log('validateDictation grading against original -> "$original"');
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
  /// (writing(번역) 답안을 정확한 단어 대응이 아니라 의미 위주로 채점하고,
  /// 뒤이어 나오는 듣기/발음 연습에 쓰일 자연스러운 모범 번역을 함께
  /// 반환한다.)
  ///
  /// `WritingViewModel`과 `ReviewViewModel`이 사용자가 번역 답안을
  /// 제출했을 때 호출해 정답 여부, 피드백, 모범 번역(`referenceTranslation`)을
  /// 얻는다. 모범 번역은 이후 듣기/발음 분석 단계에서 재생/비교 대상으로
  /// 쓰인다.
  /// [nativeSentence]: 학습자에게 주어진 모국어 원문 문장.
  /// [userTranslation]: 학습자가 작성한 번역(대상 언어와 모국어가 섞여
  /// 있을 수 있음).
  /// 반환값: 정답 여부, 피드백, 모범 번역, 언어 혼용 구간, 오류 목록 등을
  /// 담은 [TranslationResult].
  /// 부작용: Gemini API에 네트워크 요청을 보내고, 채점 대상 원문을 디버그
  /// 로그로 남긴다.
  Future<TranslationResult> validateTranslation({
    required String nativeSentence,
    required String userTranslation,
  }) async {
    // See generateNextSentence's matching log - this must always read the
    // identical string generated for this turn (WritingViewModel's
    // `nativeSentence`, never separately recomputed).
    // (generateNextSentence의 대응 로그 참고 - 이 turn을 위해 생성된 것과
    // 동일한 문자열을 항상 읽어야 한다(WritingViewModel의 `nativeSentence`를
    // 그대로 쓰며, 별도로 다시 계산하지 않는다).)
    _log('validateTranslation grading against nativeSentence -> "$nativeSentence"');
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
doesn't know this yet," not "the learner got this wrong." Do NOT invent a
completed or corrected version of the sentence anywhere in your response -
the learner must write the whole thing themselves in $targetLanguage; your
job here is only to explain each native-language part, never to supply a
finished replacement sentence.

Grading rule: judge "isCorrect" based on the $targetLanguage portion(s) of
the attempt only - their grammar, word choice, and whether they fit
meaningfully into the sentence. Do NOT mark "isCorrect" false purely
because part of it is in $nativeLanguage; that part is simply ungraded
here and instead surfaced below as a learning opportunity via
"mixedLanguageSegments". (The app separately treats ANY native-language
segment as blocking the turn from being complete, regardless of
"isCorrect" - that's a different, deliberate rule on the app side, not
something you need to reflect by changing "isCorrect".)

If the attempt is incomplete as a sentence - just a word or two, or a
phrase that trails off - mark it incorrect ("isCorrect": false) and explain
in "feedback" what's missing (e.g. no verb, cut off mid-thought), the same
way you'd explain a grammar mistake.

If any part of the attempt is in $nativeLanguage, identify each such
segment (exactly as the learner wrote it) and, for each, provide how to say
it in $targetLanguage plus a short nuance/alternatives note, in
"mixedLanguageSegments" - this is a hint for the learner to apply
themselves, not something the app assembles into an answer for them. If
the entire attempt is already in $targetLanguage, return an empty array
for "mixedLanguageSegments".

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
  comparison only - the learner never sees it presented as their own
  answer, and it is NOT read/said aloud on their behalf.
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

Return ONLY raw JSON, no markdown fences:
{"isCorrect":true|false,
"feedback":"1-2 sentences in $nativeLanguage, overall comment only",
"referenceTranslation":"a natural, correct $targetLanguage translation",
"mixedLanguageSegments":[{"originalSegment":"...exactly as the learner wrote it","suggestedTranslation":"...in $targetLanguage","explanation":"...in $nativeLanguage"}],
"errors":[{"userWrote":"...exactly as written, in $targetLanguage","shouldBe":"...corrected word/phrase only, in $targetLanguage","explanation":"...in $nativeLanguage"}]}
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
  /// (단어/짧은 구를 찾아보는 사전식 조회 — 문장 전체 답안을 채점하는
  /// [validateTranslation]과는 다르다. [input]이 [nativeLanguage]와
  /// [targetLanguage] 중 어느 언어로 쓰였는지 판별한 뒤 그에 맞춰 번역/뜻/
  /// 동의어/반의어를 설명한다. 전체 설명이 아니라 빠른 단어 조회이므로
  /// 의도적으로 짧은 프롬프트를 사용한다.
  ///
  /// 모델이 간헐적으로 "translation"/"synonyms"/"antonyms" 필드에 잘못된
  /// 언어를 넣는 경우가 있다(이 파일의 다른 Gemini 호출에서도 보이는 것과
  /// 같은 종류의 지시 불이행 문제인데, 단어 하나짜리 답변은 잘못된 언어
  /// 토큰이 숨을 곳이 없어 더 눈에 띈다). [_hasObviousLanguageMixing]이
  /// 확실히 감지할 수 있는 경우를 잡아내 한 번만(ONCE) 재시도한다. 감지하지
  /// 못하는 경우에 대해서는 해당 메서드의 문서를 참고.)
  ///
  /// `dictionary_screen.dart`에서 사용자가 사전 검색을 실행했을 때 호출된다.
  /// [input]: 조회할 단어/짧은 구.
  /// [nativeLanguage]: 학습자의 모국어.
  /// [targetLanguage]: 학습 대상 언어.
  /// 반환값: 감지된 언어, 번역, 뜻, 동의어/반의어를 담은 [WordLookupResult].
  /// 부작용: Gemini API에 네트워크 요청을 보내며, 언어 혼용이 감지되면
  /// 최대 한 번 더 요청을 보낸다.
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

  /// [lookupWord]가 Gemini에 보낼 사전 조회용 프롬프트 문자열을 만든다.
  /// [input]: 조회할 단어/구.
  /// [nativeLanguage]: 학습자의 모국어.
  /// [targetLanguage]: 학습 대상 언어.
  /// 반환값: 필드별 언어 규칙과 JSON 응답 형식을 명시한 프롬프트 문자열.
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
  /// ("translation"/"synonyms"/"antonyms"이 잘못된 언어로 돌아왔는지에 대한
  /// 최선의 검사(best-effort). 기대되는 언어가 상대 언어와 서로 다른
  /// Unicode 스크립트를 쓸 때만(예: 한국어 vs 영어, 일본어 vs 영어) 신뢰할
  /// 수 있으며, [_scriptPatternFor]로 확인한다. 같은 스크립트를 쓰는 언어
  /// 쌍(예: 영어 vs 베트남어, 둘 다 라틴 문자 기반)은 문자만 봐서는
  /// "틀린 언어"와 "맞는 언어"를 값싸게 구분할 방법이 없으므로, 이 경우
  /// 추측하지 않고 의도적으로 false를 반환한다 — 이런 경우의 실질적인
  /// 해결책은 위쪽의 강화된 프롬프트이며, 이 함수는 확실히 잡아낼 수 있는
  /// 경우에 대한 안전망일 뿐이다.)
  ///
  /// [lookupWord]가 첫 번째 응답과 재시도 응답 각각에 대해 재시도 여부를
  /// 판단하기 위해 호출한다.
  /// [result]: Gemini가 반환한 조회 결과.
  /// [nativeLanguage]: 학습자의 모국어.
  /// [targetLanguage]: 학습 대상 언어.
  /// 반환값: 확실한 언어 혼용이 감지되면 `true`.
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
  /// ([expectedLanguage]가 [_scriptPatternFor]를 통해 구분 가능한 고유
  /// Unicode 스크립트에 매핑되고, [text]에 그 스크립트 문자가 단 하나도
  /// 없을 때만 true를 반환한다 - 즉 해당 필드가 완전히 다른 스크립트로만
  /// 되어 있다면 잘못된 언어가 쓰였다고 확신할 수 있는 경우다. 판별
  /// 불가능한 언어 쌍에 대해서는 false-positive로 재시도가 낭비되는
  /// 위험을 감수하기보다 false("틀리지 않음")를 반환한다.)
  ///
  /// [_hasObviousLanguageMixing]이 각 필드(translation/synonyms/antonyms)를
  /// 검사할 때 호출하는 헬퍼다.
  /// [text]: 검사할 텍스트.
  /// [expectedLanguage]: 이 텍스트가 쓰여 있어야 할 것으로 기대되는 언어.
  /// 반환값: 확실히 다른 언어(스크립트)로 쓰였다고 판단되면 `true`.
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
  /// (자주 쓰이는 비-라틴 스크립트 언어 몇 개를, 해당 Unicode 블록에
  /// 매칭되는 정규식에 대응시킨다. 온보딩에서 사용자가 자유롭게 입력한
  /// 언어명(예: "Korean", "korean", "North Korean")에 대해 느슨한 부분
  /// 문자열 매칭으로 키를 찾는다. 그 외의 경우(영어/베트남어/프랑스어 같은
  /// 라틴 스크립트 언어, 또는 인식되지 않는 언어명)에는 null을 반환한다 -
  /// 이런 언어 쌍은 스크립트만으로 구분할 수 없으므로, 호출부는 null을
  /// "판별 불가"로 취급해야 한다.)
  ///
  /// [_isDefinitelyWrongLanguage]가 내부적으로 호출하는 헬퍼다.
  /// [languageName]: 사용자가 입력한 자유 형식의 언어 이름.
  /// 반환값: 해당 언어의 고유 스크립트를 매칭하는 정규식, 또는 판별 불가
  /// 시 `null`.
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
  /// (녹음된 발음 시도를 [targetSentence]와 비교하도록 Gemini의 멀티모달
  /// 분석에 보낸다.)
  ///
  /// `ReviewViewModel.analyzePronunciation`, `ShadowingViewModel`,
  /// `WritingViewModel`이 각각 review/shadowing/writing 화면에서 사용자가
  /// 발음 녹음을 마쳤을 때 호출하며, `review_screen.dart`,
  /// `shadowing_pronunciation_screen.dart`, `writing_listening_screen.dart`가
  /// 녹음 위젯의 콜백을 통해 이를 트리거한다.
  /// [audioBytes]: 녹음된 WAV 오디오 바이트.
  /// [targetSentence]: 실제로 재생/제시되었던 대상 언어 문장(비교 기준).
  /// 반환값: 인식된 텍스트, 피드백, 정확도(%)를 담은 [PronunciationResult].
  /// 부작용: Gemini API에 오디오를 포함한 멀티모달 요청을 보낸다.
  Future<PronunciationResult> analyzePronunciation({
    required Uint8List audioBytes,
    required String targetSentence,
  }) async {
    // See generateNextSentence's matching log - must always read the
    // identical string that was actually played (ShadowingState.sentence /
    // WritingState.lastUserTranslation, never separately recomputed).
    // (generateNextSentence의 대응 로그 참고 - 실제로 재생되었던 것과
    // 동일한 문자열을 항상 읽어야 한다(ShadowingState.sentence /
    // WritingState.lastUserTranslation을 그대로 쓰며, 별도로 다시 계산하지
    // 않는다).)
    _log('analyzePronunciation comparing against targetSentence -> "$targetSentence"');
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
  /// ([text]를 [voice]([kGeminiTtsVoices]에 있는 음성 이름) 목소리로
  /// 합성해 재생 가능한 WAV 바이트를 반환한다.
  ///
  /// 이 개발 환경에서는 실제 Gemini API 키로 검증해보지 못했다 — TTS
  /// 응답은 문서상 원시(raw) PCM 인라인 오디오를 반환한다고 되어 있으며,
  /// 이 함수는 그것을 WAV 헤더로 감싸서(`[pcm16ToWav]` 참고)
  /// `audioplayers`가 메모리에서 바로 재생할 수 있게 한다. Gemini의 실제
  /// 응답 형태가 다르다면 여기 파싱 로직을 조정해야 한다.
  ///
  /// 직접 호출하기보다는 [speakCached]를 우선 사용할 것 — 동일한 합성이지만,
  /// 이미 해당 문장의 캐시된 클립이 있으면 TTS 호출을 다시 쓰는 대신
  /// 재사용한다.)
  ///
  /// [speakCached]가 캐시 미스일 때 내부적으로 호출한다.
  /// [text]: 합성할 텍스트(항상 대상 언어 문장).
  /// [voice]: 사용할 TTS 음성 이름.
  /// 반환값: 바로 재생 가능한 WAV 형식의 오디오 바이트.
  /// 부작용: Gemini API에 네트워크 요청을 보낸다.
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
  /// ([sentence](항상 대상 언어 — 이 앱에서 TTS는 오직 대상 언어 콘텐츠에만
  /// 쓰인다)에 대한 재생 가능한 WAV 바이트를 반환하며, 이미 캐시된 클립이
  /// 있으면 TTS 호출을 새로 쓰는 대신 재사용한다. 캐시 미스이면
  /// [kGeminiTtsVoices]에서 새로 무작위 음성을 골라 그 음성으로 결과를
  /// 저장하고, 캐시 히트이면 그 문장이 원래 합성될 때 쓰인 음성을 그대로
  /// 유지한다 — 같은 문장을 다시 재생해도 음성이 바뀌지 않도록.)
  ///
  /// `shadowing_dictation_screen.dart`와 `writing_listening_screen.dart`가
  /// 오디오 재생 위젯의 `audioLoader` 콜백으로 이 메서드를 넘겨, 사용자가
  /// 재생 버튼을 누를 때(또는 필요 시 사전 로드할 때) 호출되게 한다.
  /// [sentence]: 재생할 대상 언어 문장(캐시 키로도 쓰임).
  /// 반환값: 재생 가능한 WAV 오디오 바이트.
  /// 부작용: 캐시 미스 시 [synthesizeSpeech]를 호출해 Gemini에 네트워크
  /// 요청을 보내고, `TtsCacheService`에 결과를 저장한다.
  Future<Uint8List> speakCached(String sentence) async {
    // See generateNextSentence's matching log - the exact text sent to TTS
    // (and used as the cache key) must always be the identical string
    // generated for this turn.
    // (generateNextSentence의 대응 로그 참고 - TTS로 보내는(그리고 캐시
    // 키로도 쓰이는) 정확한 텍스트는 항상 이 turn에서 생성된 것과 동일한
    // 문자열이어야 한다.)
    _log('speakCached synthesizing/caching -> "$sentence"');
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

  /// TTS 응답의 `mimeType`(예: `"audio/L16;rate=24000"`)에서 샘플레이트
  /// 숫자를 정규식으로 추출한다. [synthesizeSpeech]가 WAV 헤더를 만들
  /// 때(`pcm16ToWav`) 사용할 샘플레이트를 얻기 위해 호출한다.
  /// [mimeType]: Gemini가 반환한 오디오의 MIME 타입 문자열.
  /// 반환값: 추출된 샘플레이트(Hz), 패턴이 없으면 `null`.
  int? _parseSampleRate(String mimeType) {
    final match = RegExp(r'rate=(\d+)').firstMatch(mimeType);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// secure storage에서 API 키를 읽어오되, 없거나 비어있으면 즉시
  /// [GeminiApiException]을 던진다. [validateApiKey]를 제외한 이 클래스의
  /// 거의 모든 공개 메서드가 실제 요청을 보내기 전에 가장 먼저 호출해
  /// "키가 없는데 네트워크 요청부터 보내는" 상황을 막는다.
  /// 반환값: 저장되어 있는 유효한(비어있지 않은) API 키.
  /// 예외: 키가 없거나 공백이면 `GeminiFailureReason.authError`로
  /// [GeminiApiException]을 던진다.
  Future<String> _requireApiKey() async {
    final apiKey = await _apiKeyStorage.readApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw GeminiApiException(GeminiFailureReason.authError, 'No API key configured.');
    }
    return apiKey;
  }

  /// 순수 텍스트 [prompt] 하나만 담아 [_generateContent]를 호출하고, 응답에서
  /// 텍스트만 뽑아 반환하는 편의 헬퍼. `validateApiKey`, `generateLevelTest`,
  /// `evaluateLevelTest`, `generateHandoffSummary`, `generateNextSentence`,
  /// `validateDictation`, `validateTranslation`, `lookupWord` 등 오디오가
  /// 필요 없는 대부분의 텍스트 전용 호출이 사용한다.
  /// [apiKey]: 사용할 Gemini API 키.
  /// [prompt]: 모델에 보낼 프롬프트 텍스트.
  /// [label]: 디버그 로그에 남길 호출 식별용 라벨.
  /// 반환값: Gemini가 생성한 텍스트.
  /// 부작용: Gemini API에 네트워크 요청을 보낸다.
  Future<String> _generateText(String apiKey, String prompt, {required String label}) async {
    final decoded = await _generateContent(apiKey, [
      {'text': prompt},
    ], label: label);
    return _extractText(decoded);
  }

  /// Gemini `generateContent` REST 엔드포인트를 실제로 호출하는 저수준
  /// 공통 로직. [_generateText](텍스트 전용), [analyzePronunciation](오디오
  /// 포함), [synthesizeSpeech](TTS 모델+생성 설정 포함)가 각자 필요한
  /// `parts`/`model`/`generationConfig`를 구성해 호출하는 이 파일의 유일한
  /// 실제 HTTP 요청 지점이다.
  /// [apiKey]: 요청 URL 쿼리에 실릴 Gemini API 키.
  /// [parts]: 요청 본문의 `contents[0].parts`에 들어갈 파트 목록(텍스트,
  /// 인라인 오디오 등).
  /// [model]: 사용할 모델명(생략 시 기본 텍스트 모델 `_model` 사용).
  /// [generationConfig]: 응답 형식/음성 설정 등 추가 생성 옵션(TTS 등에서
  /// 사용).
  /// [label]: 디버그 로그에 남길 호출 식별용 라벨.
  /// 반환값: Gemini가 반환한 원시 JSON 응답을 디코딩한 Map.
  /// 예외: 타임아웃/네트워크 오류나 200이 아닌 상태 코드에 대해
  /// [GeminiApiException]을 던진다.
  /// 부작용: `http.Client`로 실제 네트워크 요청을 보내고 결과를 로그로
  /// 남긴다.
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

  /// [_generateContent]가 반환한 원시 JSON 응답에서 후보(candidate)와 파트를
  /// 파고들어 실제 생성된 텍스트만 이어붙여 추출한다. [_generateText]와
  /// [analyzePronunciation]이 텍스트 응답을 얻기 위해 호출한다.
  /// [decoded]: `_generateContent`가 반환한 디코딩된 JSON Map.
  /// 반환값: 응답에 담긴 모든 텍스트 파트를 이어붙인 문자열.
  /// 예외: `candidates`나 `parts`가 없거나 비어있으면
  /// `GeminiFailureReason.other`로 [GeminiApiException]을 던진다.
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

  /// HTTP 상태 코드를 [GeminiFailureReason]으로 분류한다. 401/403은 인증
  /// 오류, 429는 rate limit, 그 외는 기타로 취급한다. [_generateContent]가
  /// 200이 아닌 응답을 받았을 때 [GeminiApiException]에 담을 사유를 정하기
  /// 위해 호출한다.
  /// [statusCode]: HTTP 응답 상태 코드.
  /// 반환값: 분류된 [GeminiFailureReason].
  GeminiFailureReason _reasonForStatusCode(int statusCode) {
    if (statusCode == 401 || statusCode == 403) return GeminiFailureReason.authError;
    if (statusCode == 429) return GeminiFailureReason.rateLimit;
    return GeminiFailureReason.other;
  }

  /// Gemini 응답이 지시(prompt)를 무시하고 마크다운 코드펜스(예: `` ```json
  /// ``)로 JSON을 감싸 보내는 경우를 대비해, 앞뒤의 코드펜스를 제거한
  /// 순수 텍스트를 돌려준다. `generateLevelTest`, `validateDictation`,
  /// `validateTranslation`, `lookupWord`, `analyzePronunciation` 등 JSON을
  /// `jsonDecode`하기 전에 공통으로 호출하는 정리(sanitize) 헬퍼다.
  /// [text]: Gemini가 반환한 원본 텍스트.
  /// 반환값: 코드펜스가 제거되고 앞뒤 공백이 trim된 텍스트.
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
