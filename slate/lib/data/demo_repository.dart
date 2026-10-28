import 'dart:async';
import 'dart:math';

import '../utils/format.dart';
import 'models.dart';
import 'slate_repository.dart';

/// In-memory backend used when no Supabase project is configured. It is
/// seeded with the account from the reference screenshots and enforces the
/// same rules, limits and messages as the SQL functions, so every screen can
/// be tried without any setup.
class DemoRepository implements SlateRepository {
  DemoRepository({this.latency = const Duration(milliseconds: 350), DateTime? now}) {
    _seed(now ?? DateTime.now());
  }

  final Duration latency;
  final _signals = StreamController<AuthSignal>.broadcast();
  final _random = Random();

  bool _signedIn = false;
  late Profile _profile;
  final Map<String, Wallet> _wallets = {};
  final List<PaymentCard> _cards = [];
  final List<Txn> _txns = [];
  final Map<String, Object> _done = {}; // request id -> result

  static const _members = {
    'jamie@slate.app': 'Jamie Rivera',
    'sam@slate.app': 'Sam Lee',
  };

  static const _plans = [
    CardPlan(
      id: 'platinum',
      name: 'Platinum',
      annualFeeCents: 24900,
      currency: 'USD',
      perks: ['3% cashback on travel', 'Airport lounge access', 'No foreign exchange fees'],
    ),
    CardPlan(
      id: 'silver',
      name: 'Silver',
      annualFeeCents: 9900,
      currency: 'USD',
      perks: ['1% cashback on everything', 'Free ATM withdrawals', 'Instant card freeze'],
    ),
    CardPlan(
      id: 'gold',
      name: 'Gold',
      annualFeeCents: 14900,
      currency: 'USD',
      perks: ['2% cashback on dining', 'Purchase protection', 'Priority support'],
    ),
  ];

  static const _currencies = [
    Currency(code: 'USD', name: 'US Dollar', usdRate: 1),
    Currency(code: 'EUR', name: 'Euro', usdRate: 0.92),
    Currency(code: 'GBP', name: 'British Pound', usdRate: 0.79),
  ];

  void _seed(DateTime now) {
    _profile = const Profile(id: 'demo', fullName: 'Alex Carter', email: 'demo@slate.app');
    _wallets
      ..['USD'] = const Wallet(id: 'w-usd', currency: 'USD', balanceCents: 2200000)
      ..['EUR'] = const Wallet(id: 'w-eur', currency: 'EUR', balanceCents: 130640);
    final day = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int hour, int minute) =>
        day.subtract(Duration(days: daysAgo)).add(Duration(hours: hour, minutes: minute));
    _cards.add(PaymentCard(
      id: 'card-platinum',
      planId: 'platinum',
      holderName: 'Alex Carter',
      last4: '4821',
      expiryMonth: 10,
      expiryYear: 2030,
      status: CardStatus.active,
      createdAt: at(8, 11, 0),
    ));
    var n = 0;
    Txn row(TxnKind kind, int cents, int after, DateTime time,
        {String currency = 'USD', String description = '', String? who, String? group}) {
      n++;
      return Txn(
        id: 'seed-$n',
        kind: kind,
        amountCents: cents,
        currency: currency,
        balanceAfterCents: after,
        createdAt: time,
        groupId: group ?? 'g-$n',
        description: description,
        counterpartyName: who,
        cardId: kind == TxnKind.cardFee ? 'card-platinum' : null,
      );
    }

    // Newest first, matching the home screen in the screenshots.
    _txns.addAll([
      row(TxnKind.transferOut, 105000, 2200000, at(1, 16, 7), description: 'Concert tickets', who: 'Jamie Rivera'),
      row(TxnKind.topUp, 240000, 2305000, at(1, 12, 7), description: 'Added to your balance'),
      row(TxnKind.conversionIn, 87400, 130640, at(2, 16, 7), currency: 'EUR', description: 'USD → EUR', group: 'g-conv-2'),
      row(TxnKind.conversionOut, 95000, 2065000, at(2, 16, 7), description: 'USD → EUR', group: 'g-conv-2'),
      row(TxnKind.transferOut, 105000, 2160000, at(3, 16, 7), description: 'Dinner', who: 'Jamie Rivera'),
      row(TxnKind.topUp, 120000, 2265000, at(4, 9, 12), description: 'Added to your balance'),
      row(TxnKind.conversionIn, 43240, 43240, at(5, 16, 40), currency: 'EUR', description: 'USD → EUR', group: 'g-conv-1'),
      row(TxnKind.conversionOut, 47000, 2145000, at(5, 16, 40), description: 'USD → EUR', group: 'g-conv-1'),
      row(TxnKind.transferIn, 216900, 2192000, at(7, 19, 30), description: 'Rent share', who: 'Jamie Rivera'),
      row(TxnKind.cardFee, 24900, 1975100, at(8, 11, 0), description: 'Platinum card · annual fee'),
      row(TxnKind.topUp, 2000000, 2000000, at(9, 10, 0), description: 'Added to your balance'),
    ]);
  }

  Future<void> _pause() => Future.delayed(latency);

  void _requireSignedIn() {
    if (!_signedIn) throw const SlateException('You need to be signed in.');
  }

  @override
  bool get isDemo => true;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<AuthSignal> get authSignals => _signals.stream;

  // ------------------------------------------------------------------ auth

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _checkCredentials(String email, String password) {
    if (!_emailPattern.hasMatch(email.trim())) {
      throw const SlateException('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw const SlateException('Password should be at least 6 characters.');
    }
  }

  void _becomeSignedIn() {
    _signedIn = true;
    _signals.add(AuthSignal.signedIn);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _pause();
    _checkCredentials(email, password);
    _profile = Profile(id: _profile.id, fullName: _profile.fullName, email: email.trim().toLowerCase());
    _becomeSignedIn();
  }

  @override
  Future<bool> signUp({required String name, required String email, required String password}) async {
    await _pause();
    if (name.trim().isEmpty) throw const SlateException('Enter your name.');
    _checkCredentials(email, password);
    _profile = Profile(id: _profile.id, fullName: name.trim(), email: email.trim().toLowerCase());
    _cards.replaceRange(
      0,
      _cards.length,
      [for (final card in _cards) _renamed(card, name.trim())],
    );
    _becomeSignedIn();
    return false;
  }

  PaymentCard _renamed(PaymentCard card, String name) => PaymentCard(
        id: card.id,
        planId: card.planId,
        holderName: name,
        last4: card.last4,
        expiryMonth: card.expiryMonth,
        expiryYear: card.expiryYear,
        status: card.status,
        createdAt: card.createdAt,
      );

  @override
  Future<void> signInWith(SocialProvider provider) async {
    await _pause();
    _becomeSignedIn();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _pause();
    if (!_emailPattern.hasMatch(email.trim())) {
      throw const SlateException('Enter a valid email address.');
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    await _pause();
    if (password.length < 6) {
      throw const SlateException('Password should be at least 6 characters.');
    }
  }

  @override
  Future<void> signOut() async {
    await _pause();
    _signedIn = false;
    _signals.add(AuthSignal.signedOut);
  }

  // ------------------------------------------------------------------ reads

  @override
  Future<Profile> fetchProfile() async {
    _requireSignedIn();
    return _profile;
  }

  @override
  Future<List<Wallet>> fetchWallets() async {
    _requireSignedIn();
    return _wallets.values.toList();
  }

  @override
  Future<List<PaymentCard>> fetchCards() async {
    _requireSignedIn();
    return List.of(_cards);
  }

  @override
  Future<List<Txn>> fetchTransactions({int limit = 100}) async {
    _requireSignedIn();
    final sorted = List.of(_txns)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<List<CardPlan>> fetchPlans() async => _plans;

  @override
  Future<List<Currency>> fetchCurrencies() async => _currencies;

  // ------------------------------------------------------------------ writes

  @override
  Future<void> updateName(String name) async {
    await _pause();
    _requireSignedIn();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const SlateException('Enter your name.');
    if (trimmed.length > 80) throw const SlateException('Keep your name under 80 characters.');
    _profile = _profile.copyWith(fullName: trimmed);
  }

  String _currency(String code) {
    final upper = code.trim().toUpperCase();
    if (!_currencies.any((c) => c.code == upper)) {
      throw const SlateException("That currency isn't supported.");
    }
    return upper;
  }

  void _checkAmount(int cents, int max) {
    if (cents <= 0) throw const SlateException('Enter an amount greater than zero.');
    if (cents > max) throw const SlateException('That amount is over the limit for one payment.');
  }

  Wallet _wallet(String currency) =>
      _wallets[currency] ??= Wallet(id: 'w-${currency.toLowerCase()}', currency: currency, balanceCents: 0);

  Txn _post(TxnKind kind, int cents, String currency,
      {String description = '', String? who, String? group, String? cardId}) {
    final wallet = _wallet(currency);
    final after = wallet.balanceCents + (kind == TxnKind.topUp ||
            kind == TxnKind.transferIn ||
            kind == TxnKind.conversionIn
        ? cents
        : -cents);
    _wallets[currency] = wallet.withBalance(after);
    final txn = Txn(
      id: 'local-${_txns.length + 1}-${_random.nextInt(1 << 30)}',
      kind: kind,
      amountCents: cents,
      currency: currency,
      balanceAfterCents: after,
      createdAt: DateTime.now(),
      groupId: group ?? newRequestId(),
      description: description,
      counterpartyName: who,
      cardId: cardId,
    );
    _txns.insert(0, txn);
    return txn;
  }

  @override
  Future<Txn> topUp({required int cents, required String currency, required String requestId}) async {
    await _pause();
    _requireSignedIn();
    final code = _currency(currency);
    _checkAmount(cents, 2500000);
    if (_done[requestId] case final Txn previous) return previous;
    final txn = _post(TxnKind.topUp, cents, code, description: 'Added to your balance');
    _done[requestId] = txn;
    return txn;
  }

  @override
  Future<String?> lookupRecipient(String email) async {
    await Future.delayed(latency ~/ 2);
    final key = email.trim().toLowerCase();
    if (key == _profile.email) return null;
    return _members[key];
  }

  @override
  Future<Txn> transfer({
    required String email,
    required int cents,
    required String currency,
    String? note,
    required String requestId,
  }) async {
    await _pause();
    _requireSignedIn();
    final code = _currency(currency);
    _checkAmount(cents, 100000000);
    final key = email.trim().toLowerCase();
    if (key == _profile.email) throw const SlateException("You can't send money to yourself.");
    final name = _members[key];
    if (name == null) throw const SlateException('No Slate account uses that email.');
    if (_done[requestId] case final Txn previous) return previous;
    if (_wallet(code).balanceCents < cents) throw const SlateException('Insufficient funds.');
    final text = (note ?? '').trim();
    final txn = _post(TxnKind.transferOut, cents, code,
        description: text.length > 140 ? text.substring(0, 140) : text, who: name);
    _done[requestId] = txn;
    return txn;
  }

  @override
  Future<Txn> convert({
    required String from,
    required String to,
    required int cents,
    required String requestId,
  }) async {
    await _pause();
    _requireSignedIn();
    final source = _currency(from);
    final target = _currency(to);
    if (source == target) throw const SlateException('Pick two different currencies.');
    _checkAmount(cents, 100000000);
    final rate = _rate(target) / _rate(source);
    final received = (cents * rate).floor();
    if (received <= 0) throw const SlateException('That amount is too small to convert.');
    if (_done[requestId] case final Txn previous) return previous;
    if (_wallet(source).balanceCents < cents) throw const SlateException('Insufficient funds.');
    final group = newRequestId();
    final out = _post(TxnKind.conversionOut, cents, source, description: '$source → $target', group: group);
    _post(TxnKind.conversionIn, received, target, description: '$source → $target', group: group);
    _done[requestId] = out;
    return out;
  }

  double _rate(String code) => _currencies.firstWhere((c) => c.code == code).usdRate;

  @override
  Future<PaymentCard> orderCard({required String planId, required String requestId}) async {
    await _pause();
    _requireSignedIn();
    final plan = _plans.where((p) => p.id == planId.trim().toLowerCase()).firstOrNull;
    if (plan == null) throw const SlateException("That card plan doesn't exist.");
    if (_done[requestId] case final PaymentCard previous) return previous;
    if (_cards.any((c) => c.planId == plan.id && c.status != CardStatus.cancelled)) {
      throw SlateException('You already have a ${plan.name} card.');
    }
    if (_wallet(plan.currency).balanceCents < plan.annualFeeCents) {
      throw const SlateException('Insufficient funds.');
    }
    final now = DateTime.now();
    final card = PaymentCard(
      id: 'card-${plan.id}-${_random.nextInt(1 << 30)}',
      planId: plan.id,
      holderName: _profile.fullName.isEmpty ? 'Slate member' : _profile.fullName,
      last4: _random.nextInt(10000).toString().padLeft(4, '0'),
      expiryMonth: now.month,
      expiryYear: now.year + 4,
      status: CardStatus.active,
      createdAt: now,
    );
    _cards.add(card);
    if (plan.annualFeeCents > 0) {
      _post(TxnKind.cardFee, plan.annualFeeCents, plan.currency,
          description: '${plan.name} card · annual fee', cardId: card.id);
    }
    _done[requestId] = card;
    return card;
  }

  @override
  Future<PaymentCard> setCardFrozen({required String cardId, required bool frozen}) async {
    await _pause();
    _requireSignedIn();
    final index = _cards.indexWhere((c) => c.id == cardId && c.status != CardStatus.cancelled);
    if (index < 0) throw const SlateException('Card not found.');
    final card = _cards[index].withStatus(frozen ? CardStatus.frozen : CardStatus.active);
    _cards[index] = card;
    return card;
  }
}
