import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/slate_nav_bar.dart';

enum TransferMode {
  send('Send'),
  topUp('Top up'),
  convert('Convert');

  const TransferMode(this.label);
  final String label;
}

/// Send to a member, top up, or convert between currency wallets.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, required this.mode});

  final ValueNotifier<TransferMode> mode;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _amount = TextEditingController();
  final _email = TextEditingController();
  final _note = TextEditingController();
  final _amountFocus = FocusNode();

  String _currency = 'USD';
  String _target = 'EUR';
  bool _busy = false;

  // Recipient lookup, debounced while typing.
  Timer? _debounce;
  String? _recipientName;
  bool _lookingUp = false;
  String _lookedUp = '';

  /// One key per attempt: reused if the same payment is retried after a
  /// network error, replaced once it succeeds or the form changes.
  String? _requestId;

  @override
  void initState() {
    super.initState();
    widget.mode.addListener(_onModeChanged);
    _amount.addListener(_formChanged);
  }

  @override
  void dispose() {
    widget.mode.removeListener(_onModeChanged);
    _debounce?.cancel();
    _amount.dispose();
    _email.dispose();
    _note.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  TransferMode get _mode => widget.mode.value;

  void _onModeChanged() {
    _requestId = null;
    setState(() {});
  }

  void _formChanged() {
    _requestId = null;
    setState(() {});
  }

  void _onEmailChanged(String value) {
    _requestId = null;
    _debounce?.cancel();
    final email = value.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() {
        _recipientName = null;
        _lookedUp = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _lookingUp = true);
      try {
        final name = await AppScope.read(context).lookupRecipient(email);
        if (!mounted || _email.text.trim().toLowerCase() != email) return;
        setState(() {
          _recipientName = name;
          _lookedUp = email;
        });
      } on SlateException {
        // Lookup is only a hint; the transfer itself validates the recipient.
      } finally {
        if (mounted) setState(() => _lookingUp = false);
      }
    });
  }

  int? get _cents => parseAmount(_amount.text);

  String? _problem(AppState state) {
    final cents = _cents;
    if (cents == null) return null;
    final available = state.balanceOf(_currency);
    if (_mode != TransferMode.topUp && cents > available) return 'More than your balance';
    if (_mode == TransferMode.topUp && cents > 2500000) return r'Top-ups are limited to $25,000';
    return null;
  }

  bool _ready(AppState state) {
    if (_cents == null || _problem(state) != null) return false;
    return switch (_mode) {
      TransferMode.send => _recipientName != null && _lookedUp == _email.text.trim().toLowerCase(),
      TransferMode.topUp => true,
      TransferMode.convert => _currency != _target,
    };
  }

  Future<void> _submit() async {
    final state = AppScope.read(context);
    final cents = _cents;
    if (cents == null) return;
    FocusScope.of(context).unfocus();
    final requestId = _requestId ??= state.requestId();
    setState(() => _busy = true);
    try {
      final Txn txn;
      switch (_mode) {
        case TransferMode.send:
          txn = await state.transfer(_email.text, cents,
              currency: _currency, note: _note.text, requestId: requestId);
        case TransferMode.topUp:
          txn = await state.topUp(cents, currency: _currency, requestId: requestId);
        case TransferMode.convert:
          txn = await state.convert(_currency, _target, cents, requestId: requestId);
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _requestId = null;
      setState(() => _busy = false);
      await _showDone(txn);
      _amount.clear();
      _note.clear();
    } on SlateException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSlateSnack(context, e.message, error: true, aboveNav: true);
    }
  }

  Future<void> _showDone(Txn txn) {
    final state = AppScope.read(context);
    final amount = formatMoney(txn.amountCents, txn.currency);
    final credit = state.conversionCredit(txn);
    final message = switch (txn.kind) {
      TxnKind.transferOut => 'Sent $amount to ${txn.counterpartyName ?? 'them'}',
      TxnKind.topUp => 'Added $amount to your balance',
      TxnKind.conversionOut =>
        'Converted $amount${credit == null ? '' : ' to ${formatMoney(credit.amountCents, credit.currency)}'}',
      _ => 'Done',
    };
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutBack,
                builder: (context, t, child) => Transform.scale(scale: t, child: child),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: SlateColors.ink, shape: BoxShape.circle),
                  child: const Icon(Iconsax.tick_circle_copy, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: 18),
              Text(message, textAlign: TextAlign.center, style: SlateText.title.copyWith(fontSize: 19)),
              const SizedBox(height: 6),
              Text(
                'New balance ${formatMoney(txn.balanceAfterCents, txn.currency)}',
                style: SlateText.caption.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 24),
              PillButton(label: 'Done', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final safe = MediaQuery.paddingOf(context);
    final currencies = state.currencies.isEmpty
        ? const ['USD', 'EUR', 'GBP']
        : [for (final c in state.currencies) c.code];
    final problem = _problem(state);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            safe.top + 16,
            24,
            MediaQuery.viewInsetsOf(context).bottom + SlateNavBar.reservedHeight(context),
          ),
          children: [
            Text('Transfer', style: SlateText.headline.copyWith(height: 1)),
            const SizedBox(height: 14),
            _Balances(state: state),
            const SizedBox(height: 22),
            _ModeSwitch(
              value: _mode,
              onChanged: (mode) => widget.mode.value = mode,
            ),
            const SizedBox(height: 30),
            _AmountField(
              controller: _amount,
              focusNode: _amountFocus,
              currency: _currency,
              currencies: _mode == TransferMode.convert ? currencies : [_currency, ...currencies.where((c) => c != _currency)],
              onCurrency: (c) => setState(() {
                _currency = c;
                if (_target == c) _target = currencies.firstWhere((x) => x != c);
                _requestId = null;
              }),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                problem ??
                    (_mode == TransferMode.topUp
                        ? 'Balance ${formatMoney(state.balanceOf(_currency), _currency)}'
                        : 'Available ${formatMoney(state.balanceOf(_currency), _currency)}'),
                style: SlateText.caption.copyWith(
                  fontSize: 13,
                  color: problem == null ? SlateColors.muted : SlateColors.danger,
                ),
              ),
            ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child: switch (_mode) {
                  TransferMode.send => _sendFields(),
                  TransferMode.topUp => _topUpFields(),
                  TransferMode.convert => _convertFields(state, currencies),
                },
              ),
            ),
            const SizedBox(height: 28),
            PillButton(
              label: _buttonLabel(),
              loading: _busy,
              onPressed: _ready(state) ? _submit : null,
            ),
            if (_mode == TransferMode.topUp) ...[
              const SizedBox(height: 12),
              Text(
                'Simulated top-up: money is added instantly and no card or bank is charged.',
                textAlign: TextAlign.center,
                style: SlateText.caption.copyWith(fontSize: 11.5, color: SlateColors.hint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _buttonLabel() {
    final cents = _cents;
    final amount = cents == null ? '' : ' ${formatMoney(cents, _currency)}';
    return '${_mode.label}$amount';
  }

  Widget _sendFields() {
    final email = _email.text.trim().toLowerCase();
    final checked = _lookedUp == email && email.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SlateTextField(
          label: 'To',
          hint: 'Email of a Slate member',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: _onEmailChanged,
          suffix: _lookingUp
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: checked
              ? Padding(
                  padding: const EdgeInsets.only(top: 10, left: 4),
                  child: Row(
                    children: [
                      Icon(
                        _recipientName != null ? Iconsax.tick_circle_copy : Iconsax.info_circle_copy,
                        size: 16,
                        color: _recipientName != null ? SlateColors.positive : SlateColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _recipientName ?? 'No Slate member uses that email',
                        style: SlateText.caption.copyWith(
                          fontSize: 13,
                          color: _recipientName != null ? SlateColors.text : SlateColors.muted,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 20),
        SlateTextField(
          label: 'Note',
          hint: "What's it for? (optional)",
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
        ),
        if (AppScope.of(context).isDemo) ...[
          const SizedBox(height: 10),
          Text(
            'Demo members: jamie@slate.app, sam@slate.app',
            style: SlateText.caption.copyWith(fontSize: 11.5, color: SlateColors.hint),
          ),
        ],
      ],
    );
  }

  Widget _topUpFields() {
    const presets = [5000, 10000, 50000, 100000];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final cents in presets)
          Pressable(
            onTap: () {
              _amount.text = (cents / 100).toStringAsFixed(0);
              _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: _cents == cents ? SlateColors.ink : SlateColors.field,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                '+${formatMoney(cents, _currency, whole: true)}',
                style: SlateText.small.copyWith(color: _cents == cents ? Colors.white : SlateColors.text),
              ),
            ),
          ),
      ],
    );
  }

  Widget _convertFields(AppState state, List<String> currencies) {
    final cents = _cents;
    final rate = state.rate(_currency, _target);
    final receive = cents == null ? null : (cents * rate).floor();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: SlateColors.field, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('To', style: SlateText.caption.copyWith(fontSize: 13)),
              const Spacer(),
              for (final code in currencies.where((c) => c != _currency))
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Pressable(
                    onTap: () => setState(() {
                      _target = code;
                      _requestId = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _target == code ? SlateColors.ink : Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        code,
                        style: SlateText.small.copyWith(
                          color: _target == code ? Colors.white : SlateColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            receive == null ? 'You get —' : 'You get ${formatMoney(receive, _target)}',
            style: SlateText.title.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            '1 $_currency = ${rate.toStringAsFixed(4)} $_target · no fees',
            style: SlateText.caption.copyWith(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _Balances extends StatelessWidget {
  const _Balances({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final wallets = state.wallets.isEmpty
        ? [const Wallet(id: '-', currency: 'USD', balanceCents: 0)]
        : state.wallets;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (i, wallet) in wallets.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: i == 0 ? SlateColors.ink : SlateColors.field,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet.currency,
                    style: SlateText.caption.copyWith(
                      color: i == 0 ? SlateColors.onInkMuted : SlateColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatMoney(wallet.balanceCents, wallet.currency),
                    style: SlateText.body.copyWith(color: i == 0 ? Colors.white : SlateColors.text),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pill segmented control with a sliding black thumb.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.value, required this.onChanged});

  final TransferMode value;
  final ValueChanged<TransferMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const modes = TransferMode.values;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: SlateColors.field, borderRadius: BorderRadius.circular(25)),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth / modes.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: width * value.index,
                width: width,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: SlateColors.ink,
                    borderRadius: BorderRadius.circular(21),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in modes)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: mode == value,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onChanged(mode);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: SlateText.small.copyWith(
                                color: mode == value ? Colors.white : SlateColors.text,
                              ),
                              child: Text(mode.label),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Big centred amount with the currency symbol, plus a currency picker.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.focusNode,
    required this.currency,
    required this.currencies,
    required this.onCurrency,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String currency;
  final List<String> currencies;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final code in currencies)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Pressable(
                  onTap: () => onCurrency(code),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: code == currency ? SlateColors.field : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      code,
                      style: SlateText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: code == currency ? SlateColors.text : SlateColors.hint,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currencySymbol(currency),
              style: SlateText.balance.copyWith(color: SlateColors.text, fontSize: 48),
            ),
            IntrinsicWidth(
              child: TextField(
            controller: controller,
            focusNode: focusNode,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              TextInputFormatter.withFunction((oldValue, newValue) {
                final text = newValue.text.replaceAll(',', '.');
                final ok = RegExp(r'^\d{0,7}(\.\d{0,2})?$').hasMatch(text);
                return ok ? newValue.copyWith(text: text) : oldValue;
              }),
            ],
            style: SlateText.balance.copyWith(color: SlateColors.text, fontSize: 48),
            cursorWidth: 2.5,
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '0',
              hintStyle: SlateText.balance.copyWith(color: SlateColors.hint, fontSize: 48),
            ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
