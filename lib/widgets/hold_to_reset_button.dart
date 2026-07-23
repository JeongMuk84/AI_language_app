import 'package:flutter/material.dart';

/// [holdDuration] 동안 눌러 유지해야만 실행되는 파괴적(destructive) 액션
/// 버튼 — 짧게 탭하는 것만으로는 아무 일도 일어나지 않는다. SettingsDialog
/// 에서 "Reset All Data"(모든 데이터 초기화) 버튼으로 쓰인다. 버튼 자체가
/// 진행률 표시기 역할을 겸한다: 계속 누르고 있으면 채움이 왼쪽에서
/// 오른쪽으로 진행되고, 도중에 손을 떼면 [onConfirmed]를 호출하지 않고
/// 즉시 빈 상태로 되돌아간다.
class HoldToResetButton extends StatefulWidget {
  /// [onConfirmed] 콜백과, 선택적인 [label]/[holdDuration]을 받아 위젯을
  /// 구성한다.
  const HoldToResetButton({
    super.key,
    required this.onConfirmed,
    this.label = 'Reset All Data',
    this.holdDuration = const Duration(seconds: 5),
  });

  /// 홀드가 [holdDuration]만큼 완료됐을 때 호출되는 콜백. 실제 데이터
  /// 초기화 로직은 이 콜백을 넘기는 쪽(SettingsDialog)이 담당한다.
  final VoidCallback onConfirmed;

  /// 홀드 중이 아닐 때 버튼에 표시할 기본 라벨.
  final String label;

  /// [onConfirmed]가 호출되기까지 눌러 유지해야 하는 시간.
  final Duration holdDuration;

  /// [_HoldToResetButtonState]를 생성한다.
  @override
  State<HoldToResetButton> createState() => _HoldToResetButtonState();
}

/// [HoldToResetButton]의 State. 홀드 진행률 애니메이션과 탭 다운/릴리즈
/// 제스처를 관리한다.
class _HoldToResetButtonState extends State<HoldToResetButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// [HoldToResetButton.holdDuration]을 지속 시간으로 하는
  /// `AnimationController`를 만들고 상태 변화 리스너를 등록한다.
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.holdDuration);
    _controller.addStatusListener(_onStatusChanged);
  }

  /// 애니메이션이 끝까지 진행(`completed`)되면 [HoldToResetButton.onConfirmed]를
  /// 호출하고 진행률을 0으로 되돌린다. 부작용: 파괴적 액션을 트리거하고
  /// 애니메이션 값을 리셋한다.
  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onConfirmed();
      _controller.value = 0;
    }
  }

  /// 상태 리스너를 해제하고 [_controller]를 dispose한다.
  @override
  void dispose() {
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 버튼을 누르기 시작하면 [_controller]의 정방향 애니메이션(채움 진행)을
  /// 시작한다.
  void _onTapDown(TapDownDetails _) => _controller.forward();

  /// 홀드가 완료되기 전에 손을 떼면 역재생 애니메이션이 아니라 즉시 빈
  /// 상태로 스냅백해야 한다 — 그래야 빠른 릴리즈가 눈에 보이는 되감기가
  /// 아니라 "아무 일도 없었음"으로 읽힌다.
  void _onRelease() {
    if (_controller.status != AnimationStatus.completed) {
      _controller.reset();
    }
  }

  /// 진행률에 따라 채움 바를 그리는 `CustomPaint`(_FillBarPainter)와, 홀드
  /// 진행 중에는 남은 초를 함께 보여주는 텍스트를 겹쳐 그린다.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: (_) => _onRelease(),
      onTapCancel: _onRelease,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          final remainingSeconds = (widget.holdDuration.inMilliseconds * (1 - progress) / 1000)
              .ceil();
          final text = progress > 0 ? 'Hold to reset... (${remainingSeconds}s)' : widget.label;

          // Stack + Align + FractionallySizedBox 대신 직접 CustomPaint로
          // 그린다: AlertDialog 자신의 진입 전환 애니메이션이 아직 진행
          // 중인 동안 처음 레이아웃되는 새 Stack(자체 child parentData를
          // 가짐)은 프레임워크의 '!semantics.parentDataDirty' assertion을
          // 안정적으로 유발했다(이 위젯만 분리한 Windows 통합 테스트
          // 재현으로 확인됨). CustomPaint는 자체 child parentData가
          // 없으므로 그 경로를 타지 않는다.
          return CustomPaint(
            painter: _FillBarPainter(
              progress: progress,
              backgroundColor: colorScheme.errorContainer,
              fillColor: colorScheme.error,
              borderRadius: 8,
            ),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                    color: colorScheme.onError,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: colorScheme.error, blurRadius: 6)],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// [HoldToResetButton]의 채움 진행률 바를 둥근 모서리로 그리는
/// `CustomPainter`. 배경색 위에 [progress] 비율만큼 채움색 사각형을
/// 클리핑하여 겹쳐 그린다.
class _FillBarPainter extends CustomPainter {
  /// [progress], [backgroundColor], [fillColor], [borderRadius]를 받아
  /// painter를 구성한다.
  _FillBarPainter({
    required this.progress,
    required this.backgroundColor,
    required this.fillColor,
    required this.borderRadius,
  });

  final double progress;
  final Color backgroundColor;
  final Color fillColor;
  final double borderRadius;

  /// 둥근 모서리 사각형으로 클리핑한 뒤, 배경색 전체를 채우고 그 위에
  /// [progress] 비율만큼의 너비로 채움색 사각형을 그린다.
  @override
  void paint(Canvas canvas, Size size) {
    final clipRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    canvas.save();
    canvas.clipRRect(clipRRect);
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * progress, size.height),
      Paint()..color = fillColor,
    );
    canvas.restore();
  }

  /// [progress], [backgroundColor], [fillColor] 중 하나라도 이전
  /// delegate와 다르면 다시 그린다.
  @override
  bool shouldRepaint(covariant _FillBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.fillColor != fillColor;
  }
}
