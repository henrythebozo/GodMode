/// Plain data classes mirroring the Supabase tables (see supabase/migrations).
library;

class Profile {
  const Profile({required this.id, required this.fullName, required this.email});

  final String id;
  final String fullName;
  final String email;

  Profile copyWith({String? fullName}) =>
      Profile(id: id, fullName: fullName ?? this.fullName, email: email);
}

class Wallet {
  const Wallet({required this.id, required this.currency, required this.balanceCents});

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: json['id'] as String,
        currency: (json['currency'] as String).trim(),
        balanceCents: (json['balance_cents'] as num).toInt(),
      );

  final String id;
  final String currency;
  final int balanceCents;

  Wallet withBalance(int cents) => Wallet(id: id, currency: currency, balanceCents: cents);
}

class Currency {
  const Currency({required this.code, required this.name, required this.usdRate});

  factory Currency.fromJson(Map<String, dynamic> json) => Currency(
        code: (json['code'] as String).trim(),
        name: json['name'] as String,
        usdRate: double.parse(json['usd_rate'].toString()),
      );

  final String code;
  final String name;

  /// Units of this currency per 1 USD.
  final double usdRate;
}

/// Card finishes the artwork knows how to draw. Plans with other ids fall
/// back to platinum.
enum CardFinish { platinum, silver, gold }

class CardPlan {
  const CardPlan({
    required this.id,
    required this.name,
    required this.annualFeeCents,
    required this.currency,
    required this.perks,
  });

  factory CardPlan.fromJson(Map<String, dynamic> json) => CardPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        annualFeeCents: (json['annual_fee_cents'] as num).toInt(),
        currency: (json['currency'] as String).trim(),
        perks: [for (final perk in (json['perks'] as List? ?? const [])) perk as String],
      );

  final String id;
  final String name;
  final int annualFeeCents;
  final String currency;
  final List<String> perks;

  CardFinish get finish => finishFor(id);
}

CardFinish finishFor(String planId) => switch (planId) {
      'silver' => CardFinish.silver,
      'gold' => CardFinish.gold,
      _ => CardFinish.platinum,
    };

enum CardStatus { active, frozen, cancelled }

class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.planId,
    required this.holderName,
    required this.last4,
    required this.expiryMonth,
    required this.expiryYear,
    required this.status,
    required this.createdAt,
    this.network = 'visa',
  });

  factory PaymentCard.fromJson(Map<String, dynamic> json) => PaymentCard(
        id: json['id'] as String,
        planId: json['plan_id'] as String,
        holderName: json['holder_name'] as String,
        last4: (json['last4'] as String).trim(),
        network: json['network'] as String? ?? 'visa',
        expiryMonth: (json['expiry_month'] as num).toInt(),
        expiryYear: (json['expiry_year'] as num).toInt(),
        status: CardStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String planId;
  final String holderName;
  final String last4;
  final String network;
  final int expiryMonth;
  final int expiryYear;
  final CardStatus status;
  final DateTime createdAt;

  bool get isFrozen => status == CardStatus.frozen;
  CardFinish get finish => finishFor(planId);
  String get expiry =>
      '${expiryMonth.toString().padLeft(2, '0')}/${(expiryYear % 100).toString().padLeft(2, '0')}';

  PaymentCard withStatus(CardStatus status) => PaymentCard(
        id: id,
        planId: planId,
        holderName: holderName,
        last4: last4,
        network: network,
        expiryMonth: expiryMonth,
        expiryYear: expiryYear,
        status: status,
        createdAt: createdAt,
      );
}

enum TxnKind {
  topUp('top_up'),
  transferIn('transfer_in'),
  transferOut('transfer_out'),
  conversionIn('conversion_in'),
  conversionOut('conversion_out'),
  cardFee('card_fee');

  const TxnKind(this.wire);
  final String wire;

  static TxnKind fromWire(String value) => values.firstWhere((k) => k.wire == value);
}

class Txn {
  const Txn({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.currency,
    required this.balanceAfterCents,
    required this.createdAt,
    required this.groupId,
    this.description = '',
    this.counterpartyName,
    this.cardId,
  });

  factory Txn.fromJson(Map<String, dynamic> json) => Txn(
        id: json['id'] as String,
        kind: TxnKind.fromWire(json['kind'] as String),
        amountCents: (json['amount_cents'] as num).toInt(),
        currency: (json['currency'] as String).trim(),
        balanceAfterCents: (json['balance_after_cents'] as num).toInt(),
        description: json['description'] as String? ?? '',
        counterpartyName: json['counterparty_name'] as String?,
        cardId: json['card_id'] as String?,
        groupId: json['group_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final TxnKind kind;
  final int amountCents;
  final String currency;
  final int balanceAfterCents;
  final String description;
  final String? counterpartyName;
  final String? cardId;
  final String groupId;
  final DateTime createdAt;

  bool get isCredit =>
      kind == TxnKind.topUp || kind == TxnKind.transferIn || kind == TxnKind.conversionIn;

  String get title => switch (kind) {
        TxnKind.topUp => 'Top up',
        TxnKind.transferOut => 'Transfer',
        TxnKind.transferIn => 'Received',
        TxnKind.conversionIn || TxnKind.conversionOut => 'Conversion',
        TxnKind.cardFee => 'Card fee',
      };

  /// Second line for detail views: who, or what, the money moved for.
  String get detail => switch (kind) {
        TxnKind.transferOut => 'To ${counterpartyName ?? 'a Slate member'}',
        TxnKind.transferIn => 'From ${counterpartyName ?? 'a Slate member'}',
        _ => description,
      };
}

enum SocialProvider { facebook, google, apple }
