import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'visa_logo.dart';

/// Colours for each card finish, sampled from the reference frames.
class CardMaterial {
  const CardMaterial({
    required this.gradient,
    required this.ink,
    required this.label,
    required this.brush,
  });

  final List<Color> gradient;
  final Color ink;
  final Color label;

  /// Strength of the brushed-metal hairlines, 0 to 1.
  final double brush;

  static const platinum = CardMaterial(
    gradient: [Color(0xFFC5C1BC), Color(0xFFBCB8B2), Color(0xFFBAB6B0)],
    ink: Color(0xFF1E1D1B),
    label: Color(0xFF6B6763),
    brush: 1,
  );
  static const silver = CardMaterial(
    gradient: [Color(0xFFB9BCBE), Color(0xFFABAEB0), Color(0xFFA2A5A7)],
    ink: Color(0xFF1C1D1E),
    label: Color(0xFF55585B),
    brush: 0.45,
  );
  static const gold = CardMaterial(
    gradient: [Color(0xFFDDD0B4), Color(0xFFD2C3A7), Color(0xFFC4B497)],
    ink: Color(0xFF241F16),
    label: Color(0xFF75674B),
    brush: 0.5,
  );

  static CardMaterial of(CardFinish finish) => switch (finish) {
        CardFinish.platinum => platinum,
        CardFinish.silver => silver,
        CardFinish.gold => gold,
      };
}

/// The metal card from the screenshots, in landscape. It is laid out at a
/// fixed design size and scaled to whatever width it is given, so the home
/// screen card and the bigger picker card keep identical proportions.
class SlateCard extends StatelessWidget {
  const SlateCard({
    super.key,
    required this.finish,
    required this.holderName,
    required this.tierLabel,
    this.frozen = false,
  });

  SlateCard.fromCard(PaymentCard card, {super.key, required this.tierLabel})
      : finish = card.finish,
        holderName = card.holderName,
        frozen = card.isFrozen;

  final CardFinish finish;
  final String holderName;
  final String tierLabel;
  final bool frozen;

  static const designSize = Size(392, 247);
  static const aspectRatio = 392 / 247;

  @override
  Widget build(BuildContext context) {
    final material = CardMaterial.of(finish);
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
                  CustomPaint(painter: _MetalPainter(material)),
                  Positioned(
                    top: 24,
                    right: 24,
                    child: ContactlessIcon(size: 36, color: material.ink),
                  ),
                  Positioned(
                    left: 24,
                    bottom: 34,
                    right: 140,
                    child: Text(
                      holderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: SlateText.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.1,
                        color: material.ink,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 21,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        VisaLogo(height: 24, color: material.ink),
                        Text(
                          tierLabel,
                          style: TextStyle(
                            fontFamily: SlateText.family,
                            fontSize: 11,
                            height: 1,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                            color: material.label,
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
/// clockwise, which puts the name along the top-left edge and VISA at the
/// bottom-left, as in the reference.
class PortraitSlateCard extends StatelessWidget {
  const PortraitSlateCard({super.key, required this.card});

  final SlateCard card;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / SlateCard.aspectRatio,
      child: RotatedBox(quarterTurns: 1, child: card),
    );
  }
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

/// Brushed metal: a diagonal base gradient, fine horizontal hairlines and a
/// soft sheen from the top-left corner.
class _MetalPainter extends CustomPainter {
  _MetalPainter(this.material);

  final CardMaterial material;

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

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.4, 0.6),
          colors: [
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.02),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MetalPainter oldDelegate) => oldDelegate.material != material;
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

/// Placeholder in the card slot for members who don't have a card yet.
class EmptyCardSlot extends StatelessWidget {
  const EmptyCardSlot({super.key, required this.onTap, this.dark = true});

  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : SlateColors.text;
    return AspectRatio(
      aspectRatio: SlateCard.aspectRatio,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: fg.withValues(alpha: 0.25), width: 1.2),
            color: fg.withValues(alpha: 0.04),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.card_add_copy, color: fg, size: 28),
              const SizedBox(height: 10),
              Text('Get your first card', style: SlateText.body.copyWith(color: fg)),
              const SizedBox(height: 4),
              Text(
                'Platinum, Silver or Gold',
                style: SlateText.caption.copyWith(color: fg.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
