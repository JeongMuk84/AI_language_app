import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/learning_constants.dart';
import '../models/conversation_turn.dart';
import '../models/dictation_result.dart';
import '../models/exercise_type.dart';
import '../models/pronunciation_result.dart';
import '../providers/service_providers.dart';
import '../services/gemini_service.dart';
import '../utils/id_utils.dart';
import 'sentence_hidden_toggle_mixin.dart';

/// ShadowingDictationScreen과 ShadowingPronunciationScreen이 함께 watch하는
/// UI 상태. 하나의 shadowing 턴(문장 듣고 받아쓰기 -> 발음 연습)에 걸친
/// 진행 상황을 담는다.
class ShadowingState {
  const ShadowingState({
    this.isLoadingSentence = true,
    this.loadError,
    this.turnId,
    this.sentence,
    this.isSubmittingDictation = false,
    this.dictationResult,
    this.dictationError,
    this.lastDictationInput,
    this.sentenceHidden = false,
    this.isAnalyzingPronunciation = false,
    this.pronunciationResult,
    this.pronunciationError,
  });

  /// [ShadowingViewModel.loadSentence]가 문장을 불러오는 동안 true.
  final bool isLoadingSentence;

  /// 문장 로딩이 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? loadError;

  /// 이번 shadowing 턴을 식별하는 id. `ConversationTurn`을 기록할 때 쓰인다.
  final String? turnId;

  /// 이번 턴에서 듣고 받아써야 할 목표 언어(target language) 문장. 이 값이
  /// TTS 재생, 받아쓰기 채점, 발음 분석 모두에서 동일하게 참조된다.
  final String? sentence;

  /// [ShadowingViewModel.submitDictation]이 채점 요청을 보내는 동안 true가
  /// 되어, ShadowingDictationScreen의 Submit 버튼을 비활성화하고 로딩
  /// 인디케이터를 보여주게 한다.
  final bool isSubmittingDictation;

  /// 받아쓰기 채점 결과.
  final DictationResult? dictationResult;

  /// 받아쓰기 채점 API 호출 자체가 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? dictationError;

  /// 학습자가 마지막으로 제출한 받아쓰기 원문. `ConversationTurn.userAnswer`로
  /// 기록된다.
  final String? lastDictationInput;

  /// ShadowingPronunciationScreen에서 문장이 가려져 있는지. `true`이면
  /// [SentenceHiddenToggleMixin]에 의해 발음 분석 시도도 함께 초기화된다.
  final bool sentenceHidden;

  /// [ShadowingViewModel.analyzePronunciation]이 발음 분석 요청을 보내는
  /// 동안 true.
  final bool isAnalyzingPronunciation;

  /// 발음 분석 결과.
  final PronunciationResult? pronunciationResult;

  /// 발음 분석 API 호출 자체가 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? pronunciationError;

  /// 받아쓰기가 채점 완료되어 있으면(정답 여부와 무관하게) 발음 연습
  /// 화면으로 넘어갈 수 있다. ShadowingDictationScreen의 "Continue to
  /// Pronunciation Practice" 버튼 활성화 여부를 결정한다.
  bool get canProceedToPronunciation => dictationResult != null;

  /// 각 필드를 갱신한 새 ShadowingState를 반환한다. [isLoadingSentence]/
  /// [loadError]/[turnId]/[sentence]는 `loadSentence()`가 새 상태를 직접
  /// 만들 때만 바뀌며 이 copyWith에서는 그대로 유지된다. `clear*` 플래그가
  /// true인 필드만 명시적으로 null이 된다.
  ShadowingState copyWith({
    bool? isSubmittingDictation,
    DictationResult? dictationResult,
    bool clearDictationResult = false,
    String? dictationError,
    bool clearDictationError = false,
    String? lastDictationInput,
    bool? sentenceHidden,
    bool? isAnalyzingPronunciation,
    PronunciationResult? pronunciationResult,
    bool clearPronunciationResult = false,
    String? pronunciationError,
    bool clearPronunciationError = false,
  }) {
    return ShadowingState(
      isLoadingSentence: isLoadingSentence,
      loadError: loadError,
      turnId: turnId,
      sentence: sentence,
      isSubmittingDictation: isSubmittingDictation ?? this.isSubmittingDictation,
      dictationResult: clearDictationResult ? null : (dictationResult ?? this.dictationResult),
      dictationError: clearDictationError ? null : (dictationError ?? this.dictationError),
      lastDictationInput: lastDictationInput ?? this.lastDictationInput,
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

/// ShadowingDictationScreen과 ShadowingPronunciationScreen 둘 다를 지원하는
/// 뷰모델 — 두 화면이 같은 문장/턴을 다루므로, 내비게이션 인자로 데이터를
/// 주고받는 대신 하나의 view-model 인스턴스를 공유한다.
class ShadowingViewModel extends Notifier<ShadowingState>
    with SentenceHiddenToggleMixin<ShadowingState> {
  /// 초기 상태(문장 로딩 중)를 생성한다. Riverpod이 이 provider가 처음
  /// watch/read될 때 자동으로 호출한다.
  @override
  ShadowingState build() => const ShadowingState();

  /// 서로 겹치는 두 번의 [loadSentence] 호출이 "영속화된 세션에 이미 문장이
  /// 있는지" 확인하는 지점을 둘 다 통과해버려 어느 쪽도 아직 결과를 쓰지
  /// 않은 상태로 경합하는 것을 막기 위한 가드다 — 예를 들어 `initState`가
  /// 중복 호출되거나 리빌드가 진행 중간에 겹쳐 들어오는 경우. 이 가드가
  /// 없으면 둘 다 `generateNextSentence`에 도달해 각자 실제로 다른 문장을
  /// 받아올 수 있고(Gemini가 같은 문장을 반복해준다는 보장은 없다), 나중에
  /// 덮어쓰는 쪽이 조용히 "그 턴의" 문장이 되어버리면서, 이미 이전 문장을
  /// 붙잡고 있던 것(예: 이미 그 문장으로 오디오 로딩을 시작한
  /// `AudioPlayButton`)은 오래된 텍스트를 계속 참조하게 된다 — 바로 이런
  /// TTS/채점 불일치를 막기 위해 존재하는 메서드다. 완전한 뮤텍스는 아니고,
  /// 이 Notifier 인스턴스 안에서 재진입 호출을 무시(no-op)하게 하는 정도의
  /// 최소한의 가드다.
  bool _isLoadingSentence = false;

  /// 영속화된 세션에 진행 중이던 문장이 있으면 그것을 복원하고(재개
  /// 케이스), 없으면 새 문장을 요청해 영속화한다. 이 메서드가 반환된
  /// 시점부터 [currentSentence]/[currentTurnId]가 이번 턴 전체에 걸친
  /// 단일 참조값이 된다 — TTS 플레이어, `submitDictation`의 채점 호출,
  /// `analyzePronunciation`이 모두 [ShadowingState.sentence]의 동일한 값을
  /// 읽어야 하는 이유다. ShadowingDictationScreen의 `initState`에서 호출된다
  /// (로드 실패 후 재시도 버튼에서도 재호출).
  Future<void> loadSentence() async {
    if (_isLoadingSentence) return;
    _isLoadingSentence = true;
    state = const ShadowingState();
    try {
      final sessionService = ref.read(sessionStateServiceProvider);
      final gemini = ref.read(geminiServiceProvider);

      var session = await sessionService.readState();
      session ??= await sessionService.startNewSession(initialType: ExerciseType.shadowing);

      String sentence;
      String turnId;
      if (session.currentSentence != null && session.currentTurnId != null) {
        sentence = session.currentSentence!;
        turnId = session.currentTurnId!;
      } else {
        final history = await ref.read(conversationHistoryServiceProvider).readAll();
        sentence = await gemini.generateNextSentence(direction: 'target', history: history);
        turnId = newTurnId();
        await sessionService.setCurrentSentence(session, sentence: sentence, turnId: turnId);
      }

      state = ShadowingState(isLoadingSentence: false, turnId: turnId, sentence: sentence);
    } catch (e) {
      state = ShadowingState(isLoadingSentence: false, loadError: _messageFor(e));
    } finally {
      _isLoadingSentence = false;
    }
  }

  /// 이 화면이 문장이 아직 로드되지 않은 채로 마운트되면(예: 앱이
  /// ShadowingPronunciationScreen으로 바로 재시작된 경우) 진행 중이던
  /// 문장으로 재개시킨다 — 그 외의 경우엔 아무 것도 하지 않으므로,
  /// ShadowingPronunciationScreen의 `initState`에서 조건 없이 호출해도
  /// 안전하다.
  Future<void> ensureSentenceLoaded() async {
    if (state.sentence != null) return;
    await loadSentence();
  }

  /// ShadowingDictationScreen의 Submit 버튼이 눌리면 호출된다.
  /// `GeminiService.validateDictation`으로 [userInput]을 현재 문장과
  /// 비교해 채점한다.
  Future<void> submitDictation(String userInput) async {
    if (state.sentence == null) return;
    state = state.copyWith(isSubmittingDictation: true, clearDictationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .validateDictation(original: state.sentence!, userInput: userInput);
      state = state.copyWith(
        isSubmittingDictation: false,
        dictationResult: result,
        lastDictationInput: userInput,
      );
    } catch (e) {
      state = state.copyWith(isSubmittingDictation: false, dictationError: _messageFor(e));
    }
  }

  /// "다시 시도": ShadowingDictationScreen의 Try Again 버튼이 눌리면
  /// 호출된다. 같은 sentence/turnId는 유지한 채 지금까지의 받아쓰기 시도만
  /// 지운다.
  void resetDictationAttempt() {
    state = state.copyWith(clearDictationResult: true, clearDictationError: true);
  }

  /// [SentenceHiddenToggleMixin]이 요구하는 구현. 현재 [state]의
  /// `sentenceHidden` 값을 그대로 반환한다.
  @override
  bool sentenceHiddenOf(ShadowingState state) => state.sentenceHidden;

  /// [SentenceHiddenToggleMixin]이 요구하는 구현. 문장을 새로 가릴 때
  /// ([hidden]이 true)는 발음 분석 시도도 함께 초기화하고, 다시 보이게 할
  /// 때는 `sentenceHidden`만 바꾼다.
  @override
  ShadowingState copyWithSentenceHidden(ShadowingState state, {required bool hidden}) {
    return hidden
        ? state.copyWith(
            sentenceHidden: true,
            clearPronunciationResult: true,
            clearPronunciationError: true,
          )
        : state.copyWith(sentenceHidden: false);
  }

  /// ShadowingPronunciationScreen의 AudioRecorderWidget 녹음이 끝나면
  /// 호출된다. `GeminiService.analyzePronunciation`으로 녹음된 [audioBytes]를
  /// 현재 문장과 비교해 발음 정확도를 채점한다.
  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    if (state.sentence == null) return;
    state = state.copyWith(isAnalyzingPronunciation: true, clearPronunciationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .analyzePronunciation(audioBytes: audioBytes, targetSentence: state.sentence!);
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationResult: result);
    } catch (e) {
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationError: _messageFor(e));
    }
  }

  /// "다음으로 넘어가기": ShadowingPronunciationScreen의 "Continue to
  /// Writing" 버튼이 눌리면 호출된다. 이번 shadowing 턴을 기록하고 현재
  /// 진행 중인 exercise 타입을 writing으로 전환한다.
  ///
  /// 이 턴에서 방금 [kDailyTurnLimit]에 도달했다면 true를 반환한다 — 이
  /// 경우 세션이 "학습 종료"와 똑같은 방식으로 이미 여기서 자동
  /// 마무리(finalize)되었으므로, 호출한 쪽(ShadowingPronunciationScreen)은
  /// 다음 exercise로 계속 진행하는 대신 진입 라우팅 화면(`/learning`)으로
  /// 돌아가야 한다.
  Future<bool> completeTurnAndAdvanceToWriting() async {
    final sessionService = ref.read(sessionStateServiceProvider);
    var session = await sessionService.readState();
    session ??= await sessionService.startNewSession(initialType: ExerciseType.shadowing);

    final turn = ConversationTurn(
      turnId: state.turnId ?? newTurnId(),
      type: ExerciseType.shadowing,
      timestamp: DateTime.now(),
      sentenceInTarget: state.sentence,
      userAnswer: state.lastDictationInput,
      isCorrect: state.dictationResult?.isCorrect,
      pronunciationScore: state.pronunciationResult?.accuracyPercent,
    );
    await sessionService.completeTurnAndSwitchType(
      session,
      nextType: ExerciseType.writing,
    );
    await ref.read(conversationHistoryServiceProvider).append(turn);

    // Track this sentence for spaced review — a no-op if it's already
    // tracked (e.g. a retried/re-encountered sentence).
    final dictationResult = state.dictationResult;
    if (state.sentence != null && dictationResult != null) {
      await ref
          .read(reviewHistoryServiceProvider)
          .recordIfNew(
            sentenceInTarget: state.sentence!,
            sentenceInNative: dictationResult.translation,
          );
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

/// [ShadowingViewModel]/[ShadowingState]를 노출하는 provider.
/// ShadowingDictationScreen과 ShadowingPronunciationScreen 양쪽 모두에서
/// `ref.watch`(상태 렌더링)와 `ref.read(...notifier)`(loadSentence/
/// submitDictation/analyzePronunciation/completeTurnAndAdvanceToWriting 등
/// 호출)로 사용된다.
final shadowingViewModelProvider = NotifierProvider<ShadowingViewModel, ShadowingState>(
  ShadowingViewModel.new,
);
