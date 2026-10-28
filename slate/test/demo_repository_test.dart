import 'package:flutter_test/flutter_test.dart';
import 'package:slate/data/demo_repository.dart';
import 'package:slate/data/models.dart';
import 'package:slate/data/slate_repository.dart';

/// The demo backend must follow the same rules as the SQL functions, so the
/// app behaves the same before and after Supabase is connected.
void main() {
  late DemoRepository repo;

  setUp(() async {
    repo = DemoRepository(latency: Duration.zero, now: DateTime(2026, 10, 28, 9));
    await repo.signIn(email: 'alex@slate.app', password: 'slate1234');
  });

  Future<int> usd() async =>
      (await repo.fetchWallets()).firstWhere((w) => w.currency == 'USD').balanceCents;

  Matcher fails(String message) =>
      throwsA(isA<SlateException>().having((e) => e.message, 'message', message));

  test('starts with the account from the screenshots', () async {
    expect(await usd(), 2200000);
    final feed = (await repo.fetchTransactions()).where((t) => t.kind != TxnKind.conversionIn);
    expect(feed.take(6).map((t) => (t.title, t.amountCents)), [
      ('Transfer', 105000),
      ('Top up', 240000),
      ('Conversion', 95000),
      ('Transfer', 105000),
      ('Top up', 120000),
      ('Conversion', 47000),
    ]);
    expect((await repo.fetchCards()).single.planId, 'platinum');
  });

  test('ledger rows add up to the balances', () async {
    for (final wallet in await repo.fetchWallets()) {
      final rows = (await repo.fetchTransactions()).where((t) => t.currency == wallet.currency);
      final sum = rows.fold<int>(0, (s, t) => s + (t.isCredit ? t.amountCents : -t.amountCents));
      expect(sum, wallet.balanceCents, reason: wallet.currency);
    }
  });

  test('sign in is required', () async {
    await repo.signOut();
    expect(repo.fetchWallets, fails('You need to be signed in.'));
  });

  test('validates credentials like the auth server', () async {
    final fresh = DemoRepository(latency: Duration.zero);
    expect(() => fresh.signIn(email: 'nope', password: 'slate1234'), fails('Enter a valid email address.'));
    expect(() => fresh.signIn(email: 'a@b.co', password: '123'),
        fails('Password should be at least 6 characters.'));
  });

  group('transfer', () {
    test('moves money and records the recipient', () async {
      final txn = await repo.transfer(
          email: 'jamie@slate.app', cents: 12500, currency: 'USD', note: 'Lunch', requestId: 'r1');
      expect(txn.kind, TxnKind.transferOut);
      expect(txn.counterpartyName, 'Jamie Rivera');
      expect(txn.balanceAfterCents, 2187500);
      expect(await usd(), 2187500);
    });

    test('is applied once per request id', () async {
      await repo.transfer(email: 'jamie@slate.app', cents: 1000, currency: 'USD', requestId: 'same');
      await repo.transfer(email: 'jamie@slate.app', cents: 1000, currency: 'USD', requestId: 'same');
      expect(await usd(), 2199000);
    });

    test('refuses what the SQL refuses', () async {
      expect(() => repo.transfer(email: 'jamie@slate.app', cents: 2200001, currency: 'USD', requestId: 'a'),
          fails('Insufficient funds.'));
      expect(() => repo.transfer(email: 'ALEX@slate.app', cents: 100, currency: 'USD', requestId: 'b'),
          fails("You can't send money to yourself."));
      expect(() => repo.transfer(email: 'who@slate.app', cents: 100, currency: 'USD', requestId: 'c'),
          fails('No Slate account uses that email.'));
      expect(() => repo.transfer(email: 'jamie@slate.app', cents: 0, currency: 'USD', requestId: 'd'),
          fails('Enter an amount greater than zero.'));
      expect(() => repo.transfer(email: 'jamie@slate.app', cents: 100, currency: 'XYZ', requestId: 'e'),
          fails("That currency isn't supported."));
      expect(await usd(), 2200000);
    });

    test('recipient lookup', () async {
      expect(await repo.lookupRecipient(' Jamie@Slate.app '), 'Jamie Rivera');
      expect(await repo.lookupRecipient('alex@slate.app'), isNull);
      expect(await repo.lookupRecipient('nobody@slate.app'), isNull);
    });
  });

  test('top-ups are limited per payment', () async {
    expect(() => repo.topUp(cents: 2500001, currency: 'USD', requestId: 't'),
        fails('That amount is over the limit for one payment.'));
    await repo.topUp(cents: 50000, currency: 'USD', requestId: 't2');
    expect(await usd(), 2250000);
  });

  test('conversion uses the demo rates and opens wallets as needed', () async {
    final out = await repo.convert(from: 'USD', to: 'GBP', cents: 10000, requestId: 'x');
    final wallets = {for (final w in await repo.fetchWallets()) w.currency: w.balanceCents};
    expect(wallets['USD'], 2190000);
    expect(wallets['GBP'], 7900);
    final legs = (await repo.fetchTransactions()).where((t) => t.groupId == out.groupId);
    expect(legs.map((t) => t.kind), unorderedEquals([TxnKind.conversionOut, TxnKind.conversionIn]));
    expect(() => repo.convert(from: 'USD', to: 'usd', cents: 100, requestId: 'y'),
        fails('Pick two different currencies.'));
    expect(() => repo.convert(from: 'USD', to: 'EUR', cents: 1, requestId: 'z'),
        fails('That amount is too small to convert.'));
  });

  group('cards', () {
    test('ordering charges the annual fee once', () async {
      final card = await repo.orderCard(planId: 'Silver', requestId: 'card-1');
      final again = await repo.orderCard(planId: 'silver', requestId: 'card-1');
      expect(again.id, card.id);
      expect(card.holderName, 'Alex Carter');
      expect(card.last4, matches(RegExp(r'^\d{4}$')));
      expect(await usd(), 2200000 - 9900);
      expect(() => repo.orderCard(planId: 'silver', requestId: 'card-2'),
          fails('You already have a Silver card.'));
      expect(() => repo.orderCard(planId: 'titanium', requestId: 'card-3'),
          fails("That card plan doesn't exist."));
    });

    test('freeze and unfreeze', () async {
      final card = (await repo.fetchCards()).first;
      expect((await repo.setCardFrozen(cardId: card.id, frozen: true)).status, CardStatus.frozen);
      expect((await repo.setCardFrozen(cardId: card.id, frozen: false)).status, CardStatus.active);
      expect(() => repo.setCardFrozen(cardId: 'nope', frozen: true), fails('Card not found.'));
    });
  });
}
