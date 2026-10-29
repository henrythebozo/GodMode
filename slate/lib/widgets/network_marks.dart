import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Network marks the app writes onto blank cards the member described
/// themselves (the card pictures carry their own). Drawn from simple shapes
/// and the app font; they are not the networks' logo files.

TextStyle _word(double size, FontWeight weight, Color color, {double spacing = 0}) => TextStyle(
      fontFamily: SlateText.family,
      fontSize: size,
      height: 1,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color,
    );

/// The blue box: "AMERICAN" over "EXPRESS" in white on Amex blue.
class AmexBlueBox extends StatelessWidget {
  const AmexBlueBox({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFF016FD0), borderRadius: BorderRadius.circular(size * 0.04)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final word in ['AMERICAN', 'EXPRESS'])
              Padding(
                padding: EdgeInsets.symmetric(vertical: size * 0.02),
                child: Transform.scale(
                  scaleY: 1.25,
                  child: Text(word, style: _word(size * 0.155, FontWeight.w800, Colors.white, spacing: -0.1)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "DISCOVER" with the orange ball for the O.
class DiscoverWordmark extends StatelessWidget {
  const DiscoverWordmark({super.key, this.height = 17, this.color = Colors.white});

  /// Cap height.
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = height / 0.72;
    final style = _word(size, FontWeight.w800, color, spacing: size * 0.02);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('DISC', style: style),
        Container(
          width: height * 1.08,
          height: height * 1.08,
          margin: EdgeInsets.symmetric(horizontal: size * 0.03),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-0.35, -0.4),
              radius: 0.95,
              colors: [Color(0xFFFFC46B), Color(0xFFF68A1F), Color(0xFFD9531E)],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
        Text('VER', style: style),
      ],
    );
  }
}

/// Two overlapping circles: red and yellow with an orange overlap.
class MastercardMark extends StatelessWidget {
  const MastercardMark({super.key, this.width = 52});

  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, width * 0.62), painter: const _MastercardPainter());
  }
}

class _MastercardPainter extends CustomPainter {
  const _MastercardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final left = Offset(r, r);
    final right = Offset(size.width - r, r);
    final a = Path()..addOval(Rect.fromCircle(center: left, radius: r));
    final b = Path()..addOval(Rect.fromCircle(center: right, radius: r));
    canvas.drawPath(a, Paint()..color = const Color(0xFFEB001B));
    canvas.drawPath(b, Paint()..color = const Color(0xFFF79E1B));
    canvas.drawPath(
      Path.combine(PathOperation.intersect, a, b),
      Paint()..color = const Color(0xFFFF5F00),
    );
  }

  @override
  bool shouldRepaint(_MastercardPainter oldDelegate) => false;
}
