import 'package:flutter/material.dart';

/// 평가판 만료 시 표시되는 화면 — `main()`이 `TrialGateService.isExpired()`가
/// true일 때 이 화면 하나만을 `home`으로 둔 최소한의 `MaterialApp`을
/// 곧바로 `runApp`한다(`ProviderScope`/`RestartWidget`/`GoRouter` 전부
/// 건너뜀). 의도적으로 재시도 버튼도, 다른 화면으로 갈 방법(Settings의
/// "Reset All Data" 포함)도 전혀 두지 않는다 — 이 화면이 곧 앱의 종점이다.
class TrialExpiredScreen extends StatelessWidget {
  /// 파라미터 없이 화면을 구성하는 생성자.
  const TrialExpiredScreen({super.key});

  /// 만료 안내 문구만 담은 `Scaffold`를 그린다. 뒤로 갈 라우트 자체가
  /// 없으므로(이 화면이 `MaterialApp.home`의 유일한 콘텐츠) 시스템 뒤로가기도
  /// 빠져나갈 방법이 되지 않는다.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This trial version has expired.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
}
