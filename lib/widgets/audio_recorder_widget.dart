import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:record/record.dart';

const _waveformSampleCount = 48;
const _samplingInterval = Duration(milliseconds: 80);

/// 오실로스코프 스타일 파형 표시가 함께 있는 녹음/정지 단일 토글 버튼.
/// ShadowingPronunciationScreen, WritingListeningScreen, ReviewScreen에서
/// 발음 녹음용으로 쓰인다. 첫 탭에서 녹음이 시작되고, 다시 탭하면 녹음이
/// 멈추며 — 별도의 제출 단계 없이 — 녹음된 바이트가 자동으로
/// [onRecordingComplete]로 전달된다.
class AudioRecorderWidget extends StatefulWidget {
  /// [onRecordingComplete] 콜백과 [enabled] 여부를 받아 위젯을 구성한다.
  const AudioRecorderWidget({super.key, required this.onRecordingComplete, this.enabled = true});

  /// 녹음이 끝났을 때 녹음된 오디오 바이트(WAV)를 전달받는 콜백.
  final ValueChanged<Uint8List> onRecordingComplete;

  /// false이면 녹음 버튼을 비활성(탭 불가, 흐리게 표시) 상태로 렌더링한다
  /// — 예를 들어 ReviewScreen은 학습자가 번역을 제출하기 전까지 이 값을
  /// false로 두어, 그 전에 발음 연습이 이뤄지지 못하게 한다.
  final bool enabled;

  /// [_AudioRecorderWidgetState]를 생성한다.
  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

/// [AudioRecorderWidget]의 State. 실제 녹음기(`AudioRecorder`) 제어, 진폭
/// 스트림 구독을 통한 파형 샘플 갱신, 녹음 시작/중지 흐름을 담당한다.
class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSub;
  final Queue<double> _samples = Queue<double>.of(List.filled(_waveformSampleCount, 0.0));
  bool _isRecording = false;
  bool _isProcessing = false;

  /// 진폭 스트림 구독을 취소하고 [_recorder]를 dispose한다.
  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  /// 녹음 버튼 탭에 대응한다: 녹음 중이면 [_stop], 아니면 [_start]를
  /// 호출한다.
  Future<void> _toggle() async {
    if (_isRecording) {
      await _stop();
    } else {
      await _start();
    }
  }

  /// 파형 표시용 샘플 큐를 모두 0.0으로 채워 초기 상태(평평한 선)로
  /// 되돌린다.
  void _resetWaveform() {
    _samples
      ..clear()
      ..addAll(List.filled(_waveformSampleCount, 0.0));
  }

  /// 마이크 권한을 확인한 뒤(필요하면 OS 권한 요청을 트리거) 임시 디렉터리에
  /// WAV 파일로 녹음을 시작하고, 진폭 스트림을 구독해 파형 샘플을
  /// 주기적으로 갱신한다. 부작용: `_recorder.start()`로 실제 녹음을
  /// 시작시키고, `_isRecording`을 true로 setState하며, 권한이 없으면
  /// [_showPermissionDeniedMessage]로 스낵바를 띄운다.
  Future<void> _start() async {
    // On Android/iOS this triggers the native OS permission prompt the
    // first time (package:record calls straight through to
    // ActivityCompat.requestPermissions under the hood); on Windows/other
    // desktop platforms record has no OS permission model and this always
    // resolves to true.
    final hasPermission = await _recorder.hasPermission();
    if (!mounted) return;
    if (!hasPermission) {
      await _showPermissionDeniedMessage();
      return;
    }

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

  /// [_recorder.hasPermission]이 false를 반환했을 때 표시된다. Android/iOS
  /// 에서는 `permission_handler`를 통해 OS가 이 거부를 영구적인 것으로
  /// 취급하는지(예: 학습자가 시스템 프롬프트를 이미 한 번 닫았거나 "다시
  /// 묻지 않음"을 선택한 경우) 확인한다 — record 패키지 자체는 단순한
  /// bool만 노출할 뿐, "다시 물어볼 수 있음"과 "이제 설정 화면에서만 고칠
  /// 수 있음"을 구분할 방법이 없다. permission_handler는 Windows/Linux/
  /// macOS 구현이 없으므로 이 분기는 그 플랫폼들에서는 아예 실행되지
  /// 않는다; 그 플랫폼들에서는 record의 `hasPermission` 자체가 이미 항상
  /// true를 반환하므로(애초에 거부할 OS 권한 모델이 없음) 이 메시지는
  /// 모바일 외에서는 실제로 표시될 일이 없어야 한다.
  Future<void> _showPermissionDeniedMessage() async {
    var permanentlyDenied = false;
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await ph.Permission.microphone.status;
      permanentlyDenied = status.isPermanentlyDenied;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Microphone permission is required to record your pronunciation.',
        ),
        action: permanentlyDenied
            ? SnackBarAction(label: 'Settings', onPressed: ph.openAppSettings)
            : null,
      ),
    );
  }

  /// 진폭 스트림 구독을 취소하고 녹음을 중지한 뒤, 결과 파일을 바이트로
  /// 읽어 [AudioRecorderWidget.onRecordingComplete]로 전달한다. 부작용:
  /// `_isRecording`을 false로, `_isProcessing`을 잠깐 true로 setState하며
  /// (파일 읽기 동안), 파형을 초기화하고, 콜백을 통해 녹음 완료를 상위로
  /// 알린다.
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

  /// 파형을 그리는 `CustomPaint` 영역과, 녹음 상태(대기/녹음 중/처리 중)에
  /// 따라 마이크·정지·로딩 아이콘을 보여주는 원형 버튼을 세로로 배치해
  /// 그린다.
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

/// 은은한 격자 위에 중앙선을 기준으로 좌우(위아래)로 대칭인 부드러운 진폭
/// 궤적을 그려, 아날로그 오실로스코프 느낌을 낸다. `record` 패키지의 진폭
/// 스트림은 부호 있는 파형이 아니라 크기(magnitude)만 제공하기 때문에,
/// 이 "궤적"은 실제 파형이 아니라 엔벨로프(envelope)다 — 중앙선 위에
/// 샘플들을 그리고 그것을 아래로 대칭 복제한 것으로, 크기 정보만 있는
/// 신호로 낼 수 있는 가장 오실로스코프에 가까운 표현이다.
class _OscilloscopePainter extends CustomPainter {
  /// [samples], [isActive], [waveColor], [gridColor]를 받아 painter를
  /// 구성한다.
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

  /// 배경 격자를 그린 뒤, [isActive]이면 [samples]로부터 중앙선 기준
  /// 위/아래로 대칭인 부드러운 곡선을, 아니면(비활성 상태거나 샘플이
  /// 없으면) 평평한 직선을 그린다.
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

  /// [points]를 직선으로 하나하나 잇는 대신, 연속된 점들의 중점 사이를
  /// 2차 베지어(quadratic Bézier) 구간으로 이어 부드러운 곡선을 만든다 —
  /// 그 결과 궤적이 연속된 곡선처럼 보인다.
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

  /// 샘플 리스트 인스턴스가 바뀌었거나(`identical` 비교), 활성 여부·파형
  /// 색상·격자 색상이 이전 delegate와 다르면 다시 그린다.
  @override
  bool shouldRepaint(covariant _OscilloscopePainter oldDelegate) {
    return !identical(oldDelegate.samples, samples) ||
        oldDelegate.isActive != isActive ||
        oldDelegate.waveColor != waveColor ||
        oldDelegate.gridColor != gridColor;
  }
}
