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
}

enum CardStatus { active, frozen, cancelled }

enum CardNetwork { visa, mastercard, amex, discover }

CardNetwork networkFrom(String value) =>
    CardNetwork.values.firstWhere((n) => n.name == value.trim(), orElse: () => CardNetwork.visa);

/// Anything that shows up in the member's row of cards: cards Slate issued
/// ([PaymentCard]) and cards they added from other banks ([LinkedCard]).
sealed class WalletCard {
  String get id;
  String get designId;
  String get issuer;
  String get product;
  CardNetwork get network;
  String get last4;
  String get holderName;
  DateTime get createdAt;
}

/// A card the member holds at another bank, kept for display. Slate only knows
/// the last four digits and can't charge it.
class LinkedCard implements WalletCard {
  const LinkedCard({
    required this.id,
    required this.designId,
    required this.issuer,
    required this.product,
    required this.network,
    required this.last4,
    required this.holderName,
    required this.createdAt,
    this.nickname,
  });

  factory LinkedCard.fromJson(Map<String, dynamic> json) => LinkedCard(
        id: json['id'] as String,
        designId: json['design'] as String,
        issuer: json['issuer'] as String,
        product: json['product'] as String,
        network: networkFrom(json['network'] as String),
        last4: (json['last4'] as String).trim(),
        holderName: json['holder_name'] as String,
        nickname: json['nickname'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  final String id;
  @override
  final String designId;
  @override
  final String issuer;
  @override
  final String product;
  @override
  final CardNetwork network;
  @override
  final String last4;
  @override
  final String holderName;
  @override
  final DateTime createdAt;
  final String? nickname;
}

/// What someone fills in on the "Add a card" screen.
class NewLinkedCard {
  const NewLinkedCard({
    required this.designId,
    required this.issuer,
    required this.product,
    required this.network,
    required this.last4,
    required this.holderName,
    this.nickname,
  });

  final String designId;
  final String issuer;
  final String product;
  final CardNetwork network;
  final String last4;
  final String holderName;
  final String? nickname;
}

/// A card Slate issued on one of its plans.
class PaymentCard implements WalletCard {
  const PaymentCard({
    required this.id,
    required this.planId,
    required this.holderName,
    required this.last4,
    required this.expiryMonth,
    required this.expiryYear,
    required this.status,
    required this.createdAt,
    this.networkName = 'visa',
  });

  factory PaymentCard.fromJson(Map<String, dynamic> json) => PaymentCard(
        id: json['id'] as String,
        planId: json['plan_id'] as String,
        holderName: json['holder_name'] as String,
        last4: (json['last4'] as String).trim(),
        networkName: json['network'] as String? ?? 'visa',
        expiryMonth: (json['expiry_month'] as num).toInt(),
        expiryYear: (json['expiry_year'] as num).toInt(),
        status: CardStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  @override
  final String id;
  final String planId;
  @override
  final String holderName;
  @override
  final String last4;
  final String networkName;
  final int expiryMonth;
  final int expiryYear;
  final CardStatus status;
  @override
  final DateTime createdAt;

  @override
  String get designId => 'slate_$planId';
  @override
  String get issuer => 'Slate';
  @override
  String get product => planId.isEmpty ? 'Card' : planId[0].toUpperCase() + planId.substring(1);
  @override
  CardNetwork get network => networkFrom(networkName);

  bool get isFrozen => status == CardStatus.frozen;
  String get expiry =>
      '${expiryMonth.toString().padLeft(2, '0')}/${(expiryYear % 100).toString().padLeft(2, '0')}';

  PaymentCard withStatus(CardStatus status) => PaymentCard(
        id: id,
        planId: planId,
        holderName: holderName,
        last4: last4,
        networkName: networkName,
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
