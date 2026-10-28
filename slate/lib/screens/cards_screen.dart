import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/card_art.dart';
import '../widgets/card_designs.dart';
import '../widgets/common.dart';
import '../widgets/slate_nav_bar.dart';
import 'add_card_screen.dart';
import 'card_plans_screen.dart';

/// Every card in the wallet, then the round "+ Add" and the way to a Slate card.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final card = await Navigator.of(context).push(AddCardScreen.route());
    if (card != null && context.mounted) {
      showSlateSnack(context, '${CardCatalog.forCard(card).name} added.', aboveNav: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final safe = MediaQuery.paddingOf(context);
    final cards = state.walletCards;
    final ownsEveryPlan = state.plans.isNotEmpty &&
        state.plans.every((p) => state.cards.any((c) => c.planId == p.id));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: RefreshIndicator(
        onRefresh: state.refresh,
        color: SlateColors.ink,
        edgeOffset: safe.top,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(24, safe.top + 16, 24, SlateNavBar.reservedHeight(context)),
          children: [
            Text('Cards', style: SlateText.headline.copyWith(height: 1)),
            const SizedBox(height: 6),
            Text(
              cards.isEmpty
                  ? 'No cards yet. Add the ones you carry.'
                  : '${cards.length} ${cards.length == 1 ? 'card' : 'cards'} · tap one for details',
              style: SlateText.caption.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 24),
            for (final card in cards) ...[
              Pressable(
                scale: 0.98,
                onTap: () => showCardSheet(context, card),
                semanticLabel: '${CardCatalog.forCard(card).name} ending ${card.last4}',
                child: CardArt.of(card),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${CardCatalog.forCard(card).name} •••• ${card.last4}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SlateText.small,
                      ),
                    ),
                    switch (card) {
                      PaymentCard(:final isFrozen) => Text(
                          isFrozen ? 'Frozen' : 'Active',
                          style: SlateText.caption.copyWith(
                            color: isFrozen ? SlateColors.danger : SlateColors.positive,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      LinkedCard(:final nickname) => Text(
                          nickname ?? shortIssuer(card.issuer),
                          style: SlateText.caption.copyWith(fontWeight: FontWeight.w600),
                        ),
                    },
                  ],
                ),
              ),
              const SizedBox(height: 22),
            ],
            const SizedBox(height: 6),
            Center(child: AddCardButton(dark: false, onTap: () => _add(context))),
            if (!ownsEveryPlan) ...[
              const SizedBox(height: 28),
              PillButton(
                label: 'Get a Slate card',
                icon: Iconsax.card_copy,
                light: true,
                onPressed: () => Navigator.of(context).push(CardPlansScreen.route()),
              ),
            ],
          ],
        ),
      ),
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
