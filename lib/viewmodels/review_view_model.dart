import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/learning_constants.dart';
import '../models/pronunciation_result.dart';
import '../models/review_item.dart';
import '../models/review_progress.dart';
import '../models/translation_result.dart';
import '../providers/service_providers.dart';
import '../router/app_router.dart';
import '../services/gemini_service.dart';

/// ReviewScreen이 watch하는 UI 상태. 스페이스드 리뷰(spaced review) 세트,
/// 현재 몇 번째 문항을 보고 있는지, 번역 제출/채점 진행 상태, 발음 분석
/// 진행 상태를 모두 담는다.
class ReviewState {
  const ReviewState({
    this.isLoading = true,
    this.loadError,
    this.items = const [],
    this.currentIndex = 0,
    this.startedAt,
    this.isSubmittingTranslation = false,
    this.translationResult,
    this.translationError,
    this.translationWarning,
    this.lastUserTranslation,
    this.isAnalyzingPronunciation = false,
    this.pronunciationResult,
    this.pronunciationError,
  });

  /// [ReviewViewModel.loadReviewSet]이 리뷰 세트를 불러오는 동안 true. 이
  /// 동안 ReviewScreen은 로딩 인디케이터만 보여준다.
  final bool isLoading;

  /// 리뷰 세트 로딩이 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? loadError;

  /// 이번 리뷰 세션에서 복습할 문장 목록(`ReviewSessionService.buildReviewSet`
  /// 결과, 또는 재개 시 저장된 `ReviewProgress.reviewItemList`).
  final List<ReviewItem> items;

  /// 지금 학습자가 보고 있는 [items]의 인덱스.
  final int currentIndex;

  /// 이 리뷰 세션이 시작된 시각. `ReviewProgress`를 저장할 때 함께 기록된다.
  final DateTime? startedAt;

  /// [ReviewViewModel.submitTranslation]이 채점 요청을 보내는 동안 true가
  /// 되어, ReviewScreen의 Submit 버튼을 비활성화하고 로딩 인디케이터를
  /// 보여주게 한다.
  final bool isSubmittingTranslation;

  /// 현재 문항에 대한 번역 채점 결과.
  final TranslationResult? translationResult;

  /// 번역 채점 API 호출 자체가 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? translationError;

  /// 클라이언트에서만 발생하는 안내 메시지(예: "완전한 문장을 작성해
  /// 주세요")로, Submit이 눌렸는데 텍스트박스가 비어있거나 공백뿐일 때
  /// 표시된다 — 이 경우 일부러 `validateTranslation`을 호출하지 않으므로
  /// API 호출 비용이 들지 않는다. [translationResult]와는 다르다: 이 값은
  /// 실제로 채점된 시도를 나타내지 않으므로 [isTranslationCorrect]에 영향을
  /// 주지 않고 리뷰 진행 상태에도 저장되지 않는다.
  final String? translationWarning;

  /// 학습자가 마지막으로 제출한 번역 원문. 화면이 재마운트될 때
  /// (`loadReviewSet`) 텍스트박스를 복원하는 데 쓰인다.
  final String? lastUserTranslation;

  /// [ReviewViewModel.analyzePronunciation]이 발음 분석 요청을 보내는 동안
  /// true.
  final bool isAnalyzingPronunciation;

  /// 현재 문항에 대한 발음 분석 결과.
  final PronunciationResult? pronunciationResult;

  /// 발음 분석 API 호출 자체가 실패했을 때 사용자에게 보여줄 에러 메시지.
  final String? pronunciationError;

  /// [currentIndex]가 가리키는 문항. 범위를 벗어나면(모두 다 봤으면) null.
  ReviewItem? get currentItem => currentIndex < items.length ? items[currentIndex] : null;

  /// 모든 문항을 다 봤으면(캐시된 오디오가 없어 마지막 몇 개를 건너뛴
  /// 경우도 포함) true. ReviewScreen은 이 상태를 "복습할 게 없음"과 똑같이
  /// 취급해 빈 화면 대신 안내 문구를 보여준다.
  bool get isExhausted => items.isNotEmpty && currentIndex >= items.length;

  /// 번역이 *정답으로* 채점된 적이 있을 때만 true — 단순히 "한 번이라도
  /// 제출했음"과는 다르다. ReviewScreen의 텍스트박스/Submit 버튼 잠금과
  /// 아래 [canAdvance]를 모두 이 값이 좌우한다.
  bool get isTranslationCorrect => translationResult?.isCorrect ?? false;

  /// 지금 보고 있는 문항이 이번 세트의 마지막 문항인지.
  bool get isLastItem => items.isNotEmpty && currentIndex == items.length - 1;

  /// "Next Sentence" / "Finish Review & Start Learning" 버튼은 번역이
  /// *정답*으로 채점되고 발음도 통과 기준을 넘었을 때만 활성화된다 — 발음이
  /// 아무리 좋아도 번역이 틀렸으면 넘어갈 수 없다.
  bool get canAdvance =>
      isTranslationCorrect &&
      pronunciationResult != null &&
      pronunciationResult!.accuracyPercent >= kPronunciationPassThreshold;

  /// 각 필드를 갱신한 새 ReviewState를 반환한다. `clear*` 플래그가 true인
  /// 필드만 명시적으로 null이 되고, 그 외 nullable 필드는 새 값이 없으면
  /// 이전 값을 유지한다.
  ReviewState copyWith({
    bool? isLoading,
    String? loadError,
    List<ReviewItem>? items,
    int? currentIndex,
    DateTime? startedAt,
    bool? isSubmittingTranslation,
    TranslationResult? translationResult,
    bool clearTranslationResult = false,
    String? translationError,
    bool clearTranslationError = false,
    String? translationWarning,
    bool clearTranslationWarning = false,
    String? lastUserTranslation,
    bool? isAnalyzingPronunciation,
    PronunciationResult? pronunciationResult,
    bool clearPronunciationResult = false,
    String? pronunciationError,
    bool clearPronunciationError = false,
  }) {
    return ReviewState(
      isLoading: isLoading ?? this.isLoading,
      loadError: loadError,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      startedAt: startedAt ?? this.startedAt,
      isSubmittingTranslation: isSubmittingTranslation ?? this.isSubmittingTranslation,
      translationResult: clearTranslationResult
          ? null
          : (translationResult ?? this.translationResult),
      translationError: clearTranslationError
          ? null
          : (translationError ?? this.translationError),
      translationWarning: clearTranslationWarning
          ? null
          : (translationWarning ?? this.translationWarning),
      lastUserTranslation: lastUserTranslation ?? this.lastUserTranslation,
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

/// ReviewScreen(라우트 `/learning/review`)을 지원하는 뷰모델. 스페이스드
/// 리뷰 세트를 불러오고, 문항별 번역 제출/채점과 발음 분석을 처리하며,
/// 진행 상태를 `SessionStateService`에 영속화해 재시작 후에도 이어갈 수
/// 있게 한다. 이 파일 어디에서도 `GeminiService.synthesizeSpeech`/
/// `speakCached`를 호출하지 않는다 — 재생은 항상 `TtsCacheService.get`을
/// 통해서만 이루어지며, 이는 이미 캐시된 것만 읽고 새로 TTS를 합성하는
/// 데로는 절대 폴백하지 않는다. 이는 의도된 설계다: 리뷰는 TTS 쿼터를
/// 절대 소비해서는 안 된다(`kMaxReviewSetSize` / `buildReviewSet` 참고).
class ReviewViewModel extends Notifier<ReviewState> {
  /// 초기 상태(로딩 중)를 생성한다. Riverpod이 이 provider가 처음
  /// watch/read될 때 자동으로 호출한다.
  @override
  ReviewState build() => const ReviewState();

  /// ReviewScreen의 `initState`에서 호출된다(로드 실패 후 재시도 버튼에서도
  /// 재호출). 저장된 `ReviewProgress`가 있으면 그것을 복원하고, 없으면
  /// `ReviewSessionService.buildReviewSet()`으로 새로 세트를 만들어
  /// 저장한다(정상적으로는 라우터가 이미 만들어 저장해두므로, 이 분기는
  /// 라우팅 없이 화면에 바로 진입한 경우에만 실행됨). 복원 시에는 현재
  /// 문항에 대해 이미 제출된 번역/채점/발음 결과까지 함께 복원해, 화면
  /// 재마운트(주로 앱 재시작)로 인해 이미 한 일이 사라지고 Play/Record가
  /// 다시 잠기는 일이 없게 한다. 마지막으로 [_skipUnplayableItems]를 호출한다.
  Future<void> loadReviewSet() async {
    state = const ReviewState();
    try {
      final sessionStateService = ref.read(sessionStateServiceProvider);
      var progress = await sessionStateService.readReviewProgress();

      if (progress == null) {
        // The router normally builds+persists this before ever navigating
        // here — this only runs if the screen is somehow reached without
        // that (e.g. a hot restart straight into this route in dev).
        final items = await ref.read(reviewSessionServiceProvider).buildReviewSet();
        if (items.isEmpty) {
          state = state.copyWith(isLoading: false, items: const []);
          return;
        }
        progress = ReviewProgress(
          reviewItemList: items,
          reviewCurrentIndex: 0,
          startedAt: DateTime.now(),
        );
        await sessionStateService.writeReviewProgress(progress);
      }

      state = ReviewState(
        isLoading: false,
        items: progress.reviewItemList,
        currentIndex: progress.reviewCurrentIndex,
        startedAt: progress.startedAt,
        // Restores whatever progress was already made on the *current*
        // item (submitted translation, its grading, and — if attempted —
        // the pronunciation result) so a screen remount (most commonly an
        // app restart mid-item) doesn't wipe it and re-lock Play/Record
        // behind "submit again", even though the learner already did.
        translationResult: progress.currentTranslationResult,
        lastUserTranslation: progress.currentUserTranslation,
        pronunciationResult: progress.currentPronunciationResult,
      );
      await _skipUnplayableItems();
    } catch (e) {
      state = ReviewState(isLoading: false, loadError: _messageFor(e));
    }
  }

  /// 방어적 재확인용 메서드: `buildReviewSet()`이 이미 캐시된 오디오가 있는
  /// 문장만 걸러냈지만, 혹시 그 사이 캐시가 바뀌었다면(리뷰는 캐시에 쓰지
  /// 않으므로 원래는 일어나선 안 됨) 더 이상 재생할 수 없는 문항을 건너뛰어
  /// 화면이 멈추지 않게 하고, 각 스킵을 로그로 남긴다.
  Future<void> _skipUnplayableItems() async {
    final config = await ref.read(configServiceProvider).readConfig();
    final targetLanguage = config.targetLanguage ?? 'the target language';
    final ttsCache = ref.read(ttsCacheServiceProvider);

    var index = state.currentIndex;
    while (index < state.items.length) {
      final item = state.items[index];
      final location = await ttsCache.peek(sentence: item.sentenceInTarget, language: targetLanguage);
      if (location != null) break;
      // ignore: avoid_print
      print('[Review] Skipping "${item.sentenceInTarget}" — cached audio no longer available.');
      index++;
    }
    if (index != state.currentIndex) {
      state = state.copyWith(currentIndex: index);
      if (state.startedAt != null) {
        await ref
            .read(sessionStateServiceProvider)
            .writeReviewProgress(
              ReviewProgress(
                reviewItemList: state.items,
                reviewCurrentIndex: index,
                startedAt: state.startedAt!,
              ),
            );
      }
    }
  }

  /// ReviewScreen의 Submit 버튼이 눌리면 호출된다. 입력값이 비어있으면
  /// (공백만 있어도) `validateTranslation`을 호출하지 않고 클라이언트 측
  /// 경고 메시지([ReviewState.translationWarning])만 세팅한다 — 이 경우
  /// [translationResult]는 건드리지 않으므로 [isTranslationCorrect]는 여전히
  /// false이고 Submit/텍스트박스도 계속 열려 있다. 그렇지 않으면
  /// `GeminiService.validateTranslation`으로 [userTranslation]을 채점하고,
  /// 결과를 저장한 뒤 [_persistCurrentItemSnapshot]으로 진행 상태를
  /// 영속화한다.
  Future<void> submitTranslation(String userTranslation) async {
    final item = state.currentItem;
    if (item == null) return;

    final trimmed = userTranslation.trim();
    if (trimmed.isEmpty) {
      // Never spends a validateTranslation call on nothing — this is a
      // pure client-side guard, not a graded attempt, so it doesn't touch
      // translationResult (Submit/the textbox stay unlocked either way
      // since isTranslationCorrect only looks at translationResult).
      state = state.copyWith(
        clearTranslationError: true,
        translationWarning: 'Please write a complete sentence.',
      );
      return;
    }

    state = state.copyWith(
      isSubmittingTranslation: true,
      clearTranslationError: true,
      clearTranslationWarning: true,
    );
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .validateTranslation(nativeSentence: item.sentenceInNative, userTranslation: trimmed);
      state = state.copyWith(
        isSubmittingTranslation: false,
        translationResult: result,
        lastUserTranslation: trimmed,
      );
      await _persistCurrentItemSnapshot();
    } catch (e) {
      state = state.copyWith(isSubmittingTranslation: false, translationError: _messageFor(e));
    }
  }

  /// ReviewScreen의 AudioRecorderWidget 녹음이 끝나면 호출된다. 발음은
  /// 학습자가 지금 번역해서 입력하려는 내용이 아니라, 문항에 고정된 정답
  /// 문장인 [ReviewItem.sentenceInTarget]을 기준으로 채점된다 — 그래서
  /// (이전에 있었다가 지금은 제거된 게이트와 달리) 번역을 먼저 제출해야
  /// 한다는 조건이 없으며, 이는 ReviewScreen에서 Play/Record가 화면
  /// 진입 시점부터 바로 사용 가능한 것과 일치한다.
  Future<void> analyzePronunciation(Uint8List audioBytes) async {
    final item = state.currentItem;
    if (item == null) return;
    state = state.copyWith(isAnalyzingPronunciation: true, clearPronunciationError: true);
    try {
      final result = await ref
          .read(geminiServiceProvider)
          .analyzePronunciation(audioBytes: audioBytes, targetSentence: item.sentenceInTarget);
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationResult: result);
      await _persistCurrentItemSnapshot();
    } catch (e) {
      state = state.copyWith(isAnalyzingPronunciation: false, pronunciationError: _messageFor(e));
    }
  }

  /// 현재 문항의 발음 분석 시도(결과 + 에러)를 초기화하고, 초기화된
  /// 상태를 다시 영속화한다.
  void resetPronunciationAttempt() {
    state = state.copyWith(clearPronunciationResult: true, clearPronunciationError: true);
    unawaited(_persistCurrentItemSnapshot());
  }

  /// 현재 문항의 제출된 번역, 채점 결과, (시도했다면) 발음 분석 결과를
  /// 영속화한다 — 이 스냅샷은 학습자가 이 문항을 넘어가기 전에 화면이
  /// 재마운트될 경우 `loadReviewSet()`이 복원하는 대상이다. 리뷰 세트
  /// 자체가 아직 한 번도 영속화되지 않았다면(`state.startedAt == null`)
  /// 아무 것도 하지 않는다.
  Future<void> _persistCurrentItemSnapshot() async {
    if (state.startedAt == null) return;
    await ref.read(sessionStateServiceProvider).writeReviewProgress(
          ReviewProgress(
            reviewItemList: state.items,
            reviewCurrentIndex: state.currentIndex,
            startedAt: state.startedAt!,
            currentUserTranslation: state.lastUserTranslation,
            currentTranslationResult: state.translationResult,
            currentPronunciationResult: state.pronunciationResult,
          ),
        );
  }

  /// ReviewScreen의 "Next Sentence" / "Finish Review & Start Learning"
  /// 버튼이 눌리면 호출된다. 현재 문항을 복습 완료로 표시한 뒤, 마지막
  /// 문항이 아니면 다음 문항으로 진행하고, 마지막 문항이면 리뷰 진행
  /// 상태를 지우고 [SessionStateService.markReviewedToday]로 "오늘 복습
  /// 끝냄"을 표시한 뒤 다음 학습 세션을 시작한다 — 이 표시가 없으면, 오늘
  /// 복습을 다 마친 뒤 새 학습에서 문장을 한 turn만 완료해도(그 문장이 TTS
  /// 캐시까지 생겨 곧바로 "복습 가능"한 상태가 되므로) 세션이 재평가되는
  /// 순간(예: 일일 turn 한도 도달, 앱 재시작) `_resolveLearningEntryRoute`가
  /// 그 문장을 다시 복습 대상으로 오인해 복습 화면으로 돌려보내는 버그가
  /// 있었다. 호출한 쪽(ReviewScreen)이 `context.go(route)`로 이동해야 할
  /// 라우트 문자열을 반환한다 — 계속 진행 중이면 [AppRoutes.review],
  /// 마지막이었다면 [startNextLearningSession]이 결정한 다음 학습 화면
  /// (Writing 또는 Shadowing Dictation) 라우트다.
  Future<String> advance() async {
    final item = state.currentItem;
    if (item != null) {
      await ref.read(reviewHistoryServiceProvider).markReviewed(item.sentenceInTarget);
    }

    final sessionStateService = ref.read(sessionStateServiceProvider);
    if (state.isLastItem) {
      await sessionStateService.clearReviewProgress();
      await sessionStateService.markReviewedToday();
      return startNextLearningSession(
        sessionStateService: sessionStateService,
        historyService: ref.read(historyServiceProvider),
      );
    }

    final nextIndex = state.currentIndex + 1;
    await sessionStateService.writeReviewProgress(
      ReviewProgress(
        reviewItemList: state.items,
        reviewCurrentIndex: nextIndex,
        startedAt: state.startedAt ?? DateTime.now(),
      ),
    );
    state = ReviewState(
      isLoading: false,
      items: state.items,
      currentIndex: nextIndex,
      startedAt: state.startedAt,
    );
    await _skipUnplayableItems();
    return AppRoutes.review;
  }

  /// ReviewScreen의 "Skip Review & Start Learning" 버튼이 눌리면 호출된다.
  /// 이미 복습 완료로 표시된 문항들의 기록은 그대로 두고(되돌리지 않음),
  /// 남은 문항들만 포기한 채 리뷰 진행 상태를 지우고, `advance()`와
  /// 마찬가지로 [SessionStateService.markReviewedToday]로 "오늘 복습 끝냄"을
  /// 표시한 뒤 다음 학습 세션을 시작한다 — 건너뛴 것도 "오늘 복습을 다시
  /// 보여줄 필요는 없음"으로 취급한다. `advance()`와 마찬가지로 다음에
  /// 이동할 라우트 문자열을 반환한다.
  Future<String> skip() async {
    final sessionStateService = ref.read(sessionStateServiceProvider);
    await sessionStateService.clearReviewProgress();
    await sessionStateService.markReviewedToday();
    return startNextLearningSession(
      sessionStateService: sessionStateService,
      historyService: ref.read(historyServiceProvider),
    );
  }

  /// 예외 [e]를 사용자에게 보여줄 메시지 문자열로 변환한다. `GeminiApiException`이면
  /// 실패 사유별 안내 메시지로, 그 외에는 일반적인 재시도 안내 메시지로 바꾼다.
  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }
}

/// [ReviewViewModel]/[ReviewState]를 노출하는 provider. ReviewScreen에서
/// `ref.watch`(상태 렌더링)와 `ref.read(...notifier)`(loadReviewSet/
/// submitTranslation/analyzePronunciation/advance/skip 호출)로 사용된다.
final reviewViewModelProvider = NotifierProvider<ReviewViewModel, ReviewState>(
  ReviewViewModel.new,
);
