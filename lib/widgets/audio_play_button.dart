import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/audio_playback_registry.dart';

/// [audioLoader]로 지연 로딩되는 오디오 클립의 재생/일시정지 토글 버튼.
/// ListeningHistoryScreen, ShadowingDictationScreen,
/// ShadowingPronunciationScreen, WritingListeningScreen, ReviewScreen에서
/// 문장/녹음 재생 버튼으로 쓰인다. 오디오는 최초 재생 시점(탭 또는
/// [autoPlay])까지 가져오지 않으므로, 학습자가 한 번도 재생 버튼을 누르지
/// 않은 문장은 TTS 호출 자체가 발생하지 않는다. 한 번 로드되면 이 위젯의
/// lifetime 동안 바이트를 계속 보관한다: 재생 중 일시정지 후 다시 탭하면
/// 그 지점부터 재생을 재개하고, 클립이 끝난 뒤 다시 탭하면 처음부터 다시
/// 재생한다.
class AudioPlayButton extends StatefulWidget {
  /// [audioLoader], [tooltip], [autoPlay], [enabled], [onBeforePlay] 값을
  /// 받아 위젯을 구성하는 생성자.
  const AudioPlayButton({
    super.key,
    required this.audioLoader,
    this.tooltip,
    this.autoPlay = false,
    this.enabled = true,
    this.onBeforePlay,
  });

  /// 재생할 오디오 바이트를 가져오는 콜백. 최초 재생 시 한 번만 호출되고
  /// 이 위젯의 lifetime 동안 캐싱된다 — 정말로 새로운 문장이라 다시
  /// 로드해야 한다면 위젯에 새로운 `key`를 줘서 강제로 다시 resolve하게
  /// 만들어야 한다.
  final Future<Uint8List> Function() audioLoader;

  /// 버튼에 표시할 tooltip 문구.
  final String? tooltip;

  /// 이 버튼이 재생을 시작하기(처음 시작이든, 일시정지에서 재개든) 직전에
  /// 호출된다 — 일시정지할 때는 호출되지 않는다. 선택 사항이며, 화면에
  /// [AudioPlayButton]이 한 번에 하나만 있는 화면에서는 필요 없다. 여러
  /// 개의 독립된 인스턴스가 동시에 있는 화면(예: 문장 목록)에서는 여기에
  /// `AudioPlaybackRegistry.pauseAll`을 넘겨서, 하나를 재생 시작할 때
  /// 재생 중이던 다른 행을 멈추게 하여 오디오가 겹쳐 재생되지 않도록 한다.
  final Future<void> Function()? onBeforePlay;

  /// 이 위젯이 처음 build될 때 즉시 로딩(그리고 재생)을 시작할지 여부.
  /// "처음부터 다시 재생"을 강제하려면 위젯에 새로운 `key`를 줘야 한다
  /// (예: 카운터를 증가시켜서) — 그렇지 않으면 Flutter는 같은 State를
  /// 계속 재사용하므로 첫 build 이후에는 이 값이 아무 효과가 없다.
  final bool autoPlay;

  /// false이면 [audioLoader]를 아예 resolve하지 않고 버튼을 비활성(탭 불가,
  /// 흐리게 표시) 상태로 렌더링한다 — 예를 들어 ReviewScreen은 학습자가
  /// 번역을 제출하기 전까지 이 값을 false로 두어, 정답 발음을 미리 들어서
  /// 그 단계를 건너뛰지 못하게 한다.
  final bool enabled;

  /// [_AudioPlayButtonState]를 생성한다.
  @override
  State<AudioPlayButton> createState() => _AudioPlayButtonState();
}

/// [AudioPlayButton]의 State. `AudioPlayer` 인스턴스와 재생 상태, 그리고
/// 로딩/재생 실패 시의 복구 로직을 관리한다.
class _AudioPlayButtonState extends State<AudioPlayButton> {
  // `final`이 아님 — 현재 인스턴스가 더 이상 재생할 수 없는 상태가 되면
  // [_recreatePlayer]가 이 값을 교체한다(왜 이런 일이 생기는지는 그
  // 문서 주석 참고).
  AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;

  // 재생 상태에 대한 단일 진실 공급원(single source of truth) — 예전에는
  // `_isPlaying` / `_completed`라는 두 개의 별도 bool을 수동으로 동기화하고
  // 있었는데, 체이닝된 대입 버그(`_completed = _isPlaying = false`)가
  // 재생 완료 시 `_completed`를 true로 세팅하지 않고 두 값을 모두
  // 조용히 false로 만들어 버렸다. 그 결과 "방금 재생이 끝났는가?" 체크가
  // 항상 false가 되어, 다음 탭에서 (기본 ReleaseMode에서) 이미 소스를
  // release한 플레이어에 `resume()`을 호출하게 되었다 — 아무 효과 없는
  // 호출이었다. 모든 상태를 하나의 `PlayerState`에서 파생시키면 두 bool이
  // 서로 어긋나는 이 실패 유형 자체가 사라진다.
  PlayerState _playerState = PlayerState.stopped;
  bool _hasStarted = false;

  Uint8List? _audioBytes;
  bool _isLoading = false;
  bool _loadFailed = false;

  /// 한 번의 재생성(recreate) 후 재시도([_playOrRecover] 참고)까지 거쳤음에도
  /// 현재 플레이어에서 play()/resume() 호출이 실패했음을 나타낸다 —
  /// [AudioPlayButton.audioLoader] 자체가 예외를 던진 경우를 뜻하는
  /// [_loadFailed]와는 별개이며, 이렇게 구분해야 tooltip에 실제로 어느
  /// 단계가 실패했는지 알려줄 수 있다.
  bool _playFailed = false;

  /// 현재 재생 중인지 여부. [_playerState]에서 파생된다.
  bool get _isPlaying => _playerState == PlayerState.playing;

  /// State 초기화 시 [_player]를 [_wireUpPlayer]로 연결하고, [AudioPlayButton.autoPlay]와
  /// [AudioPlayButton.enabled]가 모두 참이면 곧바로 [_toggle]을 호출해 재생을
  /// 시작한다.
  @override
  void initState() {
    super.initState();
    _wireUpPlayer(_player);
    if (widget.autoPlay && widget.enabled) {
      unawaited(_toggle());
    }
  }

  /// 주어진 [player]를 [AudioPlaybackRegistry]에 등록하고, 상태 변화와
  /// 재생 완료 스트림을 구독한다. 재생이 끝나면 다음 resume()이나 위치
  /// 조회가 깔끔하게 처음부터 시작되도록 위치를 0으로 되감는다(실제 다시
  /// 재생은 아래 play() 호출을 통해 이뤄진다).
  void _wireUpPlayer(AudioPlayer player) {
    AudioPlaybackRegistry.register(player);
    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _completeSub = player.onPlayerComplete.listen((_) {
      // 재생이 끝난 뒤 이후의 resume()(혹시라도 호출된다면)이나 위치
      // 조회가 깔끔한 상태에서 시작되도록 되감는다; 실제 재생 재개는
      // 아래 play() 호출을 통해 이뤄진다.
      unawaited(player.seek(Duration.zero));
    });
  }

  /// 이 위젯 자체가 트리에서 제거될 때만 플레이어를 정리한다 — 재생 완료
  /// 시에는 절대 호출하지 않는다. 그렇지 않으면 다음에 play()를 다시
  /// 호출할 때 재생할 대상 자체가 사라져 있게 된다.
  @override
  void dispose() {
    // 이 위젯 자체가 사라질 때만 플레이어를 정리한다 — 재생 완료
    // 시점에는 정리하지 않는다. 그렇지 않으면 다음 play() 호출 때
    // 재생할 소스가 아무것도 남아 있지 않게 된다.
    _completeSub?.cancel();
    _stateSub?.cancel();
    AudioPlaybackRegistry.unregister(_player);
    _player.dispose();
    super.dispose();
  }

  /// 버튼 탭에 대응하는 핵심 로직. 재생 중이면 일시정지하고, 아니라면
  /// (필요 시 [AudioPlayButton.onBeforePlay]를 호출한 뒤) [AudioPlayButton.audioLoader]로
  /// 오디오 바이트를 로드하고(아직 로드되지 않았다면) [_playOrRecover]로
  /// 실제 재생을 수행한다. 부작용: `_player`의 재생/일시정지 상태를
  /// 바꾸고, 로딩/실패 상태를 setState로 갱신한다.
  Future<void> _toggle() async {
    if (_isPlaying) {
      try {
        await _player.pause();
      } catch (error, stackTrace) {
        debugPrint('AudioPlayButton: pause() failed: $error\n$stackTrace');
      }
      return;
    }

    await widget.onBeforePlay?.call();

    if (_audioBytes == null) {
      if (_isLoading) return;
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
      try {
        final bytes = await widget.audioLoader();
        if (!mounted) return;
        setState(() {
          _audioBytes = bytes;
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        return;
      }
    }

    await _playOrRecover();
  }

  /// [_player]로 [_audioBytes]를 재생(또는 재개)한다. 네이티브 플레이어는
  /// 한 번도 dispose되지 않은 채로 화면이 떠 있는 도중에 조용히 재생
  /// 불가능한 상태가 될 수 있다 — 예를 들어 이 버튼이 같은 화면에서
  /// [AudioRecorderWidget]과 함께 쓰이는 경우, 녹음을 시작/중지하면 OS
  /// 오디오 세션이 마이크로 넘어가는데, 그 세션을 *이미 만들어져 있던*
  /// audioplayers 인스턴스로 다시 돌려주는 것은 보장되지 않는다. 반면
  /// 새로 만든 인스턴스(예: 새 화면으로 이동했을 때)는 세션을 깔끔하게
  /// 다시 협상(negotiate)한다 — 이것이 바로 "화면을 나갔다가 다시
  /// 들어오면 고쳐진다"고 관찰됐던 정확한 이유다. 버튼이 아무 동작도 하지
  /// 않으면서 영원히 "재생" 아이콘 상태로 멈춰 있게 두는 대신, 한 번의
  /// 복구 시도로 플레이어를 재생성한다 — 새 화면이 하는 것과 똑같은 일을
  /// 여기서 대신 해 주는 것이다 — 그래도 안 되면 그때 에러를 노출한다.
  ///
  /// 예전에는 `play()`를 await하기 *전에* `_hasStarted = true`를 무조건
  /// 먼저 세팅했고, `play()`도 `resume()`도 try/catch로 감싸지 않았다.
  /// 만약 호출이 실패하면 `_hasStarted`는 실제로는 재개할 게 아무것도
  /// 없는 상태에서 영원히 true로 남아 있었다 — 다음 탭은 계속
  /// `resume()`을 호출했고, 이는 로그도 남기지 않는 조용한 no-op이었으며,
  /// 화면을 나가는 것 외에는 복구할 방법이 없었다.
  Future<void> _playOrRecover() async {
    final needsFreshStart = !_hasStarted || _playerState == PlayerState.completed;
    try {
      if (needsFreshStart) {
        await _player.play(BytesSource(_audioBytes!));
      } else {
        await _player.resume();
      }
      _hasStarted = true;
      if (_playFailed && mounted) setState(() => _playFailed = false);
      return;
    } catch (error, stackTrace) {
      debugPrint('AudioPlayButton: play/resume failed on existing player, recreating: $error\n$stackTrace');
    }

    if (!mounted) return;
    try {
      await _recreatePlayer();
      await _player.play(BytesSource(_audioBytes!));
      _hasStarted = true;
      if (mounted) setState(() => _playFailed = false);
    } catch (error, stackTrace) {
      debugPrint('AudioPlayButton: play failed even after recreating the player: $error\n$stackTrace');
      if (mounted) setState(() => _playFailed = true);
    }
  }

  /// 현재 [_player]를 등록 해제·dispose하고 새로운 `AudioPlayer` 인스턴스로
  /// 교체한 뒤 [_wireUpPlayer]로 다시 연결한다. [_playOrRecover]가 기존
  /// 플레이어로의 재생/재개가 실패했을 때 호출하는 복구 경로다. 부작용:
  /// `_player`, `_hasStarted`, `_playerState`를 초기 상태로 되돌리고,
  /// [AudioPlaybackRegistry]에서 옛 플레이어를 해제하고 새 플레이어를
  /// 등록한다.
  Future<void> _recreatePlayer() async {
    final oldPlayer = _player;
    await _completeSub?.cancel();
    await _stateSub?.cancel();
    AudioPlaybackRegistry.unregister(oldPlayer);
    try {
      await oldPlayer.dispose();
    } catch (error, stackTrace) {
      debugPrint('AudioPlayButton: disposing the broken player failed (continuing anyway): $error\n$stackTrace');
    }

    final newPlayer = AudioPlayer();
    _wireUpPlayer(newPlayer);
    _player = newPlayer;
    _hasStarted = false;
    _playerState = PlayerState.stopped;
  }

  /// 현재 상태(로딩 중 / 재생 중 / 일시정지 / 로드 실패 / 재생 실패)에 따라
  /// 로딩 스피너 또는 재생·일시정지·에러 아이콘이 표시된 `IconButton`을
  /// 그린다. 실패 시에는 tooltip 문구가 "로드 실패"인지 "재생 실패"인지에
  /// 따라 달라진다.
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final failed = _loadFailed || _playFailed;
    return IconButton.filled(
      iconSize: 36,
      tooltip: _loadFailed
          ? 'Failed to load — tap to retry'
          : (_playFailed ? 'Failed to play — tap to retry' : widget.tooltip),
      onPressed: widget.enabled ? _toggle : null,
      icon: Icon(
        failed
            ? Icons.error_outline
            : (_isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
