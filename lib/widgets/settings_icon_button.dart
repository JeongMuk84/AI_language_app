import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/service_providers.dart';
import '../screens/settings_dialog.dart';
import '../services/audio_playback_registry.dart';

/// ApiKeyScreen을 제외한 모든 화면에서 쓰이는 "Settings 열기" 표준 AppBar
/// 액션. ApiKeyScreen에는 표시되지 않는다 — 아직 설정할 것이 없기
/// 때문이다. 보통 직접 쓰이기보다는 [buildAppBarWithSettings]를 통해
/// 붙는다.
///
/// 모든 화면이 서로 어긋나지 않도록 하나의 위젯으로 뽑아냈다: 아이콘
/// 색상을 여기서 하드코딩하지 않고 `AppBarTheme.foregroundColor`(White/
/// Black 테마별로 설정됨)에 맡겨서, 어느 테마에서도 AppBar 배경에
/// 파묻히는 일이 없게 한다.
class SettingsIconButton extends StatelessWidget {
  /// 파라미터 없이 위젯을 구성하는 생성자.
  const SettingsIconButton({super.key});

  /// 재생 중인 오디오를 멈추고 config.json을 미리 읽은 뒤 [SettingsDialog]를
  /// 다이얼로그로 연다. 부작용: `AudioPlaybackRegistry.pauseAll()`을
  /// 호출하고, `configServiceProvider`로 config를 읽으며, `showDialog`로
  /// 화면 위에 다이얼로그를 띄운다.
  Future<void> _openSettings(BuildContext context) async {
    // 알려진, 아직 고쳐지지 않은 audioplayers_windows 스레딩 버그
    // (AudioPlaybackRegistry 참고)를 완화한다 — 모달이 열리기 전에 재생
    // 중인 오디오를 모두 멈춘다. 이 버그를 재현 가능하게 만든 트리거가
    // 바로 그 시점이었기 때문이다.
    await AudioPlaybackRegistry.pauseAll();
    if (!context.mounted) return;

    // config.json을 SettingsDialog의 initState 안이 아니라 다이얼로그를
    // 열기 *전에* 미리 읽는다. 다이얼로그가 이미 표시된 뒤에 읽으면
    // setState를 통해 그 안의 내용이 바뀌었다 — 다이얼로그 route 자신의
    // 약 150ms짜리 진입 전환이 진행되는 도중에, 작은 로딩 placeholder에서
    // 완전한 폼으로 구조가 바뀌는 것이다. 그 전환과 경쟁하는 구조적 크기
    // 변화가 바로 프레임워크의 '!semantics.parentDataDirty' assertion을
    // 유발한 원인이었다 — 오디오가 전혀 관여하지 않아도(단순 Scaffold +
    // 이 버튼만으로도) 결정적으로 재현되는 Windows 통합 테스트 재현으로
    // 확인됨. config.json을 읽는 것은 빠른 로컬 파일 I/O이므로, 미리
    // 읽어 두면 다이얼로그 안에서 로딩 placeholder가 아예 나타나지
    // 않게 할 수 있다.
    final config = await ProviderScope.containerOf(
      context,
    ).read(configServiceProvider).readConfig();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(initialConfig: config),
    );
  }

  /// 톱니바퀴 아이콘의 `IconButton`을 그리며, 탭하면 [_openSettings]를
  /// 호출한다.
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
      onPressed: () => _openSettings(context),
    );
  }
}
