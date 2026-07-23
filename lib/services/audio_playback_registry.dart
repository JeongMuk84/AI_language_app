import 'package:audioplayers/audioplayers.dart';

/// [AudioPlayButton]이 만들어내는 모든 살아있는 [AudioPlayer]를 추적해서,
/// 모달을 띄우려는 코드(모달을 여는 동안 플랫폼 스레드가 잠깐 바빠진다)가
/// 그 전에 재생 중인 오디오를 먼저 일시정지시킬 수 있게 해주는 레지스트리.
///
/// 이것은 근본적인 수정이 아니라 완화책(mitigation)이다: 아직 고쳐지지 않은
/// `audioplayers_windows`의 알려진 버그 때문인데, 이 플러그인의
/// MediaFoundation 재생 상태 콜백이 플랫폼 스레드가 아닌(MTA) 스레드에서
/// 발생해 거기서 Flutter의 EventChannel로 전달되면서 크래시를 일으킬 수
/// 있다 (https://github.com/bluefireteam/audioplayers/pull/1961 참고).
/// 다이얼로그를 열기 전에 재생을 멈춰두면 그 엉뚱한 콜백이 다이얼로그의
/// 메시지 루프와 경합(race)할 수 있는 시간창을 줄여줄 뿐이며, 플러그인/엔진에
/// 있는 근본적인 스레딩 버그 자체를 없애지는 못한다.
abstract final class AudioPlaybackRegistry {
  static final Set<AudioPlayer> _activePlayers = {};

  /// [player]를 활성 플레이어 집합에 등록한다.
  /// `audio_play_button.dart`의 `AudioPlayButton`이 새 `AudioPlayer`를 만들
  /// 때마다(초기 생성 시점 및 위젯 업데이트로 플레이어가 교체될 때) 호출한다.
  /// 부작용: 정적 `_activePlayers` 집합에 [player]를 추가한다.
  static void register(AudioPlayer player) => _activePlayers.add(player);

  /// [player]를 활성 플레이어 집합에서 제거한다.
  /// `AudioPlayButton`이 dispose되거나 이전 플레이어가 새 플레이어로
  /// 교체될 때(`audio_play_button.dart`) 호출되어, 더 이상 존재하지 않는
  /// 플레이어를 [pauseAll]이 건드리지 않도록 한다.
  /// 부작용: 정적 `_activePlayers` 집합에서 [player]를 제거한다.
  static void unregister(AudioPlayer player) => _activePlayers.remove(player);

  /// 현재 등록된 모든 [AudioPlayer]를 일시정지한다.
  ///
  /// `listening_history_icon_button.dart`, `dictionary_icon_button.dart`,
  /// `settings_icon_button.dart`가 각각 듣기 기록/사전/설정 모달을 열기 직전에
  /// 호출하며, `listening_history_screen.dart`에서도 화면 내 오디오 위젯의
  /// `onBeforePlay` 콜백으로 넘겨져 다른 재생을 먼저 멈추는 데 쓰인다.
  /// 부작용: 등록된 각 플레이어에 대해 `pause()`를 호출한다. 이미 정지되었거나
  /// dispose 중인 플레이어에서 예외가 나도 무시하고(best-effort) 다음
  /// 플레이어로 진행한다.
  static Future<void> pauseAll() async {
    for (final player in _activePlayers.toList()) {
      try {
        await player.pause();
      } catch (_) {
        // Best-effort: a player mid-dispose or already stopped shouldn't
        // block whatever triggered this pause.
        // (dispose 중이거나 이미 정지된 플레이어 때문에 이 호출을 트리거한
        // 동작이 막혀서는 안 되므로 최선을 다하는 수준으로만 처리한다.)
      }
    }
  }
}
