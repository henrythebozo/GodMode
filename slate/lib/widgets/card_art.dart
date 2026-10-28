import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'card_designs.dart';
import 'visa_logo.dart';

/// A card face, laid out at a fixed design size and scaled to the width it is
/// given, so every card keeps identical proportions at any size.
///
/// Slate's own cards follow the reference exactly (name bottom-left, VISA and
/// tier bottom-right, no chip). Bank cards add the issuer, an EMV chip and the
/// last four digits.
class CardArt extends StatelessWidget {
  const CardArt({
    super.key,
    required this.design,
    required this.holderName,
    this.last4,
    this.frozen = false,
  });

  CardArt.of(WalletCard card, {super.key})
      : design = CardCatalog.forCard(card),
        holderName = card.holderName,
        last4 = card.last4,
        frozen = card is PaymentCard && card.isFrozen;

  final CardDesign design;
  final String holderName;
  final String? last4;
  final bool frozen;

  static const designSize = Size(392, 247);
  static const aspectRatio = 392 / 247;

  @override
  Widget build(BuildContext context) {
    final m = design.material;
    final bank = !design.isSlate;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox.fromSize(
          size: designSize,
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _MetalPainter(m, design.pattern)),
                  if (bank && design.showIssuer)
                    Positioned(
                      top: 26,
                      left: 24,
                      right: 90,
                      child: Text(
                        design.issuer.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: SlateText.family,
                          fontSize: 12.5,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                          color: m.ink,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 24,
                    right: 24,
                    child: ContactlessIcon(size: bank ? 30 : 36, color: m.ink),
                  ),
                  if (design.chip) const Positioned(left: 24, top: 84, child: _Chip()),
                  if (bank && last4 != null)
                    Positioned(
                      left: 24,
                      bottom: 58,
                      child: Text(
                        '••••  $last4',
                        style: TextStyle(
                          fontFamily: SlateText.family,
                          fontSize: 15,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                          color: m.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 24,
                    bottom: 34,
                    right: 150,
                    child: Text(
                      holderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: SlateText.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.1,
                        color: m.ink,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 21,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        NetworkMark(network: design.network, color: m.ink),
                        Text(
                          design.product,
                          style: TextStyle(
                            fontFamily: SlateText.family,
                            fontSize: 11,
                            height: 1,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                            color: m.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (frozen) const _FrozenVeil(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picker shows cards standing up: the same artwork turned a quarter turn
/// clockwise, which puts the name along the top-left edge and the network
/// mark at the bottom-left, as in the reference.
class PortraitCard extends StatelessWidget {
  const PortraitCard({super.key, required this.child});

  final CardArt child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / CardArt.aspectRatio,
      child: RotatedBox(quarterTurns: 1, child: child),
    );
  }
}

/// Stand-in marks for the card networks, drawn from the app font (not the
/// networks' logo artwork). Each is 24pt tall to sit above the product name.
class NetworkMark extends StatelessWidget {
  const NetworkMark({super.key, required this.network, required this.color});

  final CardNetwork network;
  final Color color;

  @override
  Widget build(BuildContext context) {
    TextStyle word(double size, {double spacing = 0.6}) => TextStyle(
          fontFamily: SlateText.family,
          fontSize: size,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: spacing,
          color: color,
        );
    return switch (network) {
      CardNetwork.visa => VisaLogo(height: 24, color: color),
      CardNetwork.amex => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('AMEX', style: word(12.5, spacing: 1.6)),
          ),
        ),
      CardNetwork.mastercard => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: CustomPaint(size: const Size(42, 26), painter: _RingsPainter(color)),
        ),
      CardNetwork.discover => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DISC', style: word(14)),
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: const BoxDecoration(color: Color(0xFFF2711C), shape: BoxShape.circle),
              ),
              Text('VER', style: word(14)),
            ],
          ),
        ),
    };
  }
}

/// Two interlocking rings in the card's ink colour. (Filled discs read as a
/// toggle switch at this size; outlines with a tinted overlap don't.)
class _RingsPainter extends CustomPainter {
  _RingsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.2;
    final r = size.height / 2 - stroke / 2;
    final left = Offset(r + stroke / 2, size.height / 2);
    final right = Offset(size.width - r - stroke / 2, size.height / 2);
    final tint = Paint()..color = color.withValues(alpha: 0.14);
    canvas.drawCircle(left, r, tint);
    canvas.drawCircle(right, r, tint);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(left, r, ring);
    canvas.drawCircle(right, r, ring);
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) => oldDelegate.color != color;
}

class _Chip extends StatelessWidget {
  const _Chip();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(46, 36), painter: _ChipPainter());
  }
}

/// A gold EMV chip with its contact lines.
class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3DC9A), Color(0xFFD2AE5C), Color(0xFFE8CB80)],
        ).createShader(rect),
    );
    final line = Paint()
      ..color = const Color(0xFF8C6E2C).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(0, h * 0.33), Offset(w * 0.34, h * 0.33), line);
    canvas.drawLine(Offset(0, h * 0.67), Offset(w * 0.34, h * 0.67), line);
    canvas.drawLine(Offset(w * 0.66, h * 0.33), Offset(w, h * 0.33), line);
    canvas.drawLine(Offset(w * 0.66, h * 0.67), Offset(w, h * 0.67), line);
    canvas.drawLine(Offset(w * 0.34, 0), Offset(w * 0.34, h), line);
    canvas.drawLine(Offset(w * 0.66, 0), Offset(w * 0.66, h), line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.34, h * 0.33, w * 0.66, h * 0.67),
        const Radius.circular(3),
      ),
      line,
    );
    canvas.drawRRect(body, line);
  }

  @override
  bool shouldRepaint(_ChipPainter oldDelegate) => false;
}

class _FrozenVeil extends StatelessWidget {
  const _FrozenVeil();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: SlateColors.ink,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Iconsax.lock_copy, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Frozen', style: SlateText.small.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brushed metal: a diagonal base gradient, fine horizontal hairlines, an
/// optional engraved pattern and a soft sheen from the top-left corner.
class _MetalPainter extends CustomPainter {
  _MetalPainter(this.material, this.pattern);

  final CardMaterial material;
  final CardPattern pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: material.gradient,
        ).createShader(rect),
    );

    if (material.brush > 0) {
      final random = math.Random(7); // same grain on every card and every frame
      final line = Paint()..strokeWidth = 0.6;
      for (double y = 0; y < size.height; y += 0.9) {
        final light = random.nextBool();
        final alpha = (random.nextDouble() * 0.028 + 0.004) * material.brush;
        line.color = (light ? Colors.white : Colors.black).withValues(alpha: alpha);
        final start = random.nextDouble() * size.width * 0.3;
        final end = size.width - random.nextDouble() * size.width * 0.3;
        canvas.drawLine(Offset(start, y), Offset(end, y), line);
      }
    }

    final engrave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = material.ink.withValues(alpha: 0.05);
    switch (pattern) {
      case CardPattern.guilloche:
        final center = Offset(size.width * 0.66, size.height * 0.44);
        for (double r = 14; r < size.width; r += 5.5) {
          canvas.drawOval(Rect.fromCenter(center: center, width: r * 2.1, height: r * 1.6), engrave);
        }
      case CardPattern.pinstripe:
        for (double x = -size.height; x < size.width; x += 7) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), engrave);
        }
      case CardPattern.none:
        break;
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.4, 0.6),
          colors: [
            Colors.white.withValues(alpha: material.sheen),
            Colors.white.withValues(alpha: material.sheen * 0.22),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MetalPainter oldDelegate) =>
      oldDelegate.material != material || oldDelegate.pattern != pattern;
}

/// Three contactless arcs fanning out to the top-right.
class ContactlessIcon extends StatelessWidget {
  const ContactlessIcon({super.key, this.size = 36, this.color = Colors.black});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _ContactlessPainter(color));
  }
}

class _ContactlessPainter extends CustomPainter {
  _ContactlessPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // Quarter arcs around the bottom-left corner; the outer one spans the box.
    final center = Offset(stroke / 2, size.height - stroke / 2);
    for (final radius in [0.36, 0.66, 0.96]) {
      final r = radius * (size.width - stroke);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi / 2 + 0.12,
        math.pi / 2 - 0.24,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ContactlessPainter oldDelegate) => oldDelegate.color != color;
}

/// The round "+" with "Add" under it that ends the row of cards.
class AddCardButton extends StatelessWidget {
  const AddCardButton({super.key, required this.onTap, this.dark = true, this.label = 'Add'});

  final VoidCallback onTap;
  final bool dark;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : SlateColors.text;
    return Semantics(
      button: true,
      label: 'Add a card',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PressCircle(dark: dark),
            const SizedBox(height: 10),
            Text(label, style: SlateText.small.copyWith(color: fg.withValues(alpha: dark ? 0.85 : 1))),
          ],
        ),
      ),
    );
  }
}

class _PressCircle extends StatefulWidget {
  const _PressCircle({required this.dark});

  final bool dark;

  @override
  State<_PressCircle> createState() => _PressCircleState();
}

class _PressCircleState extends State<_PressCircle> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: widget.dark ? SlateColors.chip : SlateColors.field,
            shape: BoxShape.circle,
            border: widget.dark ? Border.all(color: Colors.white.withValues(alpha: 0.08)) : null,
          ),
          child: Icon(
            Iconsax.add_copy,
            size: 28,
            color: widget.dark ? Colors.white : SlateColors.text,
          ),
        ),
      ),
    );
  }
}
