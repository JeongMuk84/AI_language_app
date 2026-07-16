import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const _waveformSampleCount = 48;
const _samplingInterval = Duration(milliseconds: 80);

/// A single record/stop toggle button with an oscilloscope-style waveform
/// display. Recording starts on the first tap; tapping again stops it and —
/// with no separate submit step — automatically hands the recorded bytes to
/// [onRecordingComplete].
class AudioRecorderWidget extends StatefulWidget {
  const AudioRecorderWidget({super.key, required this.onRecordingComplete, this.enabled = true});

  final ValueChanged<Uint8List> onRecordingComplete;

  /// When false, renders the record button inert (no tap, dimmed) — e.g.
  /// ReviewScreen disables this until the learner has submitted a
  /// translation, so pronunciation practice can't happen before that.
  final bool enabled;

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSub;
  final Queue<double> _samples = Queue<double>.of(List.filled(_waveformSampleCount, 0.0));
  bool _isRecording = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isRecording) {
      await _stop();
    } else {
      await _start();
    }
  }

  void _resetWaveform() {
    _samples
      ..clear()
      ..addAll(List.filled(_waveformSampleCount, 0.0));
  }

  Future<void> _start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission || !mounted) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _resetWaveform();
    });

    _amplitudeSub = _recorder.onAmplitudeChanged(_samplingInterval).listen((amplitude) {
      if (!mounted) return;
      // dBFS is typically in the range [-45, 0]; normalize to 0..1.
      final normalized = ((amplitude.current + 45) / 45).clamp(0.0, 1.0);
      setState(() {
        _samples.addLast(normalized);
        if (_samples.length > _waveformSampleCount) _samples.removeFirst();
      });
    });
  }

  Future<void> _stop() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _resetWaveform();
    });

    if (path != null) {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      widget.onRecordingComplete(bytes);
    }
    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 260,
          height: 90,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _OscilloscopePainter(
              samples: _samples.toList(growable: false),
              isActive: _isRecording,
              waveColor: colorScheme.primary,
              gridColor: colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(height: 12),
        IconButton.filled(
          iconSize: 40,
          onPressed: (widget.enabled && !_isProcessing) ? _toggle : null,
          icon: _isProcessing
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isRecording ? Icons.stop : Icons.mic),
        ),
      ],
    );
  }
}

/// Draws a smooth, center-mirrored amplitude trace over a faint grid,
/// evoking an analog oscilloscope. Since `record`'s amplitude stream only
/// gives a magnitude (not a signed waveform), the "trace" is an envelope —
/// the samples plotted above the centerline and mirrored below it — rather
/// than a literal waveform, which is the closest a magnitude-only signal
/// can get to that look.
class _OscilloscopePainter extends CustomPainter {
  _OscilloscopePainter({
    required this.samples,
    required this.isActive,
    required this.waveColor,
    required this.gridColor,
  });

  final List<double> samples;
  final bool isActive;
  final Color waveColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor.withAlpha(60)
      ..strokeWidth = 1;

    const horizontalDivisions = 4;
    for (var i = 0; i <= horizontalDivisions; i++) {
      final y = size.height / horizontalDivisions * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    const verticalDivisions = 10;
    for (var i = 0; i <= verticalDivisions; i++) {
      final x = size.width / verticalDivisions * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final midY = size.height / 2;
    final wavePaint = Paint()
      ..color = waveColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (!isActive || samples.isEmpty) {
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), wavePaint);
      return;
    }

    final stepX = samples.length > 1 ? size.width / (samples.length - 1) : size.width;
    final topPoints = <Offset>[
      for (var i = 0; i < samples.length; i++)
        Offset(stepX * i, midY - samples[i].clamp(0.0, 1.0) * midY * 0.85),
    ];

    canvas.drawPath(_smoothPath(topPoints), wavePaint);
    canvas.drawPath(_smoothPath([for (final p in topPoints) Offset(p.dx, 2 * midY - p.dy)]), wavePaint);
  }

  /// Builds a smooth curve through [points] using quadratic Bézier segments
  /// between successive midpoints, rather than straight line-to-line
  /// segments, so the trace reads as a continuous curve.
  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midpoint = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant _OscilloscopePainter oldDelegate) {
    return !identical(oldDelegate.samples, samples) ||
        oldDelegate.isActive != isActive ||
        oldDelegate.waveColor != waveColor ||
        oldDelegate.gridColor != gridColor;
  }
}
