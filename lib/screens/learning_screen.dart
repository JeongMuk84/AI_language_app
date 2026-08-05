import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'topic_input_dialog.dart';

/// `/learning`(`AppRoutes.learning`)에 연결되는 부트스트랩 착지 화면이다.
/// 라우터의 redirect(`app_router.dart`의 `_resolveLearningEntryRoute`)가
/// 새 학습을 시작해야 한다고 판단했을 때(더 이상 재개할 세션/복습이 없는
/// 경우) 도달하며, 그 판단 이상의 실제 실행 — 오늘 학습 세트가 아직
/// 없으면 `TopicInputDialog`를 먼저 띄우고, 있으면 곧바로 다음 학습
/// 화면으로 — 은 이 화면의 [initState]가
/// [startNextLearningInteractive](`topic_input_dialog.dart`)를 호출해
/// 담당한다. 라우터 redirect 콜백 자신은 다이얼로그를 띄울 수 없으므로
/// (화면 트리 구성 이전에 실행되고 반복 호출될 수 있다) 이 화면이 그
/// 실행을 넘겨받는 유일한 지점이다. 오늘 세트가 이미 있는 경우에는
/// 다이얼로그 없이 다음 화면으로 거의 즉시 넘어가므로, 그 경우엔 여전히
/// 한 프레임 이상 보이는 일이 거의 없다.
class LearningScreen extends ConsumerStatefulWidget {
  const LearningScreen({super.key});

  /// 이 위젯의 상태 객체([_LearningScreenState])를 생성한다.
  @override
  ConsumerState<LearningScreen> createState() => _LearningScreenState();
}

/// [LearningScreen]의 State. 마운트되자마자
/// [startNextLearningInteractive]를 시작시키는 것 외에는 로컬 상태가 없다.
class _LearningScreenState extends ConsumerState<LearningScreen> {
  /// 화면이 처음 마운트될 때 [_start]를(완료를 기다리지 않고) 시작시킨다.
  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  /// [startNextLearningInteractive]를 호출한다. `Future.microtask`로 인한
  /// 비동기 간격 이후 위젯이 이미 unmount됐을 수 있으므로, `context`를
  /// 쓰기 직전에 [mounted]를 확인한다.
  Future<void> _start() async {
    if (!mounted) return;
    await startNextLearningInteractive(context, ref);
  }

  /// 로딩 인디케이터만 보여주는 빈 Scaffold를 그린다 —
  /// [startNextLearningInteractive]가 다이얼로그를 띄우거나 다음 화면으로
  /// 넘어가기 전까지 잠깐 보이는 배경이다.
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
