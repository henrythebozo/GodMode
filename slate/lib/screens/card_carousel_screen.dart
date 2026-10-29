import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/card_art.dart';
import '../widgets/card_designs.dart';
import '../widgets/card_hero.dart';
import '../widgets/common.dart';
import 'cards_screen.dart';

/// Every card in the wallet standing upright on a ring. Swiping spins the
/// ring (a flick carries on through several cards), tapping the front card
/// turns it over, and Details opens the freeze / remove sheet. Pull down or
/// tap close to go back.
class CardCarouselScreen extends StatefulWidget {
  const CardCarouselScreen({super.key, required this.initialIndex, required this.onClose});

  final int initialIndex;

  /// Gets the front card's id as the screen closes, so the row underneath can
  /// show that card before it flies back.
  final ValueChanged<String> onClose;

  static Route<void> route({required int initialIndex, required ValueChanged<String> onClose}) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 650),
      reverseTransitionDuration: const Duration(milliseconds: 520),
      pageBuilder: (_, _, _) => CardCarouselScreen(initialIndex: initialIndex, onClose: onClose),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  @override
  State<CardCarouselScreen> createState() => _CardCarouselScreenState();
}

class _CardCarouselScreenState extends State<CardCarouselScreen> with TickerProviderStateMixin {
  /// Angle between neighbouring cards on the ring.
  static const _step = 0.58;

  /// Ring radius, in card widths.
  static const _radius = 1.55;

  /// The ring is seen from a little above, so cards going round the back rise
  /// behind the front one.
  static const _tilt = 0.14;

  /// How far one card's worth of swipe travels, as a share of the width.
  static const _swipe = 0.55;

  late int _index = widget.initialIndex;
  late final _pages = PageController(initialPage: widget.initialIndex, viewportFraction: _swipe);
  late final _page = ValueNotifier<double>(widget.initialIndex.toDouble());

  /// Turning the front card over, 0 = face up.
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  int? _flipped;

  /// How far the ring has been pulled down to close.
  final _pull = ValueNotifier<double>(0);
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
    ..addListener(() => _pull.value = _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value)));
  double _settleFrom = 0;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      if (_pages.hasClients && _pages.position.haveDimensions) _page.value = _pages.page!;
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _page.dispose();
    _flip.dispose();
    _pull.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _onPage(int index) {
    HapticFeedback.selectionClick();
    if (_flipped != null) _flip.reverse(); // the card that was turned over turns back as it leaves
    setState(() => _index = index);
  }

  void _go(int index, int count) {
    if (index < 0 || index >= count) return;
    _pages.animateToPage(index, duration: const Duration(milliseconds: 560), curve: Curves.easeOutCubic);
  }

  void _turnOver() {
    HapticFeedback.lightImpact();
    if (_flipped != _index) {
      setState(() => _flipped = _index);
      _flip.value = 0;
      _flip.forward();
    } else if (_flip.status == AnimationStatus.forward || _flip.status == AnimationStatus.completed) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  void _close() => Navigator.of(context).maybePop();

  void _onPullEnd(DragEndDetails details) {
    if (_pull.value > 110 || (details.primaryVelocity ?? 0) > 900) {
      _close();
      return;
    }
    _settleFrom = _pull.value;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cards = AppScope.of(context).walletCards;
    if (cards.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const ColoredBox(color: Colors.black);
    }
    final index = _index.clamp(0, cards.length - 1);
    final card = cards[index];

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.onClose(card.id);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // A soft pool of light behind the front card.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.2),
                    radius: 0.85,
                    colors: [Color(0xFF242427), Colors.black],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 24, 0),
                    child: Row(
                      children: [
                        RoundIconButton(icon: Icons.close_rounded, label: 'Close', onTap: _close, iconSize: 22),
                        const Spacer(),
                        Text(
                          '${index + 1} of ${cards.length}',
                          style: SlateText.small.copyWith(color: SlateColors.onInkMuted),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: LayoutBuilder(builder: (context, box) => _carousel(cards, index, box))),
                  _caption(card, cards.length),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActionButton(icon: Iconsax.convert_card_copy, label: 'Turn over', onTap: _turnOver),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionButton(
                            icon: Iconsax.info_circle_copy,
                            label: 'Details',
                            onTap: () => showCardSheet(context, card),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carousel(List<WalletCard> cards, int index, BoxConstraints box) {
    // An upright card as tall as the space allows, but leaving room either
    // side for the neighbours to show.
    final cardHeight = math.min(box.maxHeight * 0.8, box.maxWidth * 0.53 * CardArt.aspectRatio);
    final cardWidth = cardHeight / CardArt.aspectRatio;
    final card = cards[index];
    final name = CardCatalog.forCard(card).name;

    return Semantics(
      label: '$name ending ${card.last4}, card ${index + 1} of ${cards.length}',
      hint: 'Swipe to spin the cards. Double tap to turn this one over.',
      onIncrease: index < cards.length - 1 ? () => _go(index + 1, cards.length) : null,
      onDecrease: index > 0 ? () => _go(index - 1, cards.length) : null,
      onTap: _turnOver,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final dx = details.localPosition.dx - box.maxWidth / 2;
          if (dx.abs() <= cardWidth / 2) {
            _turnOver();
          } else {
            _go(index + dx.sign.toInt(), cards.length);
          }
        },
        onVerticalDragStart: (_) => _settle.stop(),
        onVerticalDragUpdate: (details) => _pull.value = math.max(0, _pull.value + details.delta.dy),
        onVerticalDragEnd: _onPullEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _pull,
                builder: (context, pull, ring) => Transform.translate(
                  offset: Offset(0, pull * 0.6),
                  child: Transform.scale(scale: 1 - math.min(pull, 300) / 1500, child: ring),
                ),
                child: _Ring(
                  cards: cards,
                  index: index,
                  page: _page,
                  flip: _flip,
                  flipped: _flipped,
                  cardSize: Size(cardWidth, cardHeight),
                ),
              ),
            ),
            // Invisible pages that turn swipes into ring positions.
            Positioned.fill(
              child: ExcludeSemantics(
                child: PageView.builder(
                  controller: _pages,
                  pageSnapping: false,
                  physics: _SpinPhysics(extent: box.maxWidth * _swipe),
                  itemCount: cards.length,
                  onPageChanged: _onPage,
                  itemBuilder: (_, _) => const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption(WalletCard card, int count) {
    final details = [
      '•••• ${card.last4}',
      if (card case LinkedCard(:final nickname?)) nickname,
      if (card case PaymentCard(:final expiry)) 'Expires $expiry',
      if (card case PaymentCard(isFrozen: true)) 'Frozen',
    ].join('  ·  ');
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Padding(
            key: ValueKey(card.id),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  CardCatalog.forCard(card).name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SlateText.headline.copyWith(color: Colors.white, fontSize: 24),
                ),
                const SizedBox(height: 6),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SlateText.small.copyWith(color: SlateColors.onInkMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Dots(count: count, page: _page),
      ],
    );
  }
}

/// The cards placed around a vertical axis behind the screen: the front card
/// faces you, the others turn away as they go round, and cards past a
/// quarter turn show their backs.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.cards,
    required this.index,
    required this.page,
    required this.flip,
    required this.flipped,
    required this.cardSize,
  });

  final List<WalletCard> cards;
  final int index;
  final ValueListenable<double> page;
  final Animation<double> flip;
  final int? flipped;
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([page, flip]),
      builder: (context, _) {
        final radius = _CardCarouselScreenState._radius * cardSize.width;
        final corner = BorderRadius.circular(cardSize.width * 14 / 247);
        final placed = <(double, Widget)>[];
        for (var i = 0; i < cards.length; i++) {
          final theta = (i - page.value) * _CardCarouselScreenState._step;
          if (theta.abs() > 2.2) continue; // round the back of the ring, out of sight
          final x = radius * math.sin(theta);
          final z = radius * (1 - math.cos(theta));
          // Facing outwards: a card to the right turns its right edge away.
          final spin = -theta + (i == flipped ? flip.value * math.pi : 0);
          final back = math.cos(spin) < 0;
          final dim = (theta.abs() / _CardCarouselScreenState._step * 0.3).clamp(0.0, 0.75);

          Widget face = PortraitCard(child: CardArt.of(cards[i], back: back));
          // A back face is drawn mirrored so it reads correctly once turned.
          if (back) face = Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: face);
          placed.add((
            z,
            Transform(
              key: ValueKey(cards[i].id),
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0011)
                ..rotateX(-_CardCarouselScreenState._tilt)
                ..translateByDouble(x, 0, z, 1)
                ..rotateY(spin),
              child: SizedBox.fromSize(
                size: cardSize,
                child: HeroMode(
                  enabled: i == index,
                  child: CardHero(
                    card: cards[i],
                    child: Container(
                      foregroundDecoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: dim),
                        borderRadius: corner,
                      ),
                      child: face,
                    ),
                  ),
                ),
              ),
            ),
          ));
        }
        placed.sort((a, b) => b.$1.compareTo(a.$1)); // farthest first
        return Stack(alignment: Alignment.center, children: [for (final (_, card) in placed) card]);
      },
    );
  }
}

/// A flick keeps the ring spinning through several cards, then lands exactly
/// on one.
class _SpinPhysics extends ScrollPhysics {
  const _SpinPhysics({required this.extent, super.parent});

  /// Pixels of swipe per card.
  final double extent;

  @override
  _SpinPhysics applyTo(ScrollPhysics? ancestor) => _SpinPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Pulled past either end (iOS lets you), or flicked against one: the
    // platform physics bounce or clamp it back.
    if (position.outOfRange ||
        (velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final landing = FrictionSimulation(0.05, position.pixels, velocity).finalX;
    final target = ((landing / extent).round() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    final ahead = (target - position.pixels) * velocity > 0;
    if (velocity.abs() > tolerance.velocity && ahead && (target - position.pixels).abs() > tolerance.distance) {
      return FrictionSimulation.through(position.pixels, target, velocity, tolerance.velocity * velocity.sign);
    }
    if ((target - position.pixels).abs() < tolerance.distance && velocity.abs() < tolerance.velocity) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page});

  final int count;
  final ValueListenable<double> page;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: ValueListenableBuilder<double>(
        valueListenable: page,
        builder: (context, page, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 6 + 10 * (1 - (page - i).abs().clamp(0.0, 1.0)),
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Color.lerp(Colors.white, Colors.white.withValues(alpha: 0.25), (page - i).abs().clamp(0.0, 1.0)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: SlateColors.chip,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlateText.label.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
