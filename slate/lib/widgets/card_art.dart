import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'card_designs.dart';
import 'card_marks.dart';
import 'visa_logo.dart';

/// A card face, laid out at a fixed design size and scaled to the width it is
/// given, so every card keeps identical proportions at any size.
///
/// Known cards follow the real card's layout (see [CardStyle]); Slate's own
/// cards follow the reference design (name bottom-left, VISA and tier
/// bottom-right, no chip). [back] draws the reverse: stripe, signature panel
/// and, for cards with a plain front, the masked number.
class CardArt extends StatelessWidget {
  const CardArt({
    super.key,
    required this.design,
    required this.holderName,
    this.last4,
    this.frozen = false,
    this.back = false,
    this.expiry,
    this.memberSince,
  });

  CardArt.of(WalletCard card, {super.key, this.back = false})
      : design = CardCatalog.forCard(card),
        holderName = card.holderName,
        last4 = card.last4,
        frozen = card is PaymentCard && card.isFrozen,
        expiry = card is PaymentCard ? card.expiry : null,
        memberSince = (card.createdAt.year % 100).toString().padLeft(2, '0');

  final CardDesign design;
  final String holderName;
  final String? last4;
  final bool frozen;
  final bool back;

  /// "MM/YY" where the app knows it (Slate's own cards).
  final String? expiry;

  /// Two-digit year for the Amex "MEMBER SINCE" ribbon.
  final String? memberSince;

  static const designSize = Size(392, 247);
  static const aspectRatio = 392 / 247;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox.fromSize(
          size: designSize,
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: back
                  ? _Back(this)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        switch (design.style) {
                          CardStyle.slate => _SlateFront(this),
                          CardStyle.amex => _AmexFront(this),
                          CardStyle.chaseSapphire => _ChaseFront(this),
                          CardStyle.ventureX => _VentureFront(this),
                          CardStyle.citiStrata => _CitiFront(this),
                          CardStyle.discoverIt => _DiscoverFront(this),
                          CardStyle.generic => _GenericFront(this),
                        },
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

TextStyle _t(double size, FontWeight weight, Color color, {double spacing = 0, bool digits = false}) => TextStyle(
      fontFamily: SlateText.family,
      fontSize: size,
      height: 1,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color,
      fontFeatures: digits ? const [FontFeature.tabularFigures()] : null,
    );

/// The holder's name on Slate cards and generic bank cards (natural line
/// height, as measured from the reference).
TextStyle _nameStyle(Color color) => TextStyle(
      fontFamily: SlateText.family,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.1,
      color: color,
    );

/// Splits "Sapphire Reserve" into the two stacked lines printed on the card.
(String, String) _twoLines(String product) {
  final words = product.toUpperCase().split(' ');
  return (words.first, words.skip(1).join(' '));
}

class _SlateFront extends StatelessWidget {
  const _SlateFront(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final m = card.design.material;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, card.design.pattern)),
        Positioned(top: 24, right: 24, child: ContactlessIcon(size: 36, color: m.ink)),
        Positioned(
          left: 24,
          bottom: 34,
          right: 150,
          child: Text(
            card.holderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _nameStyle(m.ink),
          ),
        ),
        Positioned(
          right: 24,
          bottom: 21,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              NetworkMark(network: card.design.network, color: m.ink),
              Text(card.design.product, style: _t(11, FontWeight.w500, m.label, spacing: 0.3)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Amex Platinum, Gold and Centurion: "AMERICAN EXPRESS" centred at the top,
/// an engraved frame, the portrait in the middle, the last digits beside it
/// over the "MEMBER SINCE" ribbon, and the name at the bottom-left.
class _AmexFront extends StatelessWidget {
  const _AmexFront(this.card);

  final CardArt card;

  static const _portrait = Rect.fromLTWH(145, 75, 82, 106.6);

  @override
  Widget build(BuildContext context) {
    final m = card.design.material;
    final ink = m.ink;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, card.design.pattern, patternHole: _portrait)),
        CustomPaint(painter: AmexFramePainter(ink)),
        Positioned(top: 24, left: 0, right: 0, child: Center(child: AmexWordmark(color: ink))),
        Positioned.fromRect(rect: _portrait, child: CenturionPortrait(ink: ink, width: _portrait.width)),
        Positioned(left: 40, top: 88, child: _Chip(finish: card.design.chipFinish)),
        Positioned(left: 279, top: 115, child: ContactlessIcon(size: 15, color: ink)),
        Positioned(
          left: 299,
          top: 116,
          child: Text(card.last4 ?? '', style: _t(14.5, FontWeight.w500, ink, spacing: 1.2, digits: true)),
        ),
        Positioned(left: 256, top: 156, child: MemberSinceRibbon(color: ink, width: 78)),
        Positioned(
          left: 256,
          width: 78,
          top: 175,
          child: Center(child: Text(card.memberSince ?? '', style: _t(13, FontWeight.w500, ink, digits: true))),
        ),
        Positioned(
          left: 38,
          right: 150,
          top: 210,
          child: Text(
            card.holderName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(13.5, FontWeight.w500, ink, spacing: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Sapphire Reserve: a deep navy face with a fine diamond texture lit from the
/// top-right corner, the octagon beside "SAPPHIRE / RESERVE", and a chip. The
/// number and name are on the back.
class _ChaseFront extends StatelessWidget {
  const _ChaseFront(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final m = card.design.material;
    final (first, second) = _twoLines(card.design.product);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, CardPattern.none)),
        CustomPaint(painter: _HaloPainter()),
        const Positioned(left: 22, top: 21, child: ChaseOctagon(size: 34)),
        Positioned(
          left: 69,
          top: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(first, style: _t(18, FontWeight.w500, m.ink, spacing: 2.4)),
              const SizedBox(height: 4),
              Text(second, style: _t(12, FontWeight.w600, m.ink.withValues(alpha: 0.92), spacing: 2.8)),
            ],
          ),
        ),
        Positioned(left: 52, top: 84, child: _Chip(finish: card.design.chipFinish)),
      ],
    );
  }
}

/// Venture X: navy, the Capital One mark at the top-right, chip and
/// contactless symbol, and "VENTURE X" in widely spaced capitals.
class _VentureFront extends StatelessWidget {
  const _VentureFront(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final m = card.design.material;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, CardPattern.none)),
        const Positioned(right: 16, top: 16, child: CapitalOneLogo(width: 116)),
        Positioned(left: 45, top: 80, child: _Chip(finish: card.design.chipFinish, width: 50)),
        Positioned(left: 106, top: 95, child: ContactlessIcon(size: 17, color: m.ink.withValues(alpha: 0.85))),
        Positioned(
          left: 40,
          top: 150,
          child: Text(card.design.product.toUpperCase(), style: _t(15.5, FontWeight.w400, m.label, spacing: 6)),
        ),
      ],
    );
  }
}

/// Strata Premier: charcoal with flowing contour lines, a bright rim, "citi"
/// beside "STRATA / PREMIER", the name, and the Mastercard mark in grey.
class _CitiFront extends StatelessWidget {
  const _CitiFront(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final m = card.design.material;
    final (first, second) = _twoLines(card.design.product);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, CardPattern.none)),
        CustomPaint(painter: _WavesPainter()),
        CustomPaint(painter: _RimPainter()),
        Positioned(left: 21, top: 13, child: CitiLogo(height: 27, color: m.ink)),
        Positioned(
          left: 100,
          top: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(first, style: _t(9.5, FontWeight.w600, m.ink, spacing: 1.3)),
              const SizedBox(height: 3),
              Text(second, style: _t(9.5, FontWeight.w600, m.ink, spacing: 1.3)),
            ],
          ),
        ),
        Positioned(left: 18, top: 80, child: ContactlessIcon(size: 13, color: m.ink.withValues(alpha: 0.85))),
        Positioned(left: 38, top: 72, child: _Chip(finish: card.design.chipFinish, width: 42)),
        Positioned(
          left: 22,
          right: 150,
          bottom: 18,
          child: Text(
            card.holderName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(13, FontWeight.w700, m.ink, spacing: 0.8),
          ),
        ),
        Positioned(right: 18, bottom: 13, child: MastercardMark(width: 58, mono: true, wordmark: true, color: m.ink)),
      ],
    );
  }
}

/// Discover it: brushed metal, the chip, "DISCOVER" with its orange ball, and
/// the "it" badge cut off by the right edge.
class _DiscoverFront extends StatelessWidget {
  const _DiscoverFront(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final m = card.design.material;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, CardPattern.none)),
        Positioned(left: 42, top: 84, child: _Chip(finish: card.design.chipFinish, width: 48)),
        Positioned(left: 152, top: 96, child: DiscoverWordmark(height: 16, color: m.ink)),
        Positioned(
          right: 0,
          top: 79,
          width: 40,
          height: 56,
          child: CustomPaint(
            painter: _ItBadgePainter(m.ink),
            child: Align(
              alignment: const Alignment(0.34, 0.05),
              child: Text(card.design.product, style: _t(19, FontWeight.w700, m.ink, spacing: -0.3)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Any other card: the bank's name, chip, last four digits, name and network.
class _GenericFront extends StatelessWidget {
  const _GenericFront(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final design = card.design;
    final m = design.material;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, design.pattern)),
        if (design.showIssuer)
          Positioned(
            top: 26,
            left: 24,
            right: 90,
            child: Text(
              design.issuer.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(12.5, FontWeight.w700, m.ink, spacing: 2.4),
            ),
          ),
        Positioned(top: 24, right: 24, child: ContactlessIcon(size: 30, color: m.ink)),
        if (design.chip) Positioned(left: 24, top: 84, child: _Chip(finish: design.chipFinish)),
        if (card.last4 != null)
          Positioned(
            left: 24,
            bottom: 58,
            child: Text('••••  ${card.last4}', style: _t(15, FontWeight.w500, m.ink, spacing: 2, digits: true)),
          ),
        Positioned(
          left: 24,
          bottom: 34,
          right: 150,
          child: Text(
            card.holderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _nameStyle(m.ink),
          ),
        ),
        Positioned(
          right: 24,
          bottom: 21,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              NetworkMark(network: design.network, color: m.ink),
              Text(design.product, style: _t(11, FontWeight.w500, m.label, spacing: 0.3)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The reverse of any card: magnetic stripe, signature panel and security
/// code box, a line of small print, the masked number, expiry and name, and
/// the network mark.
class _Back extends StatelessWidget {
  const _Back(this.card);

  final CardArt card;

  @override
  Widget build(BuildContext context) {
    final design = card.design;
    final m = design.material;
    final amex = design.network == CardNetwork.amex;
    final digits = card.last4 ?? '••••';
    final number = amex ? '••••  ••••••  •$digits' : '••••  ••••  ••••  $digits';
    final small = design.isSlate
        ? 'This card is the property of Slate. Freeze it or report it lost in the Slate app.'
        : 'Shown in Slate for reference only. Slate keeps just the last 4 digits; '
            'this image can\'t be used to pay.';
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _MetalPainter(m, design.pattern)),
        if (design.style == CardStyle.citiStrata) CustomPaint(painter: _RimPainter()),
        const Positioned(left: 0, right: 0, top: 20, height: 38, child: _MagStripe()),
        Positioned(
          left: 22,
          top: 68,
          child: Text('AUTHORIZED SIGNATURE', style: _t(4.8, FontWeight.w700, m.label, spacing: 0.6)),
        ),
        const Positioned(left: 22, top: 76, width: 238, height: 28, child: _SignaturePanel()),
        Positioned(left: 264, top: 76, width: 50, height: 28, child: _CodeBox(amex: amex)),
        Positioned(
          left: 22,
          right: 22,
          top: 112,
          child: Text(small, maxLines: 2, style: _t(6.4, FontWeight.w500, m.label).copyWith(height: 1.4)),
        ),
        Positioned(
          left: 22,
          top: 146,
          child: Text(number, style: _t(15, FontWeight.w500, m.ink, spacing: 1.2, digits: true)),
        ),
        Positioned(
          left: 22,
          top: 172,
          child: Row(
            children: [
              Text('VALID\nTHRU', style: _t(4.6, FontWeight.w700, m.label, spacing: 0.4).copyWith(height: 1.2)),
              const SizedBox(width: 5),
              Text(card.expiry ?? '••/••', style: _t(12, FontWeight.w500, m.ink, digits: true)),
            ],
          ),
        ),
        Positioned(
          left: 22,
          right: 150,
          bottom: 22,
          child: Text(
            card.holderName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(12.5, FontWeight.w500, m.ink, spacing: 1.2),
          ),
        ),
        Positioned(
          right: 22,
          top: 148,
          child: Text(
            design.isSlate ? 'SLATE' : design.issuer.toUpperCase(),
            style: _t(8, FontWeight.w700, m.label, spacing: 1.6),
          ),
        ),
        Positioned(right: 20, bottom: 18, child: _BackNetworkMark(design)),
      ],
    );
  }
}

class _BackNetworkMark extends StatelessWidget {
  const _BackNetworkMark(this.design);

  final CardDesign design;

  @override
  Widget build(BuildContext context) {
    final ink = design.material.ink;
    return switch (design.network) {
      CardNetwork.amex => const AmexBlueBox(size: 38),
      CardNetwork.discover => DiscoverWordmark(height: 11, color: ink),
      CardNetwork.mastercard => MastercardMark(
          width: 50,
          mono: design.style == CardStyle.citiStrata,
          wordmark: true,
          color: ink,
        ),
      CardNetwork.visa => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VisaLogo(height: 18, color: ink),
            if (design.networkTier != null) ...[
              const SizedBox(height: 3),
              Transform(
                transform: Matrix4.skewX(-0.2),
                child: Text(design.networkTier!, style: _t(8.5, FontWeight.w600, ink, spacing: 0.3)),
              ),
            ],
          ],
        ),
    };
  }
}

class _MagStripe extends StatelessWidget {
  const _MagStripe();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0C0C0D), Color(0xFF232325), Color(0xFF101011)],
          stops: [0, 0.45, 1],
        ),
      ),
    );
  }
}

class _SignaturePanel extends StatelessWidget {
  const _SignaturePanel();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: CustomPaint(painter: _HatchPainter()),
    );
  }
}

class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEFEBE3));
    final line = Paint()
      ..color = const Color(0xFFD6CFC1)
      ..strokeWidth = 0.8;
    for (var x = -size.height; x < size.width; x += 3.2) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => false;
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.amex});

  final bool amex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
      child: Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-0.18),
          child: Text(amex ? '••••' : '•••', style: _t(11, FontWeight.w700, const Color(0xFF2A2A2A), spacing: 1)),
        ),
      ),
    );
  }
}

/// The network mark beside the tier on Slate cards and on cards from other
/// banks without their own layout, sized to sit above the product name.
class NetworkMark extends StatelessWidget {
  const NetworkMark({super.key, required this.network, required this.color});

  final CardNetwork network;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (network) {
      CardNetwork.visa => VisaLogo(height: 24, color: color),
      CardNetwork.amex => const Padding(padding: EdgeInsets.only(bottom: 5), child: AmexBlueBox(size: 30)),
      CardNetwork.mastercard => const Padding(padding: EdgeInsets.only(bottom: 6), child: MastercardMark(width: 42)),
      CardNetwork.discover => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DiscoverWordmark(height: 10, color: color),
        ),
    };
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

class _Chip extends StatelessWidget {
  const _Chip({this.finish = ChipFinish.gold, this.width = 46});

  final ChipFinish finish;
  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, width * 0.78), painter: _ChipPainter(finish));
  }
}

/// An EMV chip with its contact lines, in gold or palladium silver.
class _ChipPainter extends CustomPainter {
  _ChipPainter(this.finish);

  final ChipFinish finish;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final body = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.15));
    final gold = finish == ChipFinish.gold;
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gold
              ? const [Color(0xFFF3DC9A), Color(0xFFD2AE5C), Color(0xFFE8CB80)]
              : const [Color(0xFFF6F7F8), Color(0xFFBFC3C8), Color(0xFFE5E7EA)],
        ).createShader(rect),
    );
    final line = Paint()
      ..color = (gold ? const Color(0xFF8C6E2C) : const Color(0xFF6E747C)).withValues(alpha: 0.55)
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
  bool shouldRepaint(_ChipPainter oldDelegate) => oldDelegate.finish != finish;
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
  _MetalPainter(this.material, this.pattern, {this.patternHole});

  final CardMaterial material;
  final CardPattern pattern;

  /// An oval left free of the pattern (where the Amex portrait sits).
  final Rect? patternHole;

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
        final alpha = ((random.nextDouble() * 0.028 + 0.004) * material.brush).clamp(0.0, 1.0);
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
    canvas.save();
    if (patternHole != null) {
      canvas.clipPath(Path.combine(
        PathOperation.difference,
        Path()..addRect(rect),
        Path()..addOval(patternHole!.inflate(2)),
      ));
    }
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
      case CardPattern.engraved:
        engrave.color = material.ink.withValues(alpha: 0.06);
        for (double y = 2; y < size.height; y += 3) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 13) {
            path.quadraticBezierTo(x + 6.5, y + ((x ~/ 13).isEven ? 1.6 : -1.6), x + 13, y);
          }
          canvas.drawPath(path, engrave);
        }
      case CardPattern.none:
        break;
    }
    canvas.restore();

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
      oldDelegate.material != material || oldDelegate.pattern != pattern || oldDelegate.patternHole != patternHole;
}

/// Sapphire Reserve's light: a fine diamond lattice that shows faintly all
/// over and brightly where a warm glow falls from the top-right corner.
class _HaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    void lattice(Paint paint) {
      const slope = 0.62;
      const step = 7.0;
      final w = size.width;
      for (var c = -w * slope; c < size.height; c += step) {
        canvas.drawLine(Offset(0, c), Offset(w, c + w * slope), paint);
      }
      for (var c = 0.0; c < size.height + w * slope; c += step) {
        canvas.drawLine(Offset(0, c), Offset(w, c - w * slope), paint);
      }
    }

    lattice(Paint()
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.035));

    final glowCenter = Offset(size.width * 0.98, -size.height * 0.1);
    final glowRadius = size.width * 0.78;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          glowCenter,
          glowRadius,
          [
            const Color(0xFFE6D9BC).withValues(alpha: 0.62),
            const Color(0xFFA9A28F).withValues(alpha: 0.2),
            const Color(0x00000000),
          ],
          [0, 0.42, 1],
        ),
    );
    canvas.saveLayer(rect, Paint());
    lattice(Paint()
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.32));
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          glowCenter,
          glowRadius * 0.85,
          [const Color(0xFFFFFFFF), const Color(0x00FFFFFF)],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) => false;
}

/// Strata Premier's flowing contour lines across the right of the card.
class _WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const x0 = 70.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..shader = ui.Gradient.linear(
        const Offset(x0, 0),
        Offset(size.width * 0.62, 0),
        [const Color(0x00FFFFFF), Colors.white.withValues(alpha: 0.28)],
      );
    final span = size.width - x0 + 10;
    for (var i = 0; i < 30; i++) {
      final path = Path();
      for (var j = 0; j <= 60; j++) {
        final u = j / 60;
        final x = x0 + u * span;
        final y = size.height * 1.08 - i * 9.0 - u * size.height * 0.5 + 16 * math.sin(u * 5.4 + i * 0.2) * (0.35 + u);
        j == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter oldDelegate) => false;
}

/// A polished metal rim around the edge.
class _RimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(12.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F5F7), Color(0xFF8C9096), Color(0xFFE3E5E8), Color(0xFF6C7076)],
          stops: [0, 0.35, 0.6, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) => false;
}

/// The ring around "it", centred on the card's right edge.
class _ItBadgePainter extends CustomPainter {
  _ItBadgePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width + 4, size.height / 2);
    final radius = size.height / 2;
    canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: 0.07));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = color.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_ItBadgePainter oldDelegate) => oldDelegate.color != color;
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
