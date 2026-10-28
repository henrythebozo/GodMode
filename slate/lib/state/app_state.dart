import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../data/slate_repository.dart';
import '../utils/format.dart';

/// The signed-in member's data plus every action the screens can take. One
/// instance lives for the whole app; widgets read it through [AppScope].
class AppState extends ChangeNotifier {
  AppState(this.repository) {
    _signals = repository.authSignals.listen(_onSignal);
  }

  final SlateRepository repository;
  late final StreamSubscription<AuthSignal> _signals;

  Profile? profile;
  List<Wallet> wallets = const [];
  List<PaymentCard> cards = const [];
  List<LinkedCard> linkedCards = const [];
  List<Txn> transactions = const [];
  List<CardPlan> plans = const [];
  List<Currency> currencies = const [];

  bool loading = false;
  String? loadError;

  /// Set when someone opens a password-reset link; the shell shows the
  /// "choose a new password" sheet and clears it.
  bool pendingPasswordRecovery = false;

  bool get isDemo => repository.isDemo;
  bool get isSignedIn => repository.isSignedIn;
  bool get hasData => profile != null;

  void _onSignal(AuthSignal signal) {
    switch (signal) {
      case AuthSignal.signedIn:
        if (profile == null && !loading) unawaited(refresh());
      case AuthSignal.signedOut:
        _clear();
      case AuthSignal.passwordRecovery:
        pendingPasswordRecovery = true;
        notifyListeners();
    }
  }

  void _clear() {
    profile = null;
    wallets = const [];
    cards = const [];
    linkedCards = const [];
    transactions = const [];
    loadError = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ derived

  Wallet? walletFor(String currency) =>
      wallets.where((w) => w.currency == currency).firstOrNull;

  int balanceOf(String currency) => walletFor(currency)?.balanceCents ?? 0;

  /// The card shown on the home screen: the first card issued that is still
  /// active, else the first live (frozen) one.
  PaymentCard? get primaryCard {
    final live = cards.where((c) => c.status != CardStatus.cancelled).toList();
    if (live.isEmpty) return null;
    final active = live.where((c) => c.status == CardStatus.active).toList();
    return (active.isNotEmpty ? active : live).first;
  }

  /// The row of cards on the home screen: Slate's cards first, then the ones
  /// added from other banks, oldest first.
  List<WalletCard> get walletCards => [
        ...cards.where((c) => c.status != CardStatus.cancelled),
        ...linkedCards,
      ];

  /// Ledger rows as people think of them: a conversion is one entry (its
  /// debit), not two.
  List<Txn> get feed => transactions.where((t) => t.kind != TxnKind.conversionIn).toList();

  /// The credit row that pairs with a conversion debit.
  Txn? conversionCredit(Txn debit) => transactions
      .where((t) => t.groupId == debit.groupId && t.kind == TxnKind.conversionIn)
      .firstOrNull;

  CardPlan? planFor(String id) => plans.where((p) => p.id == id).firstOrNull;

  double rate(String from, String to) {
    double usd(String code) =>
        currencies.where((c) => c.code == code).firstOrNull?.usdRate ?? 1;
    return usd(to) / usd(from);
  }

  // ------------------------------------------------------------------ loading

  Future<void> refresh() async {
    if (!isSignedIn) return;
    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        repository.fetchProfile(),
        repository.fetchWallets(),
        repository.fetchCards(),
        repository.fetchTransactions(),
        if (plans.isEmpty) repository.fetchPlans() else Future.value(plans),
        if (currencies.isEmpty) repository.fetchCurrencies() else Future.value(currencies),
        repository.fetchLinkedCards(),
      ]);
      profile = results[0] as Profile;
      wallets = results[1] as List<Wallet>;
      cards = results[2] as List<PaymentCard>;
      transactions = results[3] as List<Txn>;
      plans = results[4] as List<CardPlan>;
      currencies = results[5] as List<Currency>;
      linkedCards = results[6] as List<LinkedCard>;
      loadError = null;
    } catch (e) {
      loadError = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadPlans() async {
    if (plans.isNotEmpty) return;
    plans = await repository.fetchPlans();
    notifyListeners();
  }

  // ------------------------------------------------------------------ auth

  Future<void> signIn(String email, String password) async {
    await repository.signIn(email: email, password: password);
    await refresh();
  }

  /// Returns true when the person has to confirm their email before signing in.
  Future<bool> signUp(String name, String email, String password) async {
    final needsConfirmation =
        await repository.signUp(name: name, email: email, password: password);
    if (!needsConfirmation) await refresh();
    return needsConfirmation;
  }

  Future<void> signInWith(SocialProvider provider) async {
    await repository.signInWith(provider);
    if (isSignedIn) await refresh();
  }

  Future<void> sendPasswordReset(String email) => repository.sendPasswordReset(email);

  Future<void> updatePassword(String password) async {
    await repository.updatePassword(password);
    pendingPasswordRecovery = false;
    notifyListeners();
  }

  void dismissPasswordRecovery() {
    pendingPasswordRecovery = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await repository.signOut();
    _clear();
  }

  // ------------------------------------------------------------------ money

  Future<T> _thenRefresh<T>(Future<T> action) async {
    final result = await action;
    await refresh();
    return result;
  }

  Future<Txn> topUp(int cents, {String currency = 'USD', required String requestId}) =>
      _thenRefresh(repository.topUp(cents: cents, currency: currency, requestId: requestId));

  Future<String?> lookupRecipient(String email) => repository.lookupRecipient(email);

  Future<Txn> transfer(String email, int cents,
          {String currency = 'USD', String? note, required String requestId}) =>
      _thenRefresh(repository.transfer(
        email: email,
        cents: cents,
        currency: currency,
        note: note,
        requestId: requestId,
      ));

  Future<Txn> convert(String from, String to, int cents, {required String requestId}) =>
      _thenRefresh(repository.convert(from: from, to: to, cents: cents, requestId: requestId));

  Future<PaymentCard> orderCard(String planId, {required String requestId}) =>
      _thenRefresh(repository.orderCard(planId: planId, requestId: requestId));

  Future<PaymentCard> setCardFrozen(PaymentCard card, bool frozen) async {
    final updated = await repository.setCardFrozen(cardId: card.id, frozen: frozen);
    cards = [for (final c in cards) c.id == updated.id ? updated : c];
    notifyListeners();
    return updated;
  }

  Future<LinkedCard> addLinkedCard(NewLinkedCard card) async {
    final added = await repository.addLinkedCard(card);
    linkedCards = [...linkedCards, added];
    notifyListeners();
    return added;
  }

  Future<void> removeLinkedCard(LinkedCard card) async {
    await repository.removeLinkedCard(card.id);
    linkedCards = [for (final c in linkedCards) if (c.id != card.id) c];
    notifyListeners();
  }

  Future<void> updateName(String name) async {
    await repository.updateName(name);
    profile = profile?.copyWith(fullName: name.trim());
    notifyListeners();
  }

  /// Fresh idempotency key for one attempt at a payment.
  String requestId() => newRequestId();

  @override
  void dispose() {
    _signals.cancel();
    super.dispose();
  }
}

/// Makes the [AppState] available below it and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// Reads the state and rebuilds the caller when it changes.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Reads the state without subscribing, for callbacks.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
