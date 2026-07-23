import 'package:flutter/material.dart';

/// 앱 전체를 감싸서 어느 하위 위젯에서든 프로세스를 종료하지 않고도 완전한
/// 재시작 — 새로운 `ProviderScope`(모든 provider 리셋)와 새로운 위젯
/// 트리 — 을 강제할 수 있게 해준다. `main.dart`에서 앱 루트를 감싸는 데
/// 쓰이며, target language를 전환한 뒤([ResetApiKeyButton]을 통한 API 키
/// 초기화 시에도) 호출된다 — 이 흐름은 config.json과 메모리에 있는 모든
/// provider를 처음부터 다시 만들어야 하기 때문이다.
class RestartWidget extends StatefulWidget {
  /// 재시작 시 다시 만들어질 하위 트리 [child]를 받아 위젯을 구성한다.
  const RestartWidget({super.key, required this.child});

  /// 재시작 대상이 되는 하위 위젯 트리(보통 앱 루트).
  final Widget child;

  /// [context]의 조상 중 가장 가까운 [RestartWidget]을 찾아 재시작을
  /// 트리거한다. 부작용: 해당 State의 key를 새로 발급해 하위 트리 전체를
  /// 다시 mount시킨다.
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  /// [_RestartWidgetState]를 생성한다.
  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

/// [RestartWidget]의 State. 현재 `key` 값을 보관하며, 재시작 요청 시 새
/// `UniqueKey`로 교체해 하위 트리를 통째로 다시 만들게 한다.
class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  /// [_key]를 새로운 `UniqueKey`로 교체한다. 부작용: `setState`를 호출해
  /// [KeyedSubtree]가 새 key로 다시 빌드되게 하며, 그 결과 `widget.child`
  /// 이하 전체 트리(및 새 `ProviderScope`)가 처음부터 다시 만들어진다.
  void _restart() {
    setState(() {
      _key = UniqueKey();
    });
  }

  /// [_key]를 key로 갖는 [KeyedSubtree]로 [RestartWidget.child]를 감싸
  /// 반환한다.
  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
