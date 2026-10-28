import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'slate_repository.dart';

/// Talks to the Supabase project described in supabase/migrations. Reads go
/// straight to the tables (row level security limits them to the signed-in
/// member); every money movement is one RPC call.
///
/// Note that postgrest's `order()` sorts descending unless told otherwise, so
/// every sort below says which way it goes.
class SupabaseRepository implements SlateRepository {
  SupabaseRepository(this.client, {this.authRedirectUrl});

  final SupabaseClient client;

  /// Where OAuth and email links send people back to: the app's URL scheme
  /// on mobile, or null on web to use the current page.
  final String? authRedirectUrl;

  GoTrueClient get _auth => client.auth;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) throw const SlateException('You need to be signed in.');
    return user.id;
  }

  @override
  bool get isDemo => false;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  Stream<AuthSignal> get authSignals => _auth.onAuthStateChange
      .map((state) => switch (state.event) {
            AuthChangeEvent.passwordRecovery => AuthSignal.passwordRecovery,
            AuthChangeEvent.signedOut => AuthSignal.signedOut,
            _ => state.session == null ? AuthSignal.signedOut : AuthSignal.signedIn,
          })
      .handleError((Object _) {}); // bad deep links surface as errors here

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw SlateException(_authMessage(e), code: e.code);
    } on PostgrestException catch (e) {
      throw SlateException(e.message, code: e.hint ?? e.code);
    } on SlateException {
      rethrow;
    } on TimeoutException {
      throw const SlateException('Slate is taking too long to respond. Try again.');
    } catch (e) {
      final text = e.toString();
      if (text.contains('SocketException') || text.contains('ClientException')) {
        throw const SlateException("Can't reach Slate. Check your connection.");
      }
      rethrow;
    }
  }

  String _authMessage(AuthException e) => switch (e.code) {
        'invalid_credentials' => 'That email and password don\'t match.',
        'email_not_confirmed' => 'Confirm your email first. We sent you a link.',
        'user_already_exists' => 'An account with that email already exists.',
        'weak_password' => 'Pick a stronger password (at least 6 characters).',
        'over_email_send_rate_limit' => 'Too many emails sent. Try again in a minute.',
        _ => e.message,
      };

  // ------------------------------------------------------------------ auth

  @override
  Future<void> signIn({required String email, required String password}) => _guard(() async {
        await _auth.signInWithPassword(email: email.trim(), password: password);
      });

  @override
  Future<bool> signUp({required String name, required String email, required String password}) =>
      _guard(() async {
        final res = await _auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': name.trim()},
          emailRedirectTo: authRedirectUrl,
        );
        return res.session == null;
      });

  @override
  Future<void> signInWith(SocialProvider provider) => _guard(() async {
        await _auth.signInWithOAuth(
          switch (provider) {
            SocialProvider.facebook => OAuthProvider.facebook,
            SocialProvider.google => OAuthProvider.google,
            SocialProvider.apple => OAuthProvider.apple,
          },
          redirectTo: authRedirectUrl,
        );
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() async {
        await _auth.resetPasswordForEmail(email.trim(), redirectTo: authRedirectUrl);
      });

  @override
  Future<void> updatePassword(String password) => _guard(() async {
        await _auth.updateUser(UserAttributes(password: password));
      });

  @override
  Future<void> signOut() => _guard(() => _auth.signOut());

  // ------------------------------------------------------------------ reads

  @override
  Future<Profile> fetchProfile() => _guard(() async {
        final row = await client.from('profiles').select('id, full_name').eq('id', _userId).single();
        return Profile(
          id: row['id'] as String,
          fullName: row['full_name'] as String,
          email: _auth.currentUser?.email ?? '',
        );
      });

  @override
  Future<List<Wallet>> fetchWallets() => _guard(() async {
        final rows = await client.from('wallets').select().order('created_at', ascending: true);
        return rows.map(Wallet.fromJson).toList();
      });

  @override
  Future<List<PaymentCard>> fetchCards() => _guard(() async {
        final rows = await client
            .from('cards')
            .select()
            .neq('status', 'cancelled')
            .order('created_at', ascending: true);
        return rows.map(PaymentCard.fromJson).toList();
      });

  @override
  Future<List<Txn>> fetchTransactions({int limit = 100}) => _guard(() async {
        final rows = await client
            .from('transactions')
            .select()
            .order('created_at', ascending: false)
            .order('kind', ascending: false) // conversion_out before its conversion_in
            .limit(limit);
        return rows.map(Txn.fromJson).toList();
      });

  @override
  Future<List<CardPlan>> fetchPlans() => _guard(() async {
        final rows = await client.from('card_plans').select().order('sort_order', ascending: true);
        return rows.map(CardPlan.fromJson).toList();
      });

  @override
  Future<List<Currency>> fetchCurrencies() => _guard(() async {
        final rows = await client.from('currencies').select().order('sort_order', ascending: true);
        return rows.map(Currency.fromJson).toList();
      });

  // ------------------------------------------------------------------ writes

  @override
  Future<void> updateName(String name) => _guard(() async {
        final trimmed = name.trim();
        if (trimmed.isEmpty) throw const SlateException('Enter your name.');
        if (trimmed.length > 80) throw const SlateException('Keep your name under 80 characters.');
        await client.from('profiles').update({'full_name': trimmed}).eq('id', _userId);
      });

  Future<Map<String, dynamic>> _rpc(String fn, Map<String, dynamic> params) async {
    final result = await client.rpc(fn, params: params);
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Txn> topUp({required int cents, required String currency, required String requestId}) =>
      _guard(() async => Txn.fromJson(await _rpc('top_up', {
            'p_amount_cents': cents,
            'p_currency': currency,
            'p_request_id': requestId,
          })));

  @override
  Future<String?> lookupRecipient(String email) => _guard(() async {
        final result = await client.rpc('lookup_recipient', params: {'p_email': email});
        return result as String?;
      });

  @override
  Future<Txn> transfer({
    required String email,
    required int cents,
    required String currency,
    String? note,
    required String requestId,
  }) =>
      _guard(() async => Txn.fromJson(await _rpc('transfer', {
            'p_recipient_email': email,
            'p_amount_cents': cents,
            'p_currency': currency,
            'p_note': note,
            'p_request_id': requestId,
          })));

  @override
  Future<Txn> convert({
    required String from,
    required String to,
    required int cents,
    required String requestId,
  }) =>
      _guard(() async => Txn.fromJson(await _rpc('convert_currency', {
            'p_from': from,
            'p_to': to,
            'p_amount_cents': cents,
            'p_request_id': requestId,
          })));

  @override
  Future<PaymentCard> orderCard({required String planId, required String requestId}) =>
      _guard(() async => PaymentCard.fromJson(await _rpc('order_card', {
            'p_plan_id': planId,
            'p_request_id': requestId,
          })));

  @override
  Future<PaymentCard> setCardFrozen({required String cardId, required bool frozen}) =>
      _guard(() async => PaymentCard.fromJson(await _rpc('set_card_frozen', {
            'p_card_id': cardId,
            'p_frozen': frozen,
          })));

  @override
  Future<List<LinkedCard>> fetchLinkedCards() => _guard(() async {
        final rows = await client.from('linked_cards').select().order('created_at', ascending: true);
        return rows.map(LinkedCard.fromJson).toList();
      });

  @override
  Future<LinkedCard> addLinkedCard(NewLinkedCard card) =>
      _guard(() async => LinkedCard.fromJson(await _rpc('add_linked_card', {
            'p_design': card.designId,
            'p_issuer': card.issuer,
            'p_product': card.product,
            'p_network': card.network.name,
            'p_last4': card.last4,
            'p_holder_name': card.holderName,
            'p_nickname': card.nickname,
          })));

  @override
  Future<void> removeLinkedCard(String cardId) => _guard(() async {
        await client.rpc('remove_linked_card', params: {'p_card_id': cardId});
      });
}
