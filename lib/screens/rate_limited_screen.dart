import 'package:flutter/material.dart';

import '../services/gemini_service.dart';
import '../widgets/end_session_button.dart';
import '../widgets/reset_api_key_button.dart';

/// 재생 버튼(AudioPlayButton)이 오디오를 로드하다가 Gemini API로부터 429
/// (rate limit) 응답을 받았을 때, `Navigator.of(context, rootNavigator: true)`로
/// go_router의 라우팅 스택 위에 그대로 push되는 전체 화면 — go_router의
/// route로 등록되어 있지 않으므로 `routerProvider`의 redirect 로직을 전혀
/// 거치지 않고 떠 있는다. "Retry" 버튼은 이 화면을 pop해서 원래 있던
/// 화면(재생 버튼이 있던 곳)으로 돌아가게 할 뿐이다 — 실제 재생 재시도는
/// 학습자가 돌아가서 재생 버튼을 다시 누르면 이루어진다. [ResetApiKeyButton]은
/// 기존과 동일하게 저장된 키를 지우고 앱을 재시작해 [ApiKeyScreen]으로
/// 돌아가게 한다. [EndSessionButton]은 다른 학습 화면들과 동일한 "학습
/// 종료" 동작을 그대로 재사용한다 — 지금까지 완료된 turn을 확정 저장하고
/// `/learning`으로 이동하며, 그곳의 redirect 로직이 오늘 아직 끝내지 않은
/// 복습이 있으면 복습 화면으로 보내준다.
class RateLimitedScreen extends StatelessWidget {
  /// 파라미터 없이 화면을 구성하는 생성자.
  const RateLimitedScreen({super.key});

  /// 안내 메시지 + "Retry"(이 화면을 닫음) + [ResetApiKeyButton] +
  /// [EndSessionButton]으로 구성된 `Scaffold`를 그린다.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usage Limit Reached')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userMessageForFailure(GeminiFailureReason.rateLimit),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 12),
                const ResetApiKeyButton(),
                const SizedBox(height: 12),
                const EndSessionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
