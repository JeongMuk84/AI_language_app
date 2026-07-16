import 'package:audioplayers/audioplayers.dart';

/// Tracks every live [AudioPlayer] created by [AudioPlayButton] instances,
/// so anything about to open a modal (which briefly keeps the platform
/// thread busy) can pause them first.
///
/// This is a mitigation, not a fix, for a known unfixed `audioplayers_windows`
/// bug: its MediaFoundation playback-state callback fires on a non-platform
/// (MTA) thread and gets forwarded to Flutter's EventChannel from there,
/// which can crash — see https://github.com/bluefireteam/audioplayers/pull/1961.
/// Pausing playback before a dialog opens shrinks the window in which that
/// stray callback can race the dialog's message loop; it doesn't eliminate
/// the underlying threading bug, which lives in the plugin/engine.
abstract final class AudioPlaybackRegistry {
  static final Set<AudioPlayer> _activePlayers = {};

  static void register(AudioPlayer player) => _activePlayers.add(player);

  static void unregister(AudioPlayer player) => _activePlayers.remove(player);

  static Future<void> pauseAll() async {
    for (final player in _activePlayers.toList()) {
      try {
        await player.pause();
      } catch (_) {
        // Best-effort: a player mid-dispose or already stopped shouldn't
        // block whatever triggered this pause.
      }
    }
  }
}
