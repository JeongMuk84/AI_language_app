import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/service_providers.dart';
import '../router/app_router.dart';
import '../services/gemini_service.dart';

/// 새 학습을 시작하려는 모든 진입점(`LearningScreen`을 통해 도달하는 기본
/// 라우팅 분기, `ReviewScreen`의 "Start Learning"/"Finish Review & Start
/// Learning")이 공통으로 호출하는 진입 함수. 판단 기준은 오직 "오늘 학습
/// 세트(10문장)를 이미 생성한 적이 있는가" 하나뿐이다 — 각 화면이 개별적으로
/// 이 판단을 반복하지 않도록 여기 한 곳에 모아둔다.
///
/// 오늘치 `SessionStateService.readSentenceQueue()`가 아직 없으면(오늘 첫
/// 학습 시작이든, API 키를 재발급하고 재시작한 뒤 세션은 이미 finalize돼
/// 있지만 아직 새 세트를 만들지 않은 상태로 되돌아온 경우든) [TopicInputDialog]
/// 를 `barrierDismissible: false`로 띄워, 반드시 "Start"를 눌러야만(뒤로
/// 가기나 바깥 탭으로는 닫히지 않는다) 닫히게 한다. 이미 오늘 세트가
/// 있으면(진행 중이던 세션을 그냥 재개하는 정상적인 경우 등) 다이얼로그 없이
/// 곧바로 [startNextLearningSession]으로 넘어간다. 어느 경로든 마지막에는
/// 결정된 라우트로 `context.go(...)`한다.
/// [context]: 다이얼로그를 띄우고 최종적으로 내비게이션할 때 쓰는 컨텍스트 —
/// 호출자(`LearningScreen`/`ReviewScreen`)의 것을 그대로 전달받는다.
/// [ref]: 서비스 provider들을 읽기 위한 참조.
/// 부작용: 오늘 세트가 없으면 모달 다이얼로그를 띄우고(그 안에서 Gemini API
/// 호출 + `sentence_queue.json` 저장), 새 세션을 시작(`session_state.json`
/// 갱신)한 뒤 라우팅한다.
Future<void> startNextLearningInteractive(BuildContext context, WidgetRef ref) async {
  final sessionStateService = ref.read(sessionStateServiceProvider);
  final historyService = ref.read(historyServiceProvider);

  final queue = await sessionStateService.readSentenceQueue();

  final String route;
  if (queue == null) {
    if (!context.mounted) return;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const TopicInputDialog(),
    );
    // TopicInputDialog only ever closes via a successful "Start" (which
    // always pops a route string) — barrierDismissible: false and its own
    // PopScope(canPop: false) mean there is no way to get a null result in
    // practice, but this guards against it anyway rather than crashing.
    if (result == null) return;
    route = result;
  } else {
    route = await startNextLearningSession(
      sessionStateService: sessionStateService,
      historyService: historyService,
    );
  }

  if (context.mounted) context.go(route);
}

/// 오늘의 대화 주제를 입력받는 모달 다이얼로그. `startNextLearningInteractive`
/// 가 오늘 학습 세트가 아직 없을 때만 띄운다. Settings/Dictionary 다이얼로그와
/// 동일하게 `AlertDialog` 기반이지만, 그 둘과 달리 취소하고 나갈 수 있는
/// 경로가 없다 — `barrierDismissible: false`(호출부)와 `PopScope(canPop:
/// false)`(이 위젯)로 뒤로 가기/바깥 탭 모두 막아, 반드시 "Start"를 눌러야만
/// 닫힌다.
///
/// "Start"를 누르면 `GeminiService.generateDailySentenceSet`으로 오늘
/// 하루치 10문장(쉐도잉 5 + 작문 5)을 한 번에 미리 생성해
/// `SessionStateService`에 저장한다 — 입력이 비어 있거나 무의미하면
/// Gemini가 조용히 무작위 주제로 대체한다(이 다이얼로그는 그 판별 결과를
/// 사용자에게 따로 안내하지 않는다). 생성이 끝나면 `startNextLearningSession`
/// 으로 세션을 시작하고, 그 결과 라우트를 `Navigator.pop`으로 호출부(
/// `startNextLearningInteractive`)에 돌려준다 — 실제 화면 이동은 호출부의
/// 몫이다.
class TopicInputDialog extends ConsumerStatefulWidget {
  const TopicInputDialog({super.key});

  /// 이 위젯의 상태 객체([_TopicInputDialogState])를 생성한다.
  @override
  ConsumerState<TopicInputDialog> createState() => _TopicInputDialogState();
}

/// [TopicInputDialog]의 State. 주제 입력 텍스트필드 컨트롤러와, 생성 진행
/// 중/실패 여부를 로컬로 관리한다.
class _TopicInputDialogState extends ConsumerState<TopicInputDialog> {
  final _controller = TextEditingController();
  bool _isStarting = false;
  String? _error;

  /// 위젯이 트리에서 제거될 때 [_controller]를 해제해 메모리 누수를 막는다.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// "Start" 버튼이 눌리면 호출된다. 오늘 하루치 문장 세트를 생성/저장한 뒤
  /// 다음 학습 세션을 시작하고, 그 결과 라우트를 들고 이 다이얼로그를 닫는다
  /// (`Navigator.pop(context, route)`) — 판별 결과(무작위 주제로
  /// 대체됐는지)와 무관하게 항상 이 경로를 그대로 따른다.
  Future<void> _start() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });
    try {
      final sessionStateService = ref.read(sessionStateServiceProvider);
      final historyService = ref.read(historyServiceProvider);
      final history = await ref.read(conversationHistoryServiceProvider).readAll();
      final cumulativeSummary = await ref.read(learningSummaryServiceProvider).readCumulativeSummary();
      final difficultyScore = await ref.read(difficultyProgressionServiceProvider).readTodayScore();

      final queue = await ref
          .read(geminiServiceProvider)
          .generateDailySentenceSet(
            topicInput: _controller.text,
            history: history,
            cumulativeSummary: cumulativeSummary,
            difficultyScore: difficultyScore,
          );
      await sessionStateService.writeSentenceQueue(queue);

      final route = await startNextLearningSession(
        sessionStateService: sessionStateService,
        historyService: historyService,
      );
      if (!mounted) return;
      Navigator.of(context).pop(route);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _error = _messageFor(e);
      });
    }
  }

  /// 예외 [e]를 사용자에게 보여줄 메시지 문자열로 변환한다. `GeminiApiException`이면
  /// 실패 사유별 안내 메시지로, 그 외에는 일반적인 재시도 안내 메시지로 바꾼다.
  String _messageFor(Object e) {
    if (e is GeminiApiException) return userMessageForFailure(e.reason, e.message);
    return 'Something went wrong. Please try again.';
  }

  /// 주제 입력 폼(로딩 중이 아닐 때) 또는 로딩 인디케이터(생성 중일 때)를
  /// 담은 [AlertDialog]를 그린다. 뒤로 가기는 [PopScope]로 막는다 —
  /// Settings/Dictionary 다이얼로그와 달리 "Cancel"/"Close" 액션이 없다.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('New Session'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _isStarting
                ? const [
                    SizedBox(height: 8),
                    Center(child: CircularProgressIndicator()),
                    SizedBox(height: 16),
                    Text('Preparing today\'s sentences...', textAlign: TextAlign.center),
                  ]
                : [
                    const Text('What would you like to talk about today?'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _start(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Leave empty for a random topic',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
          ),
        ),
        actions: _isStarting
            ? const []
            : [FilledButton(onPressed: _start, child: const Text('Start'))],
      ),
    );
  }
}
