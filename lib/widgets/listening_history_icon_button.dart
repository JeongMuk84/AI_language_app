import 'package:flutter/material.dart';

import '../screens/listening_history_screen.dart';
import '../services/audio_playback_registry.dart';

/// "Listening History 열기" 표준 AppBar 액션 — [DictionaryIconButton]/
/// `SettingsIconButton`과 구조와 배치가 동일하다(`buildAppBarWithSettings`
/// 참고). `buildAppBarWithSettings`를 통해 ApiKeyScreen을 제외한 모든
/// 화면의 AppBar에 표시된다.
class ListeningHistoryIconButton extends StatelessWidget {
  /// 파라미터 없이 위젯을 구성하는 생성자.
  const ListeningHistoryIconButton({super.key});

  /// 오디오 재생을 모두 멈춘 뒤 [ListeningHistoryScreen]을 다이얼로그로
  /// 연다. 부작용: `AudioPlaybackRegistry.pauseAll()`을 호출해 재생 중인
  /// 오디오를 멈추고, `showDialog`로 화면 위에 다이얼로그를 띄운다.
  Future<void> _openListeningHistory(BuildContext context) async {
    // SettingsIconButton/DictionaryIconButton과 동일한 완화 조치이며
    // 이유도 동일하다(AudioPlaybackRegistry 참고).
    await AudioPlaybackRegistry.pauseAll();
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (context) => const ListeningHistoryScreen());
  }

  /// 헤드폰 아이콘의 `IconButton`을 그리며, 탭하면
  /// [_openListeningHistory]를 호출한다.
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.headphones),
      tooltip: 'Listening History',
      onPressed: () => _openListeningHistory(context),
    );
  }
}
