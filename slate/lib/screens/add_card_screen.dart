import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/card_art.dart';
import '../widgets/card_designs.dart';
import '../widgets/common.dart';

/// Add a card you hold at another bank: pick it, then type its last four
/// digits. Pops with the new [LinkedCard].
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});

  static Route<LinkedCard> route() => MaterialPageRoute<LinkedCard>(builder: (_) => const AddCardScreen());

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  /// The picked catalog card; null with [_custom] false means still choosing.
  CardDesign? _design;
  bool _custom = false;

  final _form = GlobalKey<FormState>();
  final _last4 = TextEditingController();
  late final _name = TextEditingController(text: AppScope.read(context).profile?.fullName ?? '');
  final _nickname = TextEditingController();
  final _issuer = TextEditingController();
  final _product = TextEditingController();
  CardNetwork _network = CardNetwork.visa;
  String _color = 'custom_black';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_last4, _name, _issuer, _product]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_last4, _name, _nickname, _issuer, _product]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _choosing => _design == null && !_custom;

  void _pick(CardDesign? design) {
    HapticFeedback.selectionClick();
    setState(() {
      _design = design;
      _custom = design == null;
      _error = null;
    });
  }

  void _back() {
    if (_choosing) {
      Navigator.pop(context);
    } else {
      setState(() {
        _design = null;
        _custom = false;
        _error = null;
      });
    }
  }

  /// What the preview and the saved card use.
  CardDesign get _preview => _design ??
      CardDesign(
        id: _color,
        issuer: _issuer.text.trim().isEmpty ? 'Your bank' : _issuer.text.trim(),
        product: _product.text.trim().isEmpty ? 'Card' : _product.text.trim(),
        network: _network,
        material: CardCatalog.customColors[_color]!,
      );

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final design = _preview;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final card = await AppScope.read(context).addLinkedCard(NewLinkedCard(
        designId: design.id,
        issuer: design.issuer,
        product: design.product,
        network: design.network,
        last4: _last4.text,
        holderName: _name.text,
        nickname: _nickname.text,
      ));
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context, card);
    } on SlateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return PopScope(
      canPop: _choosing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: SlateColors.paper,
          body: Padding(
            padding: EdgeInsets.only(top: safe.top),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        onTap: _back,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _choosing ? _picker(safe) : _details(safe),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SlateText.headline.copyWith(height: 1)),
        const SizedBox(height: 8),
        Text(subtitle, style: SlateText.caption.copyWith(fontSize: 13)),
      ],
    );
  }

  Widget _picker(EdgeInsets safe) {
    final holder = _name.text.trim().isEmpty ? 'Your name' : _name.text.trim();
    return ListView(
      key: const ValueKey('picker'),
      padding: EdgeInsets.fromLTRB(24, 12, 24, safe.bottom + 24),
      children: [
        _heading('Add a card', 'Keep every card in one place. Slate only saves the last 4 digits.'),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 18,
          crossAxisSpacing: 12,
          childAspectRatio: 0.98,
          children: [
            for (final design in CardCatalog.addable)
              _Tile(
                art: CardArt(design: design, holderName: holder),
                title: design.name,
                subtitle: design.nickname ?? shortIssuer(design.issuer),
                onTap: () => _pick(design),
              ),
            _Tile(
              art: const _OtherSlot(),
              title: 'Other card',
              subtitle: 'Any bank',
              onTap: () => _pick(null),
            ),
          ],
        ),
      ],
    );
  }

  Widget _details(EdgeInsets safe) {
    final design = _preview;
    final last4 = _last4.text.padRight(4, '•');
    final holder = _name.text.trim().isEmpty ? 'Your name' : _name.text.trim();
    return Form(
      key: _form,
      child: ListView(
        key: const ValueKey('details'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(24, 12, 24, safe.bottom + MediaQuery.viewInsetsOf(context).bottom + 24),
        children: [
          _heading(_custom ? 'Other card' : design.name, 'Check the details, then add it to your wallet.'),
          const SizedBox(height: 20),
          CardArt(design: design, holderName: holder, last4: last4),
          const SizedBox(height: 24),
          if (_custom) ...[
            SlateTextField(
              label: 'Bank',
              hint: 'e.g. Wells Fargo',
              controller: _issuer,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the bank.' : null,
            ),
            const SizedBox(height: 18),
            SlateTextField(
              label: 'Card name',
              hint: 'e.g. Autograph',
              controller: _product,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the card name.' : null,
            ),
            const SizedBox(height: 18),
            Text('Network', style: SlateText.label),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final network in CardNetwork.values)
                  _Choice(
                    label: switch (network) {
                      CardNetwork.visa => 'Visa',
                      CardNetwork.mastercard => 'Mastercard',
                      CardNetwork.amex => 'Amex',
                      CardNetwork.discover => 'Discover',
                    },
                    selected: network == _network,
                    onTap: () => setState(() => _network = network),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Colour', style: SlateText.label),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final entry in CardCatalog.customColors.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      button: true,
                      selected: entry.key == _color,
                      label: entry.key.replaceFirst('custom_', ''),
                      child: GestureDetector(
                        onTap: () => setState(() => _color = entry.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 34,
                          height: 34,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: entry.key == _color ? SlateColors.ink : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: entry.value.gradient,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          SlateTextField(
            label: 'Last 4 digits',
            hint: '1234',
            controller: _last4,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            validator: (v) => RegExp(r'^\d{4}$').hasMatch(v ?? '') ? null : 'Enter the last 4 digits.',
          ),
          const SizedBox(height: 18),
          SlateTextField(
            label: 'Name on card',
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name on the card.' : null,
          ),
          const SizedBox(height: 18),
          SlateTextField(
            label: 'Nickname',
            hint: 'Optional, e.g. Travel',
            controller: _nickname,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          InlineError(_error),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Iconsax.shield_tick_copy, size: 16, color: SlateColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Slate never asks for the full card number or security code, and can't make payments with this card.",
                  style: SlateText.caption.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          PillButton(label: 'Add card', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.art, required this.title, required this.subtitle, required this.onTap});

  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          art,
          const SizedBox(height: 10),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SlateText.small.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: SlateText.caption),
        ],
      ),
    );
  }
}

/// Dashed-feel placeholder for "Other card".
class _OtherSlot extends StatelessWidget {
  const _OtherSlot();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: CardArt.aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: SlateColors.hint, width: 1.2),
        ),
        child: const Center(child: Icon(Iconsax.add_copy, size: 26, color: SlateColors.text)),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? SlateColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(label, style: SlateText.small.copyWith(color: selected ? Colors.white : SlateColors.text)),
      ),
    );
  }
}
