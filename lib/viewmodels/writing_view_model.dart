import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/learning_constants.dart';
import '../models/conversation_turn.dart';
import '../models/exercise_type.dart';
import '../models/pronunciation_result.dart';
import '../models/translation_result.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';
import '../utils/id_utils.dart';
import 'sentence_hidden_toggle_mixin.dart';

/// WritingScreen과 WritingListeningScreen이 함께 watch하는 UI 상태. 하나의
/// writing 턴(모국어 문장을 번역해서 쓰기 -> 자신의 번역을 듣고 발음
/// 연습하기)에 걸친 진행 상황을 담는다.
class WritingState {
  const WritingState({
    this.isLoadingSentence = true,
    this.loadError,
    this.turnId,
    this.nativeSentence,
    this.isSubmittingTranslation = false,
    this.translationResult,
    this.translationError,
    this.lastUserTranslation,
    this.sentenceHidden = false,
    this.isAnalyzingPronunciation = false,
    this.pronunciationResult,
    this.pronunciationError,
  });

  /// [WritingViewModel.loadSentence]가 문장을 불러오는 동안 true.
  final bool isLoadingSentence;

  /// 문장 로딩이 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? loadError;

  /// 이번 writing 턴을 식별하는 id. `ConversationTurn`을 기록할 때 쓰인다.
  final String? turnId;

  /// 이번 턴에서 번역해야 할 모국어(native language) 문장.
  final String? nativeSentence;

  /// [WritingViewModel.submitTranslation]이 채점 요청을 보내는 동안 true가
  /// 되어, WritingScreen의 Submit 버튼을 비활성화하고 로딩 인디케이터를
  /// 보여주게 한다.
  final bool isSubmittingTranslation;

  /// 번역 채점 결과.
  final TranslationResult? translationResult;

  /// 번역 채점 API 호출 자체가 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? translationError;

  /// 학습자 본인이 마지막으로 제출한 번역 원문 그대로(재시도했다면 가장
  /// 최근 제출본) — history 기록 목적(`ConversationTurn.userAnswer`/
  /// `sentenceInTarget`)으로 저장된다. [canProceedToListening]이 true가
  /// 되고 나면 이 값은 완전히 목표 언어로만 이루어져 있음이 보장되며(모국어
  /// 조각이 하나도 남아있지 않음) — 이는 곧 WritingListeningScreen이 그대로
  /// 보여주고, TTS로 재생하고, 발음을 채점하는 기준이 되는 문장이기도 하다.
  /// 여기에는 의도적으로 별도의 "완성됨"/자동 번역된 버전이 존재하지
  /// 않는다: 언어가 섞인 제출은 학습자를 대신해 자동으로 완성 처리되는 법이
  /// 없고, 학습자가 직접 자신의 시도를 수정해 완전히 목표 언어로만 된
  /// 문장을 다시 제출해야 한다(`TranslationResult.hasNativeLanguageMixed`
  /// 참고).
  final String? lastUserTranslation;

  /// WritingListeningScreen에서 문장이 가려져 있는지. `true`이면
  /// [SentenceHiddenToggleMixin]에 의해 발음 분석 시도도 함께 초기화된다.
  final bool sentenceHidden;

  /// [WritingViewModel.analyzePronunciation]이 발음 분석 요청을 보내는
  /// 동안 true.
  final bool isAnalyzingPronunciation;

  /// 발음 분석 결과.
  final PronunciationResult? pronunciationResult;

  /// 발음 분석 API 호출 자체가 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? pronunciationError;

  /// 제출은 목표 언어 부분이 맞았을 때 *그리고* 모국어가 하나도 남아있지
  /// 않았을 때에만 완료로 친다 — 문법적으로는 문제없어도 언어가 섞여 있으면
  /// 충분하지 않으며, 학습자가 스스로 완전히 목표 언어로 다시 써야 한다
  /// (`TranslationResult.hasNativeLanguageMixed` 참고).
  bool get canProceedToListening =>
      translationResult != null &&
      translationResult!.isCorrect &&
      !translationResult!.hasNativeLanguageMixed;

  /// 각 필드를 갱신한 새 WritingState를 반환한다. [isLoadingSentence]/
  /// [loadError]/[turnId]/[nativeSentence]는 `loadSentence()`/
  /// `resumeListeningIfNeeded()`가 새 상태를 직접 만들 때만 바뀌며 이
  /// copyWith에서는 그대로 유지된다. `clear*` 플래그가 true인 필드만
  /// 명시적으로 null이 된다.
  WritingState copyWith({
    bool? isSubmittingTranslation,
    TranslationResult? translationResult,
    bool clearTranslationResult = false,
    String? translationError,
    bool clearTranslationError = false,
    String? lastUserTranslation,
    bool? sentenceHidden,
    bool? isAnalyzingPronunciation,
    PronunciationResult? pronunciationResult,
    bool clearPronunciationResult = false,
    String? pronunciationError,
    bool clearPronunciationError = false,
  }) {
    return WritingState(
      isLoadingSentence: isLoadingSentence,
      loadError: loadError,
      turnId: turnId,
      nativeSentence: nativeSentence,
      isSubmittingTranslation: isSubmittingTranslation ?? this.isSubmittingTranslation,
      translationResult: clearTranslationResult
          ? null
          : (translationResult ?? this.translationResult),
      translationError: clearTranslationError
          ? null
          : (translationError ?? this.translationError),
      lastUserTranslation: lastUserTranslation ?? this.lastUserTranslation,
      sentenceHidden: sentenceHidden ?? this.sentenceHidden,
      isAnalyzingPronunciation: isAnalyzingPronunciation ?? this.isAnalyzingPronunciation,
      pronunciationResult: clearPronunciationResult
          ? null
          : (pronunciationResult ?? this.pronunciationResult),
      pronunciationError: clearPronunciationError
          ? null
          : (pronunciationError ?? this.pronunciationError),
    );
  }
}

/// WritingScreen과 WritingListeningScreen 둘 다를 지원하는 뷰모델 — 두
/// 화면이 같은 문장/턴을 다루므로, 내비게이션 인자로 데이터를 주고받는
/// 대신 하나의 view-model 인스턴스를 공유한다.
class WritingViewModel extends Notifier<WritingState> with SentenceHiddenToggleMixin<WritingState> {
  /// 초기 상태(문장 로딩 중)를 생성한다. Riverpod이 이 provider가 처음
  /// watch/read될 때 자동으로 호출한다.
  @override
  WritingState build() => const WritingState();

  /// 서로 겹치는 두 번의 [loadSentence] 호출이 "영속화된 세션에 이미
  /// 문장이 있는지" 확인하는 지점을 둘 다 통과해버려 어느 쪽도 아직 결과를
  /// 쓰지 않은 상태로 경합하는 것을 막기 위한 가드다 — 동일한 가드(와 그
  /// 전체 근거)가 `ShadowingViewModel.loadSentence`에도 있다.
  bool _isLoadingSentence = false;

  /// 이 메서드가 반환된 시점부터 [nativeSentence]가 이번 턴 전체에 걸친
  /// 단일 참조값이 된다 — `submitTranslation`의 채점 호출이 이 값을 직접
  /// 읽는다. WritingScreen의 `initState`에서 호출된다(로드 실패 후 재시도
  /// 버튼에서도 재호출).
  Future<void> loadSentence() async {
    if (_isLoadingSentence) return;
    _isLoadingSentence = true;
    state = const WritingState();
    try {
      final sessionService = ref.read(sessionStateServiceProvider);
      final gemini = ref.read(geminiServiceProvider);

      var session = await sessionService.readState();
      session ??= await sessionService.startNewSession(initialType: ExerciseType.writing);

      String sentence;
      String turnId;
      if (session.currentSentence != null && session.currentTurnId != null) {
        sentence = session.currentSentence!;
        turnId = session.currentTurnId!;
      } else {
        final history = await ref.read(conversationHistoryServiceProvider).readAll();
        sentence = await gemini.generateNextSentence(direction: 'native', history: history);
        turnId = newTurnId();
        await sessionService.setCurrentSentence(session, sentence: sentence, turnId: turnId);
      }

      state = WritingState(isLoadingSentence: false, turnId: turnId, nativeSentence: sentence);
    } catch (e) {
      state = WritingState(isLoadingSentence: false, loadError: _messageFor(e));
    } finally {
      _isLoadingSentence = false;
    }
  }

  /// 앱이 (`LearningSubStep.second` 기준) 듣기 단계 중간에
  /// WritingListeningScreen으로 바로 재시작되었을 때 그 화면을 재개시킨다 —
  /// 이번 세션의 번역이 이미 로드되어 있으면 아무 것도 하지 않는다.
  /// `loadSentence()`는 *첫 번째* 하위 단계(새 writing 문제)를 위한
  /// 것이라 학습자 본인이 제출한 번역을 복원해주지 않으므로 여기서는
  /// 재사용할 수 없다: 이 메서드는 채점을 다시 돌리지 않고, 듣기와 발음
  /// 채점이 동작하는 데 필요한 만큼만(문장 + 학습자의 답) 복원한다.
  /// WritingListeningScreen의 `initState`에서 호출된다.
  Future<void> resumeListeningIfNeeded() async {
    if (state.lastUserTranslation != null) return;
    final session = await ref.read(sessionStateServiceProvider).readState();
    final userAnswer = session?.currentUserAnswer;
    if (session == null || userAnswer == null) {
      // Shouldn't normally happen (this screen is only reachable with a
      // submitted translation), but avoid stranding the learner on a
      // permanent spinner if the persisted state is ever missing/corrupt.
      state = const WritingState(
        isLoadingSentence: false,
        loadError: 'Could not resume this session. Please start again.',
      );
      return;
    }
    state = WritingState(
      isLoadingSentence: false,
      turnId: session.currentTurnId,
      nativeSentence: session.currentSentence,
      lastUserTranslation: userAnswer,
    );
  }

  /// WritingScreen의 Submit 버튼이 눌리면 호출된다.
  /// `GeminiService.validateTranslation`으로 [userTranslation]을 현재
  /// 모국어 문장([nativeSentence])과 비교해 채점한다.
  Future<void> submitTranslation(String userTranslation) async {
    if (state.nativeSentence == null) return;
    state = state.copyWith(isSubmittingTranslation: true, clearTranslationError: true);
    try {
      final gemini = ref.read(geminiServiceProvider);
      final result = await gemini.validateTranslation(
        nativeSentence: state.nativeSentence!,
        userTranslation: userTranslation,
      );
      state = state.copyWith(
        isSubmittingTranslation: false,
        translationResult: result,
        lastUserTranslation: userTranslation,
      );
    } catch (e) {
      state = state.copyWith(isSubmittingTranslation: false, translationError: _messageFor(e));
    }
  }

  /// "다시 시도" on WritingScreen: 같은 sentence/turnId는 유지한 채 지금까지의
  /// 시도만 지운다.
  void resetTranslationAttempt() {
    state = state.copyWith(clearTranslationResult: true, clearTranslationError: true);
  }

  /// [SentenceHiddenToggleMixin]이 요구하는 구현. 현재 [state]의
  /// `sentenceHidden` 값을 그대로 반환한다.
  @override
  bool sentenceHiddenOf(WritingState state) => state.sentenceHidden;

  /// [SentenceHiddenToggleMixin]이 요구하는 구현. 문장을 새로 가릴 때
  /// ([hidden]이 true)는 발음 분석 시도도 함께 초기화하고, 다시 보이게 할
  /// 때는 `sentenceHidden`만 바꾼다.
  @override
  WritingState copyWithSentenceHidden(WritingState state, {required bool hidden}) {
    return hidden
        ? state.copyWith(
            sentenceHidden: true,
            clearPronunciationResult: true,
            clearPronunciationError: true,
          )
        : state.copyWith(sentenceHidden: false);
  }

  /// WritingListeningScreen의 AudioRecorderWidget 녹음이 끝나면 호출된다.
  /// `GeminiService.analyzePronunciation`으로 녹음된 [audioBytes]를 채점
  /// 대상과 비교한다.
  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    // 학습자 본인의 최종, 완전히 목표 언어로 된 제출본 — 방금
    // WritingListeningScreen이 `speakCached`로 재생해준 것과 동일한
    // 문장이다.
    final target = state.lastUserTranslation;
    if (target == null) return;
    state = state.copyWith(isAnalyzingPronunciation: true, clearPronunciationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .analyzePronunciation(audioBytes: audioBytes, targetSentence: target);
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationResult: result);
    } catch (e) {
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationError: _messageFor(e));
    }
  }

  /// "다시 시도" on WritingListeningScreen: 마지막 녹음 시도만 지운다.
  void resetPronunciationAttempt() {
    state = state.copyWith(clearPronunciationResult: true, clearPronunciationError: true);
  }

  /// "다음으로 넘어가기": WritingListeningScreen의 "Continue" 버튼이 눌리면
  /// 호출된다. 이번 writing 턴을 기록하고 현재 진행 중인 exercise 타입을
  /// shadowing으로 전환한다.
  ///
  /// 이 턴에서 방금 [kDailyTurnLimit]에 도달했다면 true를 반환한다 — 이
  /// 경우 세션이 "학습 종료"와 똑같은 방식으로 이미 여기서 자동
  /// 마무리(finalize)되었으므로, 호출한 쪽(WritingListeningScreen)은 다음
  /// exercise로 계속 진행하는 대신 진입 라우팅 화면(`/learning`)으로
  /// 돌아가야 한다.
  Future<bool> completeTurnAndAdvanceToShadowing() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    var session = await sessionService.readState();
    session ??= await sessionService.startNewSession(initialType: ExerciseType.writing);

    final turn = ConversationTurn(
      turnId: state.turnId ?? newTurnId(),
      type: ExerciseType.writing,
      timestamp: DateTime.now(),
      sentenceInNative: state.nativeSentence,
      // The learner's own final (fully target-language, correct) answer —
      // never `referenceTranslation` (a model example they never actually
      // wrote themselves).
      sentenceInTarget: state.lastUserTranslation,
      userAnswer: state.lastUserTranslation,
      isCorrect: state.translationResult?.isCorrect,
      pronunciationScore: state.pronunciationResult?.accuracyPercent,
    );
    await sessionService.completeTurnAndSwitchType(
      session,
      nextType: ExerciseType.shadowing,
    );
    await ref.read(conversationHistoryServiceProvider).append(turn);

    // Track this sentence for spaced review — a no-op if it's already
    // tracked. `lastUserTranslation` is exactly what WritingListeningScreen
    // just cached as TTS audio via `speakCached`, so this is the string
    // ReviewSessionService.buildReviewSet()'s cache check needs to find a
    // hit under.
    final finalAnswer = state.lastUserTranslation;
    if (finalAnswer != null && finalAnswer.isNotEmpty && state.nativeSentence != null) {
      await ref
          .read(reviewHistoryServiceProvider)
          .recordIfNew(sentenceInTarget: finalAnswer, sentenceInNative: state.nativeSentence!);
    }

    final newCount = await sessionService.incrementDailyTurnCount();
    ref.invalidate(dailyTurnCountProvider);
    if (newCount >= kDailyTurnLimit) {
      await ref.read(historyServiceProvider).finalizeSession();
      return true;
    }
    return false;
  }

  /// 예외 [e]를 사용자에게 보여줄 메시지 문자열로 변환한다. `GeminiApiException`이면
  /// 실패 사유별 안내 메시지로, 그 외에는 일반적인 재시도 안내 메시지로 바꾼다.
  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }
}

/// [WritingViewModel]/[WritingState]를 노출하는 provider. WritingScreen과
/// WritingListeningScreen 양쪽 모두에서 `ref.watch`(상태 렌더링)와
/// `ref.read(...notifier)`(loadSentence/submitTranslation/
/// analyzePronunciation/completeTurnAndAdvanceToShadowing 등 호출)로
/// 사용된다.
final writingViewModelProvider = NotifierProvider<WritingViewModel, WritingState>(
  WritingViewModel.new,
);
