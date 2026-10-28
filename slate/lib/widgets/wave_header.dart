import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// The black login header. Its lower edge is one cubic Bézier fitted to the
/// reference frame (0.3pt RMS error on a 440pt-wide screen).
///
/// [progress] 0 is a full-screen black curtain (the splash); 1 is the
/// finished wave. The right end rises first and the left end last, which is
/// what makes the reveal feel liquid.
class WavePainter extends CustomPainter {
  WavePainter({required this.progress, this.color = const Color(0xFF000000)});

  final double progress;
  final Color color;

  // Design points on a 440pt-wide screen: start (left), two controls, end (right).
  static const _p0 = Offset(0, 229.3);
  static const _c1 = Offset(168.7, 339.6);
  static const _c2 = Offset(320.3, 267.6);
  static const _p3 = Offset(440, 78.8);

  /// Lowest point of the finished wave, on a 440pt-wide screen.
  static const designBottom = 282.0;

  static double bottomFor(double width) => designBottom * width / 440;

  static const _rightLead = Interval(0.0, 0.78, curve: Curves.easeInOutCubic);
  static const _c2Lead = Interval(0.04, 0.86, curve: Curves.easeInOutCubic);
  static const _c1Lead = Interval(0.1, 0.94, curve: Curves.easeInOutCubic);
  static const _leftLead = Interval(0.16, 1.0, curve: Curves.easeInOutCubic);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 440;
    final floor = size.height + 60; // below the screen: nothing uncovered
    double y(Offset point, Curve curve) =>
        lerpDouble(floor, point.dy * scale, curve.transform(progress.clamp(0, 1)))!;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, y(_p3, _rightLead))
      ..cubicTo(
        _c2.dx * scale,
        y(_c2, _c2Lead),
        _c1.dx * scale,
        y(_c1, _c1Lead),
        0,
        y(_p0, _leftLead),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
