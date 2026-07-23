import 'package:flutter/material.dart';

/// `/learning`(`AppRoutes.learning`)에 연결되는, 부트스트랩 전용 임시
/// 착지 화면이다 — 라우터의 redirect(`app_router.dart`의
/// `_resolveLearningEntryRoute`)가 거의 즉시 이 라우트를 실제 목적지(학습
/// 루프의 한 화면, 예: WritingScreen/ShadowingDictationScreen, 또는
/// ReviewScreen)로 바꿔치기하므로, 이 화면은 한 프레임 이상 보이는 경우가
/// 거의 없다.
class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  /// 로딩 인디케이터만 보여주는 빈 Scaffold를 그린다. redirect가 곧바로
  /// 다른 화면으로 이동시키므로 실제로 눈에 띄는 UI는 없다.
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
