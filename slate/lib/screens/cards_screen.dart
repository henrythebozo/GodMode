import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/slate_card.dart';
import '../widgets/slate_nav_bar.dart';
import 'card_plans_screen.dart';

/// The member's cards, newest on top, plus the way into the plan picker.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final safe = MediaQuery.paddingOf(context);
    final cards = state.cards.reversed.toList();
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
                  ? 'You have no cards yet.'
                  : '${cards.length} ${cards.length == 1 ? 'card' : 'cards'} · tap one for details',
              style: SlateText.caption.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (cards.isEmpty)
              EmptyCardSlot(
                dark: false,
                onTap: () => Navigator.of(context).push(CardPlansScreen.route()),
              ),
            for (final card in cards) ...[
              Pressable(
                scale: 0.98,
                onTap: () => showCardSheet(context, card),
                child: SlateCard.fromCard(
                  card,
                  tierLabel: state.planFor(card.planId)?.name ?? card.planId,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${state.planFor(card.planId)?.name ?? 'Card'} •••• ${card.last4}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SlateText.small,
                      ),
                    ),
                    Text(
                      card.isFrozen ? 'Frozen' : 'Active',
                      style: SlateText.caption.copyWith(
                        color: card.isFrozen ? SlateColors.danger : SlateColors.positive,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
            ],
            if (!ownsEveryPlan)
              PillButton(
                label: cards.isEmpty ? 'Choose a card' : 'Get another card',
                icon: Iconsax.card_add_copy,
                onPressed: () => Navigator.of(context).push(CardPlansScreen.route()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card details and the freeze switch.
Future<void> showCardSheet(BuildContext context, PaymentCard card) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CardSheet(cardId: card.id),
  );
}

class _CardSheet extends StatefulWidget {
  const _CardSheet({required this.cardId});

  final String cardId;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
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
    final rows = <(String, String)>[
      ('Card number', '•••• •••• •••• ${card.last4}'),
      ('Expires', card.expiry),
      ('Cardholder', card.holderName),
      if (plan != null) ('Annual fee', formatMoney(plan.annualFeeCents, plan.currency)),
      ('Issued', formatDay(card.createdAt)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SlateCard.fromCard(card, tierLabel: plan?.name ?? card.planId),
            const SizedBox(height: 20),
            for (final (i, (label, value)) in rows.indexed) ...[
              if (i > 0) const Hairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  children: [
                    Text(label, style: SlateText.caption.copyWith(fontSize: 13)),
                    const Spacer(),
                    Text(value, style: SlateText.small),
                  ],
                ),
              ),
            ],
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
                    : Switch(
                        value: card.isFrozen,
                        onChanged: (v) => _setFrozen(card, v),
                      ),
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
