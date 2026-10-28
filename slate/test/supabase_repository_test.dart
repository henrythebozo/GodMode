@Tags(['integration'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:slate/data/models.dart';
import 'package:slate/data/slate_repository.dart';
import 'package:slate/data/supabase_repository.dart';
import 'package:slate/utils/format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The real repository against a local Supabase stack with the seed data:
///
///   supabase start && supabase db reset
///   SUPABASE_TEST_URL=http://127.0.0.1:54321 \
///   SUPABASE_TEST_KEY=(the publishable key `supabase status` prints) \
///   flutter test test/supabase_repository_test.dart
///
/// Skipped when those variables are not set. Assertions use balance changes,
/// so the tests can run repeatedly without a reset.
void main() {
  final url = Platform.environment['SUPABASE_TEST_URL'];
  final key = Platform.environment['SUPABASE_TEST_KEY'];
  final skip = url == null || key == null ? 'SUPABASE_TEST_URL / SUPABASE_TEST_KEY not set' : null;

  // flutter_test answers every HTTP request with a 400 unless this is cleared.
  setUpAll(() => HttpOverrides.global = null);

  // The app gets session storage (needed for the PKCE flow) from
  // supabase_flutter; a bare test client uses the implicit flow instead.
  SupabaseRepository connect() => SupabaseRepository(
        SupabaseClient(
          url!,
          key!,
          authOptions: const AuthClientOptions(
            autoRefreshToken: false,
            authFlowType: AuthFlowType.implicit,
          ),
        ),
      );

  Future<SupabaseRepository> signedIn(String email) async {
    final repo = connect();
    await repo.signIn(email: email, password: 'slate1234');
    return repo;
  }

  Future<int> usd(SlateRepository repo) async =>
      (await repo.fetchWallets()).firstWhere((w) => w.currency == 'USD').balanceCents;

  Matcher fails(String message, [String? code]) => throwsA(isA<SlateException>()
      .having((e) => e.message, 'message', message)
      .having((e) => e.code, 'code', code ?? anything));

  test('wrong password is a friendly error', () async {
    await expectLater(() => connect().signIn(email: 'demo@slate.app', password: 'nope-nope'),
        fails("That email and password don't match.", 'invalid_credentials'));
  }, skip: skip);

  test('reads the seeded account in display order', () async {
    final alex = await signedIn('demo@slate.app');
    expect((await alex.fetchProfile()).fullName, 'Alex Carter');
    expect((await alex.fetchPlans()).map((p) => p.id), ['platinum', 'silver', 'gold']);
    expect((await alex.fetchCurrencies()).map((c) => c.code), ['USD', 'EUR', 'GBP']);
    expect((await alex.fetchCards()).first.planId, 'platinum');
    final txns = await alex.fetchTransactions();
    for (var i = 1; i < txns.length; i++) {
      expect(txns[i - 1].createdAt.isBefore(txns[i].createdAt), isFalse, reason: 'newest first');
    }
    await alex.signOut();
  }, skip: skip);

  test('transfer is applied once per request id and reaches the recipient', () async {
    final alex = await signedIn('demo@slate.app');
    final jamie = await signedIn('jamie@slate.app');
    final alexBefore = await usd(alex);
    final jamieBefore = await usd(jamie);
    final id = newRequestId();

    final first = await alex.transfer(email: 'jamie@slate.app', cents: 137, currency: 'USD', note: 'test', requestId: id);
    final retry = await alex.transfer(email: 'jamie@slate.app', cents: 137, currency: 'USD', note: 'test', requestId: id);
    expect(retry.id, first.id);
    expect(await usd(alex), alexBefore - 137);
    expect(await usd(jamie), jamieBefore + 137);

    final received = (await jamie.fetchTransactions()).firstWhere((t) => t.groupId == first.groupId);
    expect(received.kind, TxnKind.transferIn);
    expect(received.counterpartyName, 'Alex Carter');
    await alex.signOut();
    await jamie.signOut();
  }, skip: skip);

  test('money rules come back as readable errors', () async {
    final alex = await signedIn('demo@slate.app');
    await expectLater(() => alex.transfer(email: 'jamie@slate.app', cents: 99999999, currency: 'USD', requestId: newRequestId()),
        fails('Insufficient funds.', 'insufficient_funds'));
    await expectLater(() => alex.transfer(email: 'demo@slate.app', cents: 100, currency: 'USD', requestId: newRequestId()),
        fails("You can't send money to yourself.", 'self_transfer'));
    await expectLater(() => alex.transfer(email: 'nobody@example.com', cents: 100, currency: 'USD', requestId: newRequestId()),
        fails('No Slate account uses that email.', 'recipient_not_found'));
    await expectLater(() => alex.orderCard(planId: 'platinum', requestId: newRequestId()),
        fails('You already have a Platinum card.', 'card_exists'));
    expect(await alex.lookupRecipient('JAMIE@slate.app'), 'Jamie Rivera');
    expect(await alex.lookupRecipient('demo@slate.app'), isNull);
    await alex.signOut();
  }, skip: skip);

  test('a new member starts empty, isolated, and can top up and order a card', () async {
    final repo = connect();
    final email = 'it-${Random().nextInt(1 << 31)}@example.com';
    final needsConfirmation = await repo.signUp(name: 'Ivy Test', email: email, password: 'slate1234');
    expect(needsConfirmation, isFalse, reason: 'local config has email confirmations off');

    expect((await repo.fetchProfile()).fullName, 'Ivy Test');
    expect(await usd(repo), 0);
    expect(await repo.fetchCards(), isEmpty);
    expect(await repo.fetchLinkedCards(), isEmpty, reason: 'live accounts start with no cards');
    expect(await repo.fetchTransactions(), isEmpty, reason: 'row level security hides other members');

    final linked = await repo.addLinkedCard(const NewLinkedCard(
      designId: 'amex_platinum',
      issuer: 'American Express',
      product: 'Platinum',
      network: CardNetwork.amex,
      last4: '2003',
      holderName: 'Ivy Test',
    ));
    expect((await repo.fetchLinkedCards()).single.id, linked.id);
    await expectLater(
      () => repo.addLinkedCard(const NewLinkedCard(
        designId: 'amex_platinum',
        issuer: 'American Express',
        product: 'Platinum',
        network: CardNetwork.amex,
        last4: '2003',
        holderName: 'Ivy Test',
      )),
      fails("You've already added this card.", 'card_exists'),
    );
    await repo.removeLinkedCard(linked.id);
    expect(await repo.fetchLinkedCards(), isEmpty);
    await expectLater(() => repo.orderCard(planId: 'silver', requestId: newRequestId()), fails('Insufficient funds.'));

    await repo.topUp(cents: 10000, currency: 'USD', requestId: newRequestId());
    final card = await repo.orderCard(planId: 'silver', requestId: newRequestId());
    expect(card.holderName, 'Ivy Test');
    expect(await usd(repo), 100);
    final frozen = await repo.setCardFrozen(cardId: card.id, frozen: true);
    expect(frozen.status, CardStatus.frozen);

    final out = await repo.convert(from: 'USD', to: 'EUR', cents: 100, requestId: newRequestId());
    expect(out.kind, TxnKind.conversionOut);
    final eur = (await repo.fetchWallets()).firstWhere((w) => w.currency == 'EUR');
    expect(eur.balanceCents, 92);
    await repo.signOut();
  }, skip: skip);
}
