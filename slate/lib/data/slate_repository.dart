import 'models.dart';

/// Everything the app needs from a backend. [SupabaseRepository] talks to the
/// real one; [DemoRepository] keeps the same rules in memory so the app runs
/// with no setup.
abstract class SlateRepository {
  bool get isDemo;
  bool get isSignedIn;

  /// Fires whenever the signed-in state changes, plus [AuthSignal.passwordRecovery]
  /// when someone opens a reset-password link.
  Stream<AuthSignal> get authSignals;

  Future<void> signIn({required String email, required String password});

  /// Returns true when the account still has to be confirmed from an email
  /// (hosted Supabase projects do this by default).
  Future<bool> signUp({required String name, required String email, required String password});

  Future<void> signInWith(SocialProvider provider);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<void> signOut();

  Future<Profile> fetchProfile();
  Future<List<Wallet>> fetchWallets();
  Future<List<PaymentCard>> fetchCards();
  Future<List<Txn>> fetchTransactions({int limit = 100});
  Future<List<CardPlan>> fetchPlans();
  Future<List<Currency>> fetchCurrencies();

  Future<void> updateName(String name);
  Future<Txn> topUp({required int cents, required String currency, required String requestId});
  Future<String?> lookupRecipient(String email);
  Future<Txn> transfer({
    required String email,
    required int cents,
    required String currency,
    String? note,
    required String requestId,
  });
  Future<Txn> convert({
    required String from,
    required String to,
    required int cents,
    required String requestId,
  });
  Future<PaymentCard> orderCard({required String planId, required String requestId});
  Future<PaymentCard> setCardFrozen({required String cardId, required bool frozen});

  /// Cards the member added from other banks (display only).
  Future<List<LinkedCard>> fetchLinkedCards();
  Future<LinkedCard> addLinkedCard(NewLinkedCard card);
  Future<void> removeLinkedCard(String cardId);
}

enum AuthSignal { signedIn, signedOut, passwordRecovery }

/// An error worth showing to the person as-is.
class SlateException implements Exception {
  const SlateException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
