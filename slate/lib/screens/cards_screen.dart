import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/card_art.dart';
import '../widgets/card_designs.dart';
import '../widgets/carousel_parts.dart';
import '../widgets/common.dart';
import '../widgets/slate_nav_bar.dart';
import 'add_card_screen.dart';
import 'card_plans_screen.dart';

/// Every card in the wallet standing upright in a row you slide through; a
/// flick carries on past several. Each card you slide past is caught in the
/// gust and spins round before it settles, and tapping the front card turns
/// it over. Details opens the freeze / remove sheet, "+" adds a card.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final _shelf = GlobalKey<_CardShelfState>();
  final _page = ValueNotifier<double>(0);
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final card = await Navigator.of(context).push(AddCardScreen.route());
    if (card == null || !mounted) return;
    showSlateSnack(context, '${CardCatalog.forCard(card).name} added.', aboveNav: true);
    // Wait for the shelf to rebuild with the new card, then slide to it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _shelf.currentState?.showCard(card.id));
  }

  void _openPlans() => Navigator.of(context).push(CardPlansScreen.route());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final safe = MediaQuery.paddingOf(context);
    final cards = state.walletCards;
    final ownsEveryPlan = state.plans.isNotEmpty &&
        state.plans.every((p) => state.cards.any((c) => c.planId == p.id));
    final card = cards.isEmpty ? null : cards[_index.clamp(0, cards.length - 1)];
    final bottom = SlateNavBar.reservedHeight(context);
    // Room for everything but the cards, so a short screen scrolls instead of squashing them.
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final minHeight = safe.top + bottom + 170 + 110 * textScale + 220;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: LayoutBuilder(
        builder: (context, box) => RefreshIndicator(
          onRefresh: state.refresh,
          color: SlateColors.ink,
          edgeOffset: safe.top,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            child: SizedBox(
              height: math.max(box.maxHeight, minHeight),
              child: Padding(
                padding: EdgeInsets.only(top: safe.top + 16, bottom: bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _header(cards.length),
                    ),
                    if (card == null)
                      Expanded(child: _empty(ownsEveryPlan))
                    else ...[
                      Expanded(
                        child: _CardShelf(
                          key: _shelf,
                          cards: cards,
                          page: _page,
                          onIndex: (i) => setState(() => _index = i),
                        ),
                      ),
                      _caption(card),
                      const SizedBox(height: 14),
                      PageDots(count: cards.length, page: _page, color: SlateColors.text),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: PillButton(
                                label: 'Details',
                                icon: Iconsax.info_circle_copy,
                                height: 52,
                                onPressed: () => showCardSheet(context, card),
                              ),
                            ),
                            if (!ownsEveryPlan) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: PillButton(
                                  label: 'Get a Slate card',
                                  light: true,
                                  height: 52,
                                  onPressed: _openPlans,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int count) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cards', style: SlateText.headline.copyWith(height: 1)),
              const SizedBox(height: 6),
              Text(
                count == 0
                    ? 'No cards yet. Add the ones you carry.'
                    : '$count ${count == 1 ? 'card' : 'cards'} · tap one to turn it over',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlateText.caption.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        RoundIconButton(
          icon: Iconsax.add_copy,
          label: 'Add a card',
          onTap: _add,
          background: SlateColors.field,
          foreground: SlateColors.text,
        ),
      ],
    );
  }

  Widget _caption(WalletCard card) {
    final (status, color) = switch (card) {
      PaymentCard(:final isFrozen) => (
          isFrozen ? 'Frozen' : 'Active',
          isFrozen ? SlateColors.danger : SlateColors.positive,
        ),
      LinkedCard(:final nickname) => (nickname ?? shortIssuer(card.issuer), SlateColors.muted),
    };
    return AnimatedSwitcher(
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
              style: SlateText.headline.copyWith(fontSize: 22, height: 1.1),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '•••• ${card.last4}  ·  '),
                  TextSpan(text: status, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SlateText.caption.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(bool ownsEveryPlan) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: AddCardButton(dark: false, onTap: _add)),
            if (!ownsEveryPlan) ...[
              const SizedBox(height: 28),
              PillButton(label: 'Get a Slate card', icon: Iconsax.card_copy, light: true, onPressed: _openPlans),
            ],
          ],
        ),
      ),
    );
  }
}

/// The cards stood up in a row, the current one in front. Swipes go to an
/// invisible [PageView] (with [CardSpinPhysics], so a flick runs on); every
/// card has its own spin, which the gust and the turn-over both drive. A
/// card the row carries away from the front spins round once it's out to
/// the side, so you land on a card and see the one you left whirl.
class _CardShelf extends StatefulWidget {
  const _CardShelf({super.key, required this.cards, required this.page, required this.onIndex});

  final List<WalletCard> cards;

  /// Where the row is, in cards (1.5 = halfway between the second and third).
  final ValueNotifier<double> page;
  final ValueChanged<int> onIndex;

  @override
  State<_CardShelf> createState() => _CardShelfState();
}

class _CardShelfState extends State<_CardShelf> with TickerProviderStateMixin {
  /// One card's worth of swipe, as a share of the width.
  static const _swipe = 0.55;

  /// The gust: a quick spin that slows, overshoots by about 20 degrees and
  /// settles back, over a second and a half.
  static final _gust = SpringDescription.withDampingRatio(mass: 1, stiffness: 24, ratio: 0.64);
  static const _gustSpeed = 7.0; // radians per second as it starts

  late final _pages = PageController(viewportFraction: _swipe);
  int _index = 0;

  /// Each card's turn about its upright axis, in radians: a multiple of 2π is
  /// face up, an odd multiple of π face down.
  final _spins = <String, AnimationController>{};

  /// Where each spin is heading, so a second tap during a turn reverses it.
  final _rest = <String, double>{};

  /// Cards that have been at the front since they last spun: the gust takes
  /// each one once the row has carried it most of the way out to the side.
  final _armed = <String>{};
  double _lastPage = 0;

  @override
  void initState() {
    super.initState();
    _pages.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_pages.hasClients || !_pages.position.haveDimensions) return;
    final page = _pages.page!;
    final last = _lastPage;
    _lastPage = page;
    widget.page.value = page;
    if (page == last) return;
    final cards = widget.cards;
    for (var i = 0; i < cards.length; i++) {
      final id = cards[i].id;
      // At the front just now or now, or passed it between two frames.
      if ((i - last).abs() < 0.5 || (i - page).abs() < 0.5 || (i - last).sign != (i - page).sign) _armed.add(id);
      if ((i - page).abs() >= 0.8 && _armed.remove(id)) _blow(id, (page - last).sign);
    }
  }

  @override
  void didUpdateWidget(_CardShelf old) {
    super.didUpdateWidget(old);
    final ids = {for (final c in widget.cards) c.id};
    final gone = [for (final id in _spins.keys) if (!ids.contains(id)) id];
    if (gone.isEmpty) return;
    final spins = [for (final id in gone) _spins.remove(id)!];
    gone.forEach(_rest.remove);
    // Still listened to by this frame's builder; let go after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final spin in spins) {
        spin.dispose();
      }
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final spin in _spins.values) {
      spin.dispose();
    }
    super.dispose();
  }

  AnimationController _spinOf(String id) => _spins.putIfAbsent(id, () => AnimationController.unbounded(vsync: this));

  /// Slides to a card, e.g. one that was just added.
  void showCard(String id) {
    final index = widget.cards.indexWhere((c) => c.id == id);
    if (index < 0 || !_pages.hasClients) return;
    _pages.animateToPage(index, duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic);
  }

  void _go(int index) {
    if (index < 0 || index >= widget.cards.length) return;
    _pages.animateToPage(index, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
  }

  void _onPage(int index) {
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    widget.onIndex(index);
  }

  /// Spins a card most of the way round, or further, landing face up.
  void _blow(String id, double direction) {
    final spin = _spinOf(id);
    final from = spin.value;
    const turn = 2 * math.pi;
    final to = direction > 0
        ? ((from + 1.6 * math.pi) / turn).ceil() * turn
        : ((from - 1.6 * math.pi) / turn).floor() * turn;
    _rest[id] = to;
    final carry = spin.isAnimating ? spin.velocity : 0.0;
    spin.animateWith(SpringSimulation(_gust, from, to, carry + direction * _gustSpeed));
  }

  /// Turns the front card over, or back again.
  void _turnOver() {
    final cards = widget.cards;
    if (cards.isEmpty) return;
    final id = cards[_index.clamp(0, cards.length - 1)].id;
    final spin = _spinOf(id);
    final rest = _rest[id] ?? (spin.value / math.pi).round() * math.pi;
    final faceDown = (rest / math.pi).round().isOdd;
    // Face up turns to the back; the back turns the way it came.
    final to = faceDown ? rest - math.pi : rest + math.pi;
    _rest[id] = to;
    HapticFeedback.lightImpact();
    spin.animateTo(to, duration: const Duration(milliseconds: 560), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    final index = _index.clamp(0, cards.length - 1);
    final card = cards[index];
    final name = CardCatalog.forCard(card).name;
    return LayoutBuilder(
      builder: (context, box) {
        // An upright card as tall as the space allows, leaving room either
        // side for the neighbours, so a card spinning away stays in sight.
        final cardHeight = math.min(box.maxHeight * 0.9, box.maxWidth * 0.48 * CardArt.aspectRatio);
        final cardWidth = cardHeight / CardArt.aspectRatio;
        return Semantics(
          label: '$name ending ${card.last4}, card ${index + 1} of ${cards.length}',
          hint: 'Swipe to slide through your cards. Double tap to turn this one over.',
          onIncrease: index < cards.length - 1 ? () => _go(index + 1) : null,
          onDecrease: index > 0 ? () => _go(index - 1) : null,
          onTap: _turnOver,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final dx = details.localPosition.dx - box.maxWidth / 2;
              if (dx.abs() <= cardWidth / 2) {
                _turnOver();
              } else {
                _go(index + dx.sign.toInt());
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: _Row(
                    cards: cards,
                    page: widget.page,
                    spins: [for (final c in cards) _spinOf(c.id)],
                    cardSize: Size(cardWidth, cardHeight),
                  ),
                ),
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: PageView.builder(
                      controller: _pages,
                      pageSnapping: false,
                      physics: CardSpinPhysics(extent: box.maxWidth * _swipe),
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
      },
    );
  }
}

/// Draws the row: the front card full size, its neighbours smaller, turned
/// in towards it and fading into the page, each turned by its own spin. A
/// card spinning fast lifts and tips a little, as if the gust had it.
class _Row extends StatelessWidget {
  const _Row({required this.cards, required this.page, required this.spins, required this.cardSize});

  final List<WalletCard> cards;
  final ValueListenable<double> page;
  final List<AnimationController> spins;
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([page, ...spins]),
      builder: (context, _) {
        final corner = BorderRadius.circular(cardSize.width * 14 / 247);
        final placed = <(double, Widget)>[];
        for (var i = 0; i < cards.length; i++) {
          final offset = i - page.value;
          final distance = offset.abs();
          if (distance > 3.2) continue;
          final near = math.min(distance, 1.0);
          final far = (distance - 1).clamp(0.0, 2.0);
          final x = offset.sign * (near * 0.66 + far * 0.3) * cardSize.width;
          final scale = 1 - 0.16 * near - 0.08 * far;
          final spin = spins[i];
          final speed = spin.isAnimating ? spin.velocity : 0.0;
          final turn = -offset.clamp(-1.0, 1.0) * 0.35 + spin.value;
          final back = math.cos(turn) < 0;

          Widget face = PortraitCard(child: CardArt.of(cards[i], back: back));
          // A back face is drawn mirrored so it reads correctly once turned.
          if (back) face = Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: face);
          placed.add((
            distance,
            Transform(
              key: ValueKey(cards[i].id),
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..translateByDouble(x, -math.min(speed.abs() * 0.6, 12.0), 0, 1)
                ..scaleByDouble(scale, scale, 1, 1)
                ..rotateX((speed * 0.006).clamp(-0.12, 0.12))
                ..rotateY(turn),
              child: SizedBox.fromSize(
                size: cardSize,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: corner,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22 * (1 - near * 0.6)),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: (distance * 0.22).clamp(0.0, 0.6)),
                    borderRadius: corner,
                  ),
                  child: face,
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

/// Details for any card in the wallet: Slate cards can be frozen, cards from
/// other banks can be removed.
Future<void> showCardSheet(BuildContext context, WalletCard card) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => switch (card) {
      PaymentCard() => _SlateCardSheet(cardId: card.id),
      LinkedCard() => _LinkedCardSheet(card: card),
    },
  );
}

Widget _rows(List<(String, String)> rows) {
  return Column(
    children: [
      for (final (i, (label, value)) in rows.indexed) ...[
        if (i > 0) const Hairline(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Text(label, style: SlateText.caption.copyWith(fontSize: 13)),
              const SizedBox(width: 16),
              Expanded(child: Text(value, textAlign: TextAlign.right, style: SlateText.small)),
            ],
          ),
        ),
      ],
    ],
  );
}

class _SlateCardSheet extends StatefulWidget {
  const _SlateCardSheet({required this.cardId});

  final String cardId;

  @override
  State<_SlateCardSheet> createState() => _SlateCardSheetState();
}

class _SlateCardSheetState extends State<_SlateCardSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _setFrozen(PaymentCard card, bool frozen) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).setCardFrozen(card, frozen);
      HapticFeedback.mediumImpact();
    } on SlateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final card = state.cards.where((c) => c.id == widget.cardId).firstOrNull;
    if (card == null) return const SizedBox(height: 120);
    final plan = state.planFor(card.planId);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardArt.of(card),
            const SizedBox(height: 20),
            _rows([
              ('Card number', '•••• •••• •••• ${card.last4}'),
              ('Expires', card.expiry),
              ('Cardholder', card.holderName),
              if (plan != null) ('Annual fee', formatMoney(plan.annualFeeCents, plan.currency)),
              ('Issued', formatDay(card.createdAt)),
            ]),
            const Hairline(),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Iconsax.lock_copy, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Freeze card', style: SlateText.body),
                      Text('Block new payments until you unfreeze it.', style: SlateText.caption),
                    ],
                  ),
                ),
                _busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Switch(value: card.isFrozen, onChanged: (v) => _setFrozen(card, v)),
              ],
            ),
            InlineError(_error),
            if (plan != null && plan.perks.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('${plan.name} perks', style: SlateText.label),
              const SizedBox(height: 6),
              for (final perk in plan.perks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Iconsax.tick_circle_copy, size: 16, color: SlateColors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(perk, style: SlateText.caption.copyWith(fontSize: 13))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkedCardSheet extends StatefulWidget {
  const _LinkedCardSheet({required this.card});

  final LinkedCard card;

  @override
  State<_LinkedCardSheet> createState() => _LinkedCardSheetState();
}

class _LinkedCardSheetState extends State<_LinkedCardSheet> {
  bool _confirming = false;
  bool _busy = false;
  String? _error;

  Future<void> _remove() async {
    if (!_confirming) {
      HapticFeedback.selectionClick();
      setState(() => _confirming = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).removeLinkedCard(widget.card);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      showSlateSnack(context, '${CardCatalog.forCard(widget.card).name} removed.', aboveNav: true);
    } on SlateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardArt.of(card),
            const SizedBox(height: 20),
            _rows([
              ('Bank', card.issuer),
              ('Card', card.product),
              ('Number', '•••• ${card.last4}'),
              ('Name on card', card.holderName),
              if (card.nickname != null) ('Nickname', card.nickname!),
              ('Added', formatDay(card.createdAt)),
            ]),
            const Hairline(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Iconsax.shield_tick_copy, size: 16, color: SlateColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Saved for display only. Slate has just the last 4 digits and can't make payments with it.",
                    style: SlateText.caption.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
            InlineError(_error),
            const SizedBox(height: 20),
            PillButton(
              label: _confirming ? 'Tap again to remove' : 'Remove card',
              icon: Iconsax.trash_copy,
              light: !_confirming,
              loading: _busy,
              onPressed: _remove,
            ),
          ],
        ),
      ),
    );
  }
}
