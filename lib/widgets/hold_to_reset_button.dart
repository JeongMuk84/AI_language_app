import 'package:flutter/material.dart';

/// A destructive action that only fires after being held down for
/// [holdDuration] — a short tap does nothing. The button itself acts as
/// the progress indicator: its fill sweeps left-to-right as the hold
/// continues, and releasing early resets it to empty without triggering
/// [onConfirmed].
class HoldToResetButton extends StatefulWidget {
  const HoldToResetButton({
    super.key,
    required this.onConfirmed,
    this.label = 'Reset All Data',
    this.holdDuration = const Duration(seconds: 5),
  });

  final VoidCallback onConfirmed;
  final String label;
  final Duration holdDuration;

  @override
  State<HoldToResetButton> createState() => _HoldToResetButtonState();
}

class _HoldToResetButtonState extends State<HoldToResetButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.holdDuration);
    _controller.addStatusListener(_onStatusChanged);
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onConfirmed();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.forward();

  /// Releasing before the hold completes must snap straight back to empty —
  /// not play a reverse animation — so a quick release reads as "nothing
  /// happened" rather than a visible rewind.
  void _onRelease() {
    if (_controller.status != AnimationStatus.completed) {
      _controller.reset();
    }
  }

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

          // Painted directly instead of Stack + Align + FractionallySizedBox:
          // a fresh Stack (custom child parentData) laid out for the first
          // time while the AlertDialog's own entrance transition is still
          // animating reliably tripped the framework's
          // '!semantics.parentDataDirty' assertion (confirmed via a Windows
          // integration-test repro isolating this widget). CustomPaint has
          // no child parentData of its own, so it doesn't hit that path.
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

class _FillBarPainter extends CustomPainter {
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

  @override
  bool shouldRepaint(covariant _FillBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.fillColor != fillColor;
  }
}
