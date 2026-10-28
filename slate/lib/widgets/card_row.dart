import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import 'card_art.dart';
import 'card_designs.dart';
import 'common.dart';

/// The swipeable row of cards on the home screen. Every card is as wide as
/// the screen minus 24pt margins, the next one peeks in from the right, and
/// the row ends with the round "+ Add" button.
class CardRow extends StatefulWidget {
  const CardRow({
    super.key,
    required this.cards,
    required this.onOpen,
    required this.onAdd,
  });

  final List<WalletCard> cards;
  final ValueChanged<WalletCard> onOpen;
  final VoidCallback onAdd;

  @override
  State<CardRow> createState() => CardRowState();
}

class CardRowState extends State<CardRow> {
  static const _margin = 24.0;
  static const _gap = 12.0;

  PageController? _pages;
  double _fraction = 0;
  final _page = ValueNotifier<double>(0);

  @override
  void dispose() {
    _pages?.dispose();
    _page.dispose();
    super.dispose();
  }

  /// Scrolls to a card, e.g. one that was just added.
  void showCard(String id) {
    final index = widget.cards.indexWhere((c) => c.id == id);
    if (index < 0 || _pages == null || !_pages!.hasClients) return;
    _pages!.animateToPage(index, duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
  }

  bool _isCurrent(int i) => (_page.value.round()) == i;

  void _goTo(int i) =>
      _pages?.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);

  PageController _controllerFor(double fraction) {
    // viewportFraction is fixed when a PageController is made, so make a new
    // one if the screen width changes (rotation, split view).
    if (_pages != null && (fraction - _fraction).abs() < 0.001) return _pages!;
    final old = _pages;
    final page = old?.hasClients ?? false ? (old!.page ?? 0).round() : 0;
    // The PageView lets go of the old controller during this build; free it after.
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _fraction = fraction;
    return _pages = PageController(viewportFraction: fraction, initialPage: page)
      ..addListener(() => _page.value = _pages!.page ?? _page.value);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final cardWidth = width - _margin * 2;
        final controller = _controllerFor((cardWidth + _gap) / width);
        return Column(
          children: [
            SizedBox(
              height: cardWidth / CardArt.aspectRatio,
              child: PageView.builder(
                controller: controller,
                itemCount: cards.length + 1,
                onPageChanged: (_) => HapticFeedback.selectionClick(),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                  child: i < cards.length
                      ? Pressable(
                          scale: 0.98,
                          // A tap on a peeking card brings it in; on the centred one, opens it.
                          onTap: () => _isCurrent(i) ? widget.onOpen(cards[i]) : _goTo(i),
                          semanticLabel: '${CardCatalog.forCard(cards[i]).name} ending ${cards[i].last4}',
                          child: CardArt.of(cards[i]),
                        )
                      : GestureDetector(
                          // Pages don't rebuild while scrolling, so decide at tap time.
                          // Taps on the circle itself go to the button inside.
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!_isCurrent(i)) _goTo(i);
                          },
                          child: Center(child: AddCardButton(onTap: widget.onAdd)),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Dots(count: cards.length, page: _page),
          ],
        );
      },
    );
  }
}

/// One dot per card and a small "+" for the add button at the end.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page});

  final int count;
  final ValueNotifier<double> page;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: ValueListenableBuilder<double>(
        valueListenable: page,
        builder: (context, page, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i <= count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: i == count
                    ? Icon(
                        Iconsax.add_copy,
                        size: 9,
                        color: Colors.white.withValues(alpha: lerpDouble(1, 0.35, (page - i).abs().clamp(0.0, 1.0))!),
                      )
                    : Container(
                        width: lerpDouble(16, 6, (page - i).abs().clamp(0.0, 1.0)),
                        height: 6,
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            Colors.white,
                            Colors.white.withValues(alpha: 0.25),
                            (page - i).abs().clamp(0.0, 1.0),
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
