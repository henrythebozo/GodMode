import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/card_designs.dart';
import '../widgets/card_row.dart';
import '../widgets/slate_nav_bar.dart';
import '../widgets/transaction_tile.dart';
import 'add_card_screen.dart';
import 'card_plans_screen.dart';
import 'cards_screen.dart';
import 'transactions_screen.dart';
import 'transfer_screen.dart';

/// Greeting, balance and card on black; recent transactions below.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onAction});

  /// Opens the transfer tab in a given mode (from the "+" sheet).
  final ValueChanged<TransferMode> onAction;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();
  final _scroll = ScrollController();
  final _overscroll = ValueNotifier<double>(0);
  final _row = GlobalKey<CardRowState>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _overscroll.value = (-_scroll.offset).clamp(0, 1000));
  }

  @override
  void dispose() {
    _intro.dispose();
    _scroll.dispose();
    _overscroll.dispose();
    super.dispose();
  }

  Widget _rise(double start, Widget child, {double distance = 30}) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(((_intro.value - start) / 0.5).clamp(0, 1));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, distance * (1 - t)), child: child),
        );
      },
      child: child,
    );
  }

  void _openAll({bool search = false}) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => TransactionsScreen(autofocusSearch: search)));
  }

  void _openPlans() {
    Navigator.of(context).push(CardPlansScreen.route());
  }

  Future<void> _addCard() async {
    final card = await Navigator.of(context).push(AddCardScreen.route());
    if (card == null || !mounted) return;
    showSlateSnack(context, '${CardCatalog.forCard(card).name} added.', aboveNav: true);
    // Wait for the row to rebuild with the new card, then glide to it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _row.currentState?.showCard(card.id));
  }

  void _showActions() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        Widget action(IconData icon, String title, String subtitle, VoidCallback onTap) {
          return Pressable(
            onTap: () {
              Navigator.pop(sheetContext);
              onTap();
            },
            scale: 0.98,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(color: SlateColors.field, shape: BoxShape.circle),
                    child: Icon(icon, size: 21, color: SlateColors.text),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: SlateText.body),
                        const SizedBox(height: 2),
                        Text(subtitle, style: SlateText.caption),
                      ],
                    ),
                  ),
                  const Icon(Iconsax.arrow_right_3_copy, size: 18, color: SlateColors.hint),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Move money', style: SlateText.headline.copyWith(fontSize: 24)),
                const SizedBox(height: 12),
                action(
                  Iconsax.add_copy,
                  'Top up',
                  'Add money to your balance',
                  () => widget.onAction(TransferMode.topUp),
                ),
                action(
                  Iconsax.export_3_copy,
                  'Send',
                  'Pay another Slate member',
                  () => widget.onAction(TransferMode.send),
                ),
                action(
                  Iconsax.arrow_swap_horizontal_copy,
                  'Convert',
                  'Swap between currencies',
                  () => widget.onAction(TransferMode.convert),
                ),
                action(Iconsax.card_add_copy, 'Add a card', 'Amex, Chase and other banks', _addCard),
                action(Iconsax.card_copy, 'Get a Slate card', 'Platinum, Silver or Gold', _openPlans),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final safe = MediaQuery.paddingOf(context);
    final feed = state.feed;
    final recent = feed.take(8).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          // Keeps the area above the header black while pulling down.
          ValueListenableBuilder<double>(
            valueListenable: _overscroll,
            builder: (_, pull, _) => Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: pull + 2,
              child: const ColoredBox(color: SlateColors.ink),
            ),
          ),
          RefreshIndicator(
            onRefresh: state.refresh,
            color: SlateColors.ink,
            backgroundColor: Colors.white,
            edgeOffset: safe.top,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: _header(state, safe)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 21, 24, 0),
                  sliver: SliverToBoxAdapter(
                    child: _rise(
                      0.35,
                      SectionHeader(title: 'Recent transactions', action: 'See all', onAction: _openAll),
                    ),
                  ),
                ),
                if (state.loadError != null && !state.hasData)
                  SliverToBoxAdapter(child: _error(state))
                else if (recent.isEmpty)
                  SliverToBoxAdapter(child: _rise(0.4, const _EmptyFeed()))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 7, 24, 0),
                    sliver: SliverList.builder(
                      itemCount: recent.length,
                      itemBuilder: (context, i) => _rise(
                        0.38 + i * 0.05,
                        TransactionTile(
                          txn: recent[i],
                          onTap: () => showTransactionSheet(context, recent[i]),
                        ),
                        distance: 18,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: SlateNavBar.reservedHeight(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppState state, EdgeInsets safe) {
    final name = firstName(state.profile?.fullName ?? '');
    final balance = state.balanceOf('USD');
    return Container(
      decoration: const BoxDecoration(
        color: SlateColors.ink,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      // No side padding here: the card row runs edge to edge so the next card
      // can peek in. Everything else is inset by 24.
      padding: EdgeInsets.only(top: safe.top + 7, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _greeting(name, balance)),
          const SizedBox(height: 19),
          _rise(
            0.1,
            CardRow(
              key: _row,
              cards: state.walletCards,
              onOpen: (card) => showCardSheet(context, card),
              onAdd: _addCard,
            ),
            distance: 40,
          ),
        ],
      ),
    );
  }

  Widget _greeting(String name, int balance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Hello $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlateText.headline.copyWith(color: Colors.white, height: 1),
              ),
            ),
            const SizedBox(width: 12),
            RoundIconButton(
              icon: Iconsax.search_normal_1_copy,
              label: 'Search transactions',
              onTap: () => _openAll(search: true),
            ),
            const SizedBox(width: 12),
            RoundIconButton(icon: Iconsax.add_copy, label: 'Move money', onTap: _showActions),
          ],
        ),
        const SizedBox(height: 31),
        Text(
          'Available balance',
          style: SlateText.caption.copyWith(
            color: SlateColors.onInkMuted,
            fontSize: 13,
            height: 1,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 11),
        AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            // Count up on first appearance, then just show the number.
            final t = Curves.easeOutExpo.transform((_intro.value / 0.85).clamp(0, 1));
            final shown = (balance * t).round();
            return Text(
              formatMoney(t < 1 ? shown - shown % 100 : balance, 'USD', whole: true),
              style: SlateText.balance.copyWith(height: 1),
            );
          },
        ),
      ],
    );
  }

  Widget _error(AppState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        children: [
          Text("Couldn't load your account.", style: SlateText.body),
          const SizedBox(height: 6),
          Text(state.loadError ?? '', textAlign: TextAlign.center, style: SlateText.caption),
          const SizedBox(height: 16),
          PillButton(label: 'Try again', onPressed: state.refresh, light: true, height: 48),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
      child: Column(
        children: [
          const Icon(Iconsax.receipt_2_copy, size: 30, color: SlateColors.hint),
          const SizedBox(height: 12),
          Text('No transactions yet', style: SlateText.body),
          const SizedBox(height: 4),
          Text('Top up to get started.', style: SlateText.caption),
        ],
      ),
    );
  }
}
