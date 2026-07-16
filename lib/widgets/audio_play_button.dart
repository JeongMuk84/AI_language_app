import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/audio_playback_registry.dart';

/// Play/pause toggle for an audio clip resolved lazily via [audioLoader] —
/// not fetched until the first play (tap or [autoPlay]), so a sentence the
/// learner never presses play on never spends a TTS call. Once resolved,
/// the bytes are kept for this widget's lifetime: pausing mid-playback and
/// tapping again resumes from that point; tapping again after the clip
/// finishes starts over from the beginning.
class AudioPlayButton extends StatefulWidget {
  const AudioPlayButton({
    super.key,
    required this.audioLoader,
    this.tooltip,
    this.autoPlay = false,
    this.enabled = true,
  });

  /// Resolves the audio bytes to play. Called once (on first play) and
  /// cached for this widget's lifetime — give the widget a fresh `key` to
  /// force it to resolve again (e.g. a genuinely new sentence).
  final Future<Uint8List> Function() audioLoader;
  final String? tooltip;

  /// Starts loading (and then playing) immediately when this widget is
  /// first built. Give the widget a fresh `key` (e.g. bump a counter) to
  /// force a "play from the start" restart, since otherwise Flutter would
  /// just keep reusing the same State and this would have no effect after
  /// the first build.
  final bool autoPlay;

  /// When false, renders the button inert (no tap, dimmed) without
  /// resolving [audioLoader] at all — e.g. ReviewScreen disables this
  /// until the learner has submitted a translation, so hearing the
  /// correct pronunciation can't short-circuit that step.
  final bool enabled;

  @override
  State<AudioPlayButton> createState() => _AudioPlayButtonState();
}

class _AudioPlayButtonState extends State<AudioPlayButton> {
  final _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;

  // Single source of truth for playback state — previously this was two
  // separate bools (`_isPlaying` / `_completed`) kept in sync by hand, and
  // a chained assignment bug (`_completed = _isPlaying = false`) silently
  // set both to false on completion instead of marking `_completed = true`.
  // That made the "did we just finish?" check always false, so the next
  // tap called `resume()` on a player that (in the default ReleaseMode)
  // had already released its source on completion — a no-op. Deriving
  // everything from one `PlayerState` removes the two-bools-out-of-sync
  // failure mode entirely.
  PlayerState _playerState = PlayerState.stopped;
  bool _hasStarted = false;

  Uint8List? _audioBytes;
  bool _isLoading = false;
  bool _loadFailed = false;

  bool get _isPlaying => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    AudioPlaybackRegistry.register(_player);
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      // Rewind so a subsequent resume() (if ever reached) or position
      // query starts clean; the actual replay happens via play() below.
      unawaited(_player.seek(Duration.zero));
    });
    if (widget.autoPlay && widget.enabled) {
      unawaited(_toggle());
    }
  }

  @override
  void dispose() {
    // Only clean up the player when this widget itself goes away — never
    // on playback completion, or a fresh play() next time would have
    // nothing to play through.
    _completeSub?.cancel();
    _stateSub?.cancel();
    AudioPlaybackRegistry.unregister(_player);
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

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

    final needsFreshStart = !_hasStarted || _playerState == PlayerState.completed;
    if (needsFreshStart) {
      _hasStarted = true;
      await _player.play(BytesSource(_audioBytes!));
    } else {
      await _player.resume();
    }
  }

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

    return IconButton.filled(
      iconSize: 36,
      tooltip: _loadFailed ? 'Failed to load — tap to retry' : widget.tooltip,
      onPressed: widget.enabled ? _toggle : null,
      icon: Icon(
        _loadFailed
            ? Icons.error_outline
            : (_isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
