import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/card_art.dart';
import '../widgets/card_designs.dart';

/// "Choose Silver": portrait cards in a carousel, with the plan name and
/// price sliding along above them.
class CardPlansScreen extends StatefulWidget {
  const CardPlansScreen({super.key, this.initialPlan});

  final String? initialPlan;

  static Route<void> route({String? initialPlan}) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => CardPlansScreen(initialPlan: initialPlan),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  State<CardPlansScreen> createState() => _CardPlansScreenState();
}

class _CardPlansScreenState extends State<CardPlansScreen> with SingleTickerProviderStateMixin {
  static const _viewport = 0.66; // page width / screen width, from the frames
  static const _sideScale = 0.88; // neighbouring cards

  PageController? _pages;
  final _page = ValueNotifier<double>(0);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  bool _ordering = false;

  @override
  void initState() {
    super.initState();
    unawaited(AppScope.read(context).loadPlans());
  }

  @override
  void dispose() {
    _pages?.dispose();
    _page.dispose();
    _intro.dispose();
    super.dispose();
  }

  PageController _controllerFor(List<CardPlan> plans) {
    if (_pages != null) return _pages!;
    final start = widget.initialPlan == null
        ? 0
        : plans.indexWhere((p) => p.id == widget.initialPlan).clamp(0, plans.length - 1);
    _page.value = start.toDouble();
    return _pages = PageController(viewportFraction: _viewport, initialPage: start)
      ..addListener(() => _page.value = _pages!.page ?? _page.value);
  }

  Future<void> _choose(CardPlan plan) async {
    final state = AppScope.read(context);
    final owned = state.cards.any((c) => c.planId == plan.id && c.status != CardStatus.cancelled);
    if (owned) {
      showSlateSnack(context, 'You already have a ${plan.name} card.', error: true);
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _ConfirmSheet(plan: plan, balance: state.balanceOf(plan.currency)),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _ordering = true);
    try {
      await state.orderCard(plan.id, requestId: state.requestId());
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
      showSlateSnack(context, 'Your ${plan.name} card is ready.', aboveNav: true);
    } on SlateException catch (e) {
      if (!mounted) return;
      setState(() => _ordering = false);
      showSlateSnack(context, e.message, error: true);
    }
  }

  Widget _enter(double start, Widget child, {double distance = 24}) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(((_intro.value - start) / 0.6).clamp(0, 1));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, distance * (1 - t)), child: child),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final plans = state.plans;
    final safe = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: SlateColors.paper,
        body: Padding(
          padding: EdgeInsets.only(top: safe.top),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: RoundIconButton(
                      icon: Iconsax.arrow_left_2_copy,
                      label: 'Back',
                      background: Colors.transparent,
                      foreground: SlateColors.text,
                      iconSize: 22,
                      onTap: () => Navigator.maybePop(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              if (plans.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else ...[
                _enter(0, _TitleStrip(plans: plans, page: _page, width: width), distance: 12),
                Expanded(child: _carousel(plans, state)),
                _enter(0.25, _Dots(count: plans.length, page: _page)),
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, safe.bottom + 15),
                  child: _enter(
                    0.3,
                    ValueListenableBuilder<double>(
                      valueListenable: _page,
                      builder: (context, page, _) {
                        final plan = plans[page.round().clamp(0, plans.length - 1)];
                        return PillButton(
                          label: 'Choose ${plan.name}',
                          loading: _ordering,
                          onPressed: () => _choose(plan),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _carousel(List<CardPlan> plans, AppState state) {
    final holder = state.profile?.fullName ?? 'Slate member';
    return LayoutBuilder(
      builder: (context, box) {
        final pageWidth = box.maxWidth * _viewport;
        // Card fills the page minus 6pt each side, unless the screen is short.
        final cardWidth = (pageWidth - 12).clamp(0.0, box.maxHeight * 0.94 / CardArt.aspectRatio);
        return PageView.builder(
          controller: _controllerFor(plans),
          itemCount: plans.length,
          onPageChanged: (_) => HapticFeedback.selectionClick(),
          itemBuilder: (context, i) => ValueListenableBuilder<double>(
            valueListenable: _page,
            builder: (context, page, child) {
              final distance = (page - i).abs().clamp(0.0, 1.0);
              return Transform.scale(scale: lerpDouble(1, _sideScale, distance), child: child);
            },
            child: Center(
              child: _enter(
                0.05 + 0.08 * (i - (_page.value.round())).abs(),
                SizedBox(
                  width: cardWidth,
                  child: Pressable(
                    scale: 0.98,
                    onTap: () => _pages?.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                    ),
                    child: PortraitCard(
                      child: CardArt(design: CardCatalog.slatePlan(plans[i].id), holderName: holder),
                    ),
                  ),
                ),
                distance: 80,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Plan name and price, sliding at half the screen width per page so the
/// neighbours peek in faintly at the edges.
class _TitleStrip extends StatelessWidget {
  const _TitleStrip({required this.plans, required this.page, required this.width});

  final List<CardPlan> plans;
  final ValueNotifier<double> page;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ValueListenableBuilder<double>(
        valueListenable: page,
        builder: (context, page, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < plans.length; i++)
              if ((i - page).abs() < 1.8)
                Positioned(
                  left: (i - page) * width / 2,
                  width: width,
                  top: 0,
                  child: Opacity(
                    opacity: _opacity((i - page).abs()),
                    child: Column(
                      children: [
                        Text(
                          plans[i].name,
                          style: SlateText.headline.copyWith(fontSize: 32, letterSpacing: -1.6, height: 1),
                        ),
                        const SizedBox(height: 12),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: formatMoney(plans[i].annualFeeCents, plans[i].currency, whole: true),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const TextSpan(
                                text: ' / year',
                                style: TextStyle(color: SlateColors.subtle),
                              ),
                            ],
                          ),
                          style: SlateText.small.copyWith(fontSize: 15, height: 1, letterSpacing: -0.3),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static double _opacity(double distance) {
    if (distance <= 1) return lerpDouble(1, 0.07, Curves.easeOut.transform(distance))!;
    return lerpDouble(0.07, 0, ((distance - 1) / 0.8).clamp(0, 1))!;
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page});

  final int count;
  final ValueNotifier<double> page;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: page,
      builder: (context, page, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              width: lerpDouble(18, 6, (page - i).abs().clamp(0.0, 1.0)),
              height: 6,
              decoration: BoxDecoration(
                color: Color.lerp(SlateColors.ink, SlateColors.dot, (page - i).abs().clamp(0.0, 1.0)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.plan, required this.balance});

  final CardPlan plan;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final fee = formatMoney(plan.annualFeeCents, plan.currency);
    final enough = balance >= plan.annualFeeCents;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${plan.name} card', style: SlateText.headline.copyWith(fontSize: 24)),
            const SizedBox(height: 6),
            Text(
              '$fee for the first year, paid from your balance.',
              style: SlateText.caption.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 18),
            for (final perk in plan.perks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Iconsax.tick_circle_copy, size: 18, color: SlateColors.text),
                    const SizedBox(width: 10),
                    Expanded(child: Text(perk, style: SlateText.small)),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            if (!enough)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Your balance is ${formatMoney(balance, plan.currency)}. Top up first to order this card.',
                  style: SlateText.caption.copyWith(color: SlateColors.danger, fontSize: 13),
                ),
              ),
            PillButton(
              label: 'Pay $fee',
              onPressed: enough ? () => Navigator.pop(context, true) : null,
            ),
          ],
        ),
      ),
    );
  }
}
