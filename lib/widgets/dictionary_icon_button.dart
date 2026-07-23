import 'package:flutter/material.dart';

import '../screens/dictionary_screen.dart';
import '../services/audio_playback_registry.dart';

/// "Dictionary 열기" 표준 AppBar 액션 — `SettingsIconButton`과 구조와
/// 배치가 동일하다(`buildAppBarWithSettings` 참고). `buildAppBarWithSettings`를
/// 통해 ApiKeyScreen을 제외한 모든 화면의 AppBar에 표시된다.
class DictionaryIconButton extends StatelessWidget {
  /// 파라미터 없이 위젯을 구성하는 생성자.
  const DictionaryIconButton({super.key});

  /// 오디오 재생을 모두 멈춘 뒤 [DictionaryScreen]을 다이얼로그로 연다.
  /// 부작용: `AudioPlaybackRegistry.pauseAll()`을 호출해 재생 중인 오디오를
  /// 멈추고, `showDialog`로 화면 위에 다이얼로그를 띄운다.
  Future<void> _openDictionary(BuildContext context) async {
    // SettingsIconButton과 동일한 완화 조치이며 이유도 동일하다: 오디오가
    // 재생 중일 때 모달이 열리는 것이 알려진 audioplayers_windows 스레딩
    // 버그(AudioPlaybackRegistry 참고)를 재현시키는 트리거다 — Settings에만
    // 국한된 문제가 아니므로, 이 화면들에서 열리는 모든 다이얼로그에
    // 똑같이 필요하다.
    await AudioPlaybackRegistry.pauseAll();
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (context) => const DictionaryScreen());
  }

  /// 책 아이콘의 `IconButton`을 그리며, 탭하면 [_openDictionary]를 호출한다.
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_book),
      tooltip: 'Dictionary',
      onPressed: () => _openDictionary(context),
    );
  }
}
