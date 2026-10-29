import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Issuer and network marks for the card faces, drawn from simple shapes and
/// the app font in the style of each card. They are drawings, not the
/// companies' logo files.

TextStyle _word(double size, FontWeight weight, Color color, {double spacing = 0}) => TextStyle(
      fontFamily: SlateText.family,
      fontSize: size,
      height: 1,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color,
    );

/// Reads absolute M, L, C, Q and Z commands, which is all the artwork uses.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLCQZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m[0]!).toList();
  bool isCommand(String t) => 'MLCQZ'.contains(t);
  var i = 0;
  double n() => double.parse(tokens[i++]);
  var command = 'M';
  while (i < tokens.length) {
    if (isCommand(tokens[i])) command = tokens[i++];
    switch (command) {
      case 'M':
        path.moveTo(n(), n());
        command = 'L'; // numbers after a moveto are linetos
      case 'L':
        path.lineTo(n(), n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Q':
        path.quadraticBezierTo(n(), n(), n(), n());
      case 'Z':
        path.close();
        if (i < tokens.length && !isCommand(tokens[i])) throw FormatException('Number after Z', d);
    }
  }
  return path;
}

// ---------------------------------------------------------------------------
// American Express

/// "AMERICAN EXPRESS" across the top of the Platinum, Gold and Centurion cards:
/// heavy, slightly wide capitals.
class AmexWordmark extends StatelessWidget {
  const AmexWordmark({super.key, required this.color, this.size = 15.5});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: 1.06,
      child: Text('AMERICAN EXPRESS', style: _word(size, FontWeight.w800, color, spacing: 0.5)),
    );
  }
}

/// The engraved frame just inside the card's edge: a dark band with a rope
/// texture and a hairline inside it.
class AmexFramePainter extends CustomPainter {
  AmexFramePainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final band = RRect.fromRectAndRadius((Offset.zero & size).deflate(8), const Radius.circular(9));
    canvas.drawRRect(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..color = ink.withValues(alpha: 0.86),
    );
    final light = ink.computeLuminance() < 0.5;
    final tick = Paint()
      ..strokeWidth = 0.65
      ..color = (light ? Colors.white : Colors.black).withValues(alpha: light ? 0.42 : 0.5);
    for (final metric in (Path()..addRRect(band)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 2.1) {
        final t = metric.getTangentForOffset(d)!;
        final normal = Offset(-t.vector.dy, t.vector.dx);
        canvas.drawLine(t.position + normal * 1.7 - t.vector * 0.9, t.position - normal * 1.7 + t.vector * 0.9, tick);
      }
    }
    canvas.drawRRect(
      band.deflate(4.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = ink.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(AmexFramePainter oldDelegate) => oldDelegate.ink != ink;
}

/// The small "MEMBER SINCE" scroll ribbon.
class MemberSinceRibbon extends StatelessWidget {
  const MemberSinceRibbon({super.key, required this.color, this.width = 80});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 0.17;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _RibbonPainter(color),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: height * 0.06),
            child: Text('MEMBER SINCE', style: _word(height * 0.42, FontWeight.w700, color, spacing: 0.7)),
          ),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    // A gently arched band with folded, notched tails at both ends.
    final body = Path()
      ..moveTo(w * 0.1, h * 0.12)
      ..quadraticBezierTo(w * 0.5, -h * 0.18, w * 0.9, h * 0.12)
      ..lineTo(w * 0.9, h * 0.88)
      ..quadraticBezierTo(w * 0.5, h * 0.58, w * 0.1, h * 0.88)
      ..close();
    canvas.drawPath(body, line);
    for (final flip in [false, true]) {
      canvas.save();
      if (flip) {
        canvas.translate(w, 0);
        canvas.scale(-1, 1);
      }
      final tail = Path()
        ..moveTo(w * 0.1, h * 0.3)
        ..lineTo(0, h * 0.3)
        ..lineTo(w * 0.04, h * 0.65)
        ..lineTo(0, h * 1.0)
        ..lineTo(w * 0.1, h * 1.0)
        ..lineTo(w * 0.1, h * 0.88);
      canvas.drawPath(tail, line);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => oldDelegate.color != color;
}

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

/// A helmeted profile in an oval, engraved in fine lines: the portrait at the
/// centre of the Platinum, Gold and Centurion cards. Drawn for this app in a
/// 200 x 260 box, facing right.
class CenturionPortrait extends StatelessWidget {
  const CenturionPortrait({super.key, required this.ink, this.width = 82});

  final Color ink;
  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, width * 1.3), painter: _CenturionPainter(ink));
  }
}

class _CenturionArt {
  _CenturionArt() {
    Path p(String d) => parseSvgPath(d);
    oval = p('M100 4 C153 4 196 60 196 130 C196 200 153 256 100 256 C47 256 4 200 4 130 C4 60 47 4 100 4 Z');
    final plume = p('M134 24 C106 8 66 16 44 44 C22 72 18 112 28 148 C36 176 52 198 72 214 '
        'C82 206 84 196 82 186 C68 168 60 146 60 122 C60 94 74 66 98 48 C108 40 120 34 134 30 Z');
    knob = p('M126 28 L128 8 C128 4 134 4 134 8 L136 28 Z');
    final dome = p('M86 76 C86 46 106 24 132 24 C158 24 176 44 178 70 L86 82 Z');
    final band = p('M82 74 C114 68 150 64 184 64 L185 79 C152 79 116 83 84 91 Z');
    final guard = p('M92 86 C90 106 94 126 104 146 C112 126 116 106 118 84 Z');
    final face = p('M116 85 L179 78 C179 84 177 89 179 95 C181 101 181 105 183 111 '
        'C187 119 193 127 191 131 C189 135 183 134 181 137 C183 141 180 144 182 147 '
        'C184 151 179 153 181 158 C183 165 181 171 175 175 C165 181 151 181 139 175 '
        'C127 169 119 161 113 151 C111 127 113 105 116 85 Z');
    final neck = p('M106 146 C110 164 110 180 104 196 L162 200 C156 190 154 182 156 177 '
        'C144 181 128 175 116 159 Z');
    final shade = p('M116 85 C114 105 112 127 113 151 C119 161 127 169 139 175 '
        'C133 163 129 147 129 129 C129 113 131 99 135 84 Z '
        'M106 146 C110 164 110 180 104 196 L128 198 C128 184 126 172 120 164 Z');
    final armor = p('M18 230 C34 208 64 196 98 194 C124 192 150 194 172 200 '
        'C188 204 198 214 200 226 L200 260 L0 260 Z');
    final cloak = p('M152 200 C172 202 192 214 198 234 L198 260 L142 260 C152 234 152 216 152 200 Z');
    final collar = p('M96 196 C120 188 152 190 176 198 L174 210 C152 202 120 202 98 210 Z');

    Path union(List<Path> paths) => paths.reduce((a, b) => Path.combine(PathOperation.union, a, b));
    Path minus(Path a, List<Path> cut) => Path.combine(PathOperation.difference, a, union(cut));

    final head = union([face, neck]);
    final everything = union([plume, knob, dome, band, guard, head, armor, cloak, collar]);
    background = minus(oval, [everything]);
    this.plume = minus(plume, [dome, band, guard, head]);
    this.armor = minus(armor, [collar, head, cloak]);
    this.cloak = minus(cloak, [collar]);
    skin = minus(head, [guard, band, collar]);
    shadow = Path.combine(PathOperation.intersect, shade, skin);
    this.dome = minus(dome, [band]);
    headOutline = minus(Path()..addRect(const Rect.fromLTWH(0, 0, 200, 260)), [guard, band, collar]);
    behindBand = minus(Path()..addRect(const Rect.fromLTWH(0, 0, 200, 260)), [band]);
    headOutlines = [face, neck];
    domeOutline = dome;
    front = [band, guard, collar];
    details = [
      p('M161 102 C165 100 169 100 172 102'), // eye
      p('M160 99 C164 96 169 96 173 99'), // lid
      p('M157 94 C163 90 171 90 177 93'), // brow
      p('M181 132 C179 131 177 129 177 127'), // nostril
      p('M172 141 C176 141 179 141 182 140'), // mouth
      p('M169 161 C173 159 177 158 180 158'), // chin
    ];
    soft = [
      p('M146 124 C152 134 156 146 156 158'), // cheek
      p('M86 84 C118 77 152 73 184 72'), // lower edge of the band
      p('M98 90 C98 108 100 124 104 138'), // ridge of the cheek guard
    ];
    backgroundLines = _lines(0, 260, 3.4);
    feathers = _feathers(12);
    armorLines = _lines(190, 260, 2.6, wave: -4);
    cloakLines = _lines(190, 260, 2.4, wave: 8);
    skinLines = _lines(70, 220, 2.8, wave: 3);
    domeLines = _lines(24, 84, 2.4, x0: 80, x1: 180, wave: -6);
  }

  late final Path oval, knob, background, plume, armor, cloak, skin, shadow, dome;
  late final Path headOutline, behindBand, domeOutline;
  late final List<Path> headOutlines, front, details, soft;
  late final Path backgroundLines, feathers, armorLines, cloakLines, skinLines, domeLines;

  static Path _lines(double y0, double y1, double step, {double x0 = 0, double x1 = 200, double wave = 0}) {
    final path = Path();
    for (var y = y0; y < y1; y += step) {
      path
        ..moveTo(x0, y)
        ..quadraticBezierTo((x0 + x1) / 2, y + wave, x1, y);
    }
    return path;
  }

  // Strands of the plume, blended between its outer and inner edges so each
  // one follows the sweep from the crest down behind the neck.
  static const _outer = [134.0, 24, 106, 8, 66, 16, 44, 44, 22, 72, 18, 112, 28, 148, 36, 176, 52, 198, 72, 214];
  static const _inner = [134.0, 30, 120, 34, 108, 40, 98, 48, 74, 66, 60, 94, 60, 122, 60, 146, 68, 168, 82, 186];

  static Path _feathers(int count) {
    final path = Path();
    for (var i = 0; i < count; i++) {
      final t = (i + 0.5) / count;
      double at(int k) => _outer[k] + (_inner[k] - _outer[k]) * t;
      path.moveTo(at(0), at(1));
      for (var k = 2; k < _outer.length; k += 6) {
        path.cubicTo(at(k), at(k + 1), at(k + 2), at(k + 3), at(k + 4), at(k + 5));
      }
    }
    return path;
  }
}

class _CenturionPainter extends CustomPainter {
  _CenturionPainter(this.ink);

  final Color ink;

  static final _art = _CenturionArt();

  @override
  void paint(Canvas canvas, Size size) {
    final a = _art;
    canvas.save();
    canvas.scale(size.width / 200, size.height / 260);
    Paint line(double width, double alpha) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = ink.withValues(alpha: alpha);
    void within(Path clip, void Function() draw) {
      canvas.save();
      canvas.clipPath(clip);
      draw();
      canvas.restore();
    }

    canvas.save();
    canvas.clipPath(a.oval); // everything but the frame stays inside the oval
    within(a.background, () => canvas.drawPath(a.backgroundLines, line(1.0, 0.2)));
    within(a.plume, () => canvas.drawPath(a.feathers, line(1.7, 0.8)));
    canvas.drawPath(a.knob, Paint()..color = ink);
    within(a.armor, () => canvas.drawPath(a.armorLines, line(1.5, 0.85)));
    within(a.cloak, () => canvas.drawPath(a.cloakLines, line(1.8, 0.95)));
    within(a.skin, () => canvas.drawPath(a.skinLines, line(0.9, 0.35)));
    within(a.shadow, () => canvas.drawPath(a.skinLines, line(1.8, 0.75)));
    within(a.dome, () => canvas.drawPath(a.domeLines, line(1.4, 0.8)));
    final outline = line(2.6, 1);
    within(a.headOutline, () {
      for (final p in a.headOutlines) {
        canvas.drawPath(p, outline);
      }
    });
    within(a.behindBand, () => canvas.drawPath(a.domeOutline, outline));
    for (final p in a.front) {
      canvas.drawPath(p, outline);
    }
    final detail = line(2.4, 1);
    for (final p in a.details) {
      canvas.drawPath(p, detail);
    }
    final soft = line(1.5, 0.65);
    for (final p in a.soft) {
      canvas.drawPath(p, soft);
    }
    canvas.restore();
    canvas.drawPath(a.oval, line(4, 1));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CenturionPainter oldDelegate) => oldDelegate.ink != ink;
}

// ---------------------------------------------------------------------------
// Chase

/// The octagon: four identical pieces turning around a square hole, in brushed
/// silver.
class ChaseOctagon extends StatelessWidget {
  const ChaseOctagon({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _OctagonPainter());
}

class _OctagonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const a = 0.3; // half the hole
    final t = math.tan(math.pi / 8); // octagon vertex offset when the apothem is 1
    final piece = [
      const Offset(-a, -a),
      const Offset(a, -a),
      const Offset(1, -a),
      Offset(1, -t),
      Offset(t, -1),
      const Offset(-a, -1),
    ];
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFC9CCD2), Color(0xFFF2F3F5), Color(0xFF9EA3AB)],
        stops: [0, 0.4, 0.62, 1],
      ).createShader(Offset.zero & size);
    final r = size.width / 2;
    final center = size.center(Offset.zero);
    for (var k = 0; k < 4; k++) {
      final angle = k * math.pi / 2;
      final c = math.cos(angle);
      final s = math.sin(angle);
      final pts = [for (final p in piece) Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c)];
      final centroid = pts.reduce((x, y) => x + y) / pts.length.toDouble();
      final path = Path();
      for (final (i, p) in pts.indexed) {
        // Pull each piece a touch toward its own middle so thin gaps show between them.
        final q = center + (centroid + (p - centroid) * 0.93) * r;
        i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path..close(), paint);
    }
  }

  @override
  bool shouldRepaint(_OctagonPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Capital One

/// "Capital One" in italics under its swoosh.
class CapitalOneLogo extends StatelessWidget {
  const CapitalOneLogo({super.key, this.width = 112, this.color = const Color(0xFFE4E7EB)});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.3;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _SwooshPainter(color))),
          Positioned(
            left: 0,
            bottom: 0,
            child: Transform(
              transform: Matrix4.skewX(-0.22),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Capital', style: _word(width * 0.19, FontWeight.w800, color, spacing: -0.2)),
                  TextSpan(text: 'One', style: _word(width * 0.205, FontWeight.w400, color, spacing: -0.4)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  _SwooshPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // A crescent: thick over the middle, tapering to points at both ends.
    final path = Path()
      ..moveTo(w * 0.3, h * 0.46)
      ..cubicTo(w * 0.46, h * 0.0, w * 0.84, -h * 0.12, w * 1.06, h * 0.04)
      ..cubicTo(w * 0.82, h * 0.1, w * 0.52, h * 0.16, w * 0.3, h * 0.46)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwooshPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Citi

/// Lowercase "citi" with the arc over the "ti".
class CitiLogo extends StatelessWidget {
  const CitiLogo({super.key, this.height = 28, this.color = Colors.white});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = _word(height * 1.02, FontWeight.w700, color, spacing: -height * 0.03);
    return CustomPaint(
      foregroundPainter: _CitiArcPainter(color),
      child: Padding(
        padding: EdgeInsets.only(top: height * 0.2),
        child: Text('citi', style: style),
      ),
    );
  }
}

class _CitiArcPainter extends CustomPainter {
  _CitiArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTRB(w * 0.42, h * 0.02, w * 1.0, h * 0.9);
    canvas.drawArc(
      rect,
      math.pi * 1.12,
      math.pi * 0.76,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.075
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CitiArcPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Networks

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

/// Two overlapping circles: red and yellow with an orange overlap, or tones of
/// grey on cards that print the mark in one colour.
class MastercardMark extends StatelessWidget {
  const MastercardMark({super.key, this.width = 52, this.mono = false, this.wordmark = false, this.color = Colors.white});

  final double width;
  final bool mono;
  final bool wordmark;

  /// Colour of the "mastercard" wordmark under the circles.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final circles = CustomPaint(size: Size(width, width * 0.62), painter: _MastercardPainter(mono));
    if (!wordmark) return circles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circles,
        SizedBox(height: width * 0.05),
        Text('mastercard', style: _word(width * 0.19, FontWeight.w600, color, spacing: 0.1)),
      ],
    );
  }
}

class _MastercardPainter extends CustomPainter {
  _MastercardPainter(this.mono);

  final bool mono;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final left = Offset(r, r);
    final right = Offset(size.width - r, r);
    final a = Path()..addOval(Rect.fromCircle(center: left, radius: r));
    final b = Path()..addOval(Rect.fromCircle(center: right, radius: r));
    canvas.drawPath(a, Paint()..color = mono ? const Color(0xFFB9BCC1) : const Color(0xFFEB001B));
    canvas.drawPath(b, Paint()..color = mono ? const Color(0xFF8E9298) : const Color(0xFFF79E1B));
    canvas.drawPath(
      Path.combine(PathOperation.intersect, a, b),
      Paint()..color = mono ? const Color(0xFFD7D9DC) : const Color(0xFFFF5F00),
    );
  }

  @override
  bool shouldRepaint(_MastercardPainter oldDelegate) => oldDelegate.mono != mono;
}
