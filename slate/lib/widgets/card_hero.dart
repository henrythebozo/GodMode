import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'card_art.dart';

/// Lets a wallet card fly between the home row, where it lies flat, and the
/// card carousel, where it stands upright: on the way it turns a quarter turn
/// and tips back in 3D, then settles.
class CardHero extends StatelessWidget {
  const CardHero({super.key, required this.card, required this.child});

  final WalletCard card;
  final Widget child;

  static Object tag(String cardId) => 'wallet-card-$cardId';

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag(card.id),
      flightShuttleBuilder: (_, animation, _, _, _) => _CardFlight(card: card, animation: animation),
      child: child,
    );
  }
}

class _CardFlight extends StatelessWidget {
  const _CardFlight({required this.card, required this.animation});

  final WalletCard card;

  /// 0 in the home row, 1 in the carousel, whichever way the card is flying.
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: CardArt.of(card),
      builder: (context, art) {
        // The hero's path uses this curve too, so the turn and the move land together.
        final t = Curves.fastOutSlowIn.transform(animation.value.clamp(0.0, 1.0));
        final angle = t * math.pi / 2;
        return LayoutBuilder(
          builder: (context, box) {
            // The longest card that, turned by [angle], still fits the hero's rect.
            const ratio = CardArt.aspectRatio;
            final c = math.cos(angle);
            final s = math.sin(angle);
            final length = math.min(box.maxWidth / (c + s / ratio), box.maxHeight / (s + c / ratio));
            return Center(
              child: OverflowBox(
                minWidth: length,
                maxWidth: length,
                minHeight: length / ratio,
                maxHeight: length / ratio,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateZ(angle)
                    ..rotateY(math.sin(t * math.pi) * 0.55),
                  child: art,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
