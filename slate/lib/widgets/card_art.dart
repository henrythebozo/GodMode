import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'card_designs.dart';
import 'network_marks.dart';
import 'card_slots.dart';
import 'visa_logo.dart';

/// A card face: the card's picture from `assets/cards/`, with the member's
/// own details (name, last four digits, ...) written where the real card
/// prints them. Laid out at a fixed 392 x 247 design size and scaled to the
/// width it is given, so every card keeps identical proportions at any size.
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
    final slots = cardSlots[design.art(back: back)] ?? const <TextSlot>[];
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
                  // Shows in the card's colours until the picture has loaded.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: design.material.gradient,
                      ),
                    ),
                  ),
                  Image.asset(
                    back ? design.backArt : design.frontArt,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                  for (final slot in slots)
                    if (_content(slot) case final content?)
                      Positioned.fromRect(
                        rect: slot.rect,
                        child: Align(alignment: slot.alignment, child: content),
                      ),
                  if (frozen && !back) const _FrozenVeil(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _content(TextSlot slot) {
    final ink = design.material.ink;
    // Slate's own cards print the name as written, like the reference design;
    // bank cards print it in capitals.
    final name = design.isSlate ? holderName : holderName.toUpperCase();
    final amex = design.network == CardNetwork.amex;
    return switch (slot.field) {
      SlotField.name => _Etched(name, size: slot.size, color: ink, weight: slot.weight, spacing: 1.2, align: slot.align),
      SlotField.last4 => last4 == null
          ? null
          : _Etched(last4!, size: slot.size, color: ink, weight: slot.weight, spacing: 1.4, digits: true),
      SlotField.memberSince => memberSince == null
          ? null
          : _Etched(memberSince!, size: slot.size, color: ink, weight: slot.weight, digits: true),
      SlotField.issuer => _Etched(design.issuer.toUpperCase(), size: slot.size, color: ink, weight: slot.weight, spacing: 2.2),
      SlotField.product => _Etched(design.product, size: slot.size, color: design.material.label, weight: slot.weight, spacing: 0.4),
      SlotField.number => _Etched(
          amex ? '••••  ••••••  •${last4 ?? '••••'}' : '••••  ••••  ••••  ${last4 ?? '••••'}',
          size: slot.size,
          color: ink,
          weight: slot.weight,
          spacing: 1.2,
          digits: true,
        ),
      SlotField.expiry => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Etched('VALID\nTHRU', size: slot.size * 0.38, color: design.material.label, weight: FontWeight.w700, height: 1.2),
            SizedBox(width: slot.size * 0.4),
            _Etched(expiry ?? '••/••', size: slot.size, color: ink, weight: slot.weight, digits: true),
          ],
        ),
      SlotField.network => NetworkMark(network: design.network, color: ink, height: slot.size),
    };
  }
}

/// Text that looks printed into the metal: the card's ink with a faint
/// highlight on the lower edge (or a faint shadow above, for light ink).
class _Etched extends StatelessWidget {
  const _Etched(
    this.text, {
    required this.size,
    required this.color,
    this.weight = FontWeight.w500,
    this.spacing = 0,
    this.digits = false,
    this.height = 1,
    this.align = TextAlign.left,
  });

  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final double spacing;
  final bool digits;
  final double height;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final lightInk = color.computeLuminance() > 0.45;
    return Text(
      text,
      maxLines: text.contains('\n') ? 2 : 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        fontFamily: SlateText.family,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color,
        fontFeatures: digits ? const [FontFeature.tabularFigures()] : null,
        shadows: [
          Shadow(
            offset: Offset(0, lightInk ? -0.5 : 0.6),
            color: (lightInk ? Colors.black : Colors.white).withValues(alpha: lightInk ? 0.35 : 0.3),
          ),
        ],
      ),
    );
  }
}

/// Network marks written onto cards the member described themselves.
class NetworkMark extends StatelessWidget {
  const NetworkMark({super.key, required this.network, required this.color, this.height = 24});

  final CardNetwork network;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return switch (network) {
      CardNetwork.visa => VisaLogo(height: height * 0.8, color: color),
      CardNetwork.amex => AmexBlueBox(size: height * 1.25),
      CardNetwork.mastercard => MastercardMark(width: height * 1.75),
      CardNetwork.discover => DiscoverWordmark(height: height * 0.42, color: color),
    };
  }
}

/// Loads the pictures of these cards ahead of time, front and back, so the
/// row and the carousel never show a card while its picture is still coming.
void precacheCardArt(BuildContext context, Iterable<WalletCard> cards) {
  for (final card in cards) {
    final design = CardCatalog.forCard(card);
    precacheImage(AssetImage(design.frontArt), context);
    precacheImage(AssetImage(design.backArt), context);
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
