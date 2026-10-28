import 'package:flutter/material.dart';

import '../data/models.dart';

/// Colours and finish for one card face.
class CardMaterial {
  const CardMaterial({
    required this.gradient,
    required this.ink,
    required this.label,
    required this.brush,
    this.sheen = 0.09,
  });

  final List<Color> gradient;
  final Color ink;
  final Color label;

  /// Strength of the brushed-metal hairlines, 0 to 1.
  final double brush;

  /// Strength of the soft highlight from the top-left corner.
  final double sheen;

  // Slate's own plans, sampled from the reference frames.
  static const platinum = CardMaterial(
    gradient: [Color(0xFFC5C1BC), Color(0xFFBCB8B2), Color(0xFFBAB6B0)],
    ink: Color(0xFF1E1D1B),
    label: Color(0xFF6B6763),
    brush: 1,
  );
  static const silver = CardMaterial(
    gradient: [Color(0xFFB9BCBE), Color(0xFFABAEB0), Color(0xFFA2A5A7)],
    ink: Color(0xFF1C1D1E),
    label: Color(0xFF55585B),
    brush: 0.45,
  );
  static const gold = CardMaterial(
    gradient: [Color(0xFFDDD0B4), Color(0xFFD2C3A7), Color(0xFFC4B497)],
    ink: Color(0xFF241F16),
    label: Color(0xFF75674B),
    brush: 0.5,
  );
}

enum CardPattern {
  none,

  /// Fine concentric rings, like banknote engraving.
  guilloche,

  /// Faint diagonal pinstripes.
  pinstripe,
}

/// One card face the app can draw. Designs are stand-ins in each card's
/// colours, not copies of the issuers' artwork.
class CardDesign {
  const CardDesign({
    required this.id,
    required this.issuer,
    required this.product,
    required this.network,
    required this.material,
    this.chip = true,
    this.showIssuer = true,
    this.pattern = CardPattern.none,
    this.nickname,
  });

  final String id;
  final String issuer;
  final String product;
  final CardNetwork network;
  final CardMaterial material;

  /// Bank cards have an EMV chip; Slate's own cards are chipless, as in the
  /// reference design.
  final bool chip;
  final bool showIssuer;
  final CardPattern pattern;

  /// How people know the card ("The Black Card"), shown in the picker.
  final String? nickname;

  bool get isSlate => id.startsWith('slate_');
  String get name => '${shortIssuer(issuer)} $product';
}

/// "American Express" is "Amex" in lists; other banks keep their name.
String shortIssuer(String issuer) => issuer == 'American Express' ? 'Amex' : issuer;

abstract final class CardCatalog {
  static const slatePlatinum = CardDesign(
    id: 'slate_platinum',
    issuer: 'Slate',
    product: 'Platinum',
    network: CardNetwork.visa,
    material: CardMaterial.platinum,
    chip: false,
    showIssuer: false,
  );
  static const slateSilver = CardDesign(
    id: 'slate_silver',
    issuer: 'Slate',
    product: 'Silver',
    network: CardNetwork.visa,
    material: CardMaterial.silver,
    chip: false,
    showIssuer: false,
  );
  static const slateGold = CardDesign(
    id: 'slate_gold',
    issuer: 'Slate',
    product: 'Gold',
    network: CardNetwork.visa,
    material: CardMaterial.gold,
    chip: false,
    showIssuer: false,
  );

  static const amexCenturion = CardDesign(
    id: 'amex_centurion',
    issuer: 'American Express',
    product: 'Centurion',
    network: CardNetwork.amex,
    nickname: 'The Black Card',
    pattern: CardPattern.guilloche,
    material: CardMaterial(
      gradient: [Color(0xFF2E2E30), Color(0xFF1B1B1C), Color(0xFF0F0F10)],
      ink: Color(0xFFD9D9D9),
      label: Color(0xFF8C8C8C),
      brush: 0.35,
      sheen: 0.07,
    ),
  );
  static const amexPlatinum = CardDesign(
    id: 'amex_platinum',
    issuer: 'American Express',
    product: 'Platinum',
    network: CardNetwork.amex,
    pattern: CardPattern.guilloche,
    material: CardMaterial(
      gradient: [Color(0xFFE7E7E4), Color(0xFFCECECB), Color(0xFFB5B5B2)],
      ink: Color(0xFF242424),
      label: Color(0xFF5E5E5E),
      brush: 1,
    ),
  );
  static const amexGold = CardDesign(
    id: 'amex_gold',
    issuer: 'American Express',
    product: 'Gold',
    network: CardNetwork.amex,
    pattern: CardPattern.guilloche,
    material: CardMaterial(
      gradient: [Color(0xFFECDBA8), Color(0xFFD8BE78), Color(0xFFBD9D55)],
      ink: Color(0xFF3A2D10),
      label: Color(0xFF6F5B2D),
      brush: 0.8,
    ),
  );
  static const chaseSapphireReserve = CardDesign(
    id: 'chase_sapphire_reserve',
    issuer: 'Chase',
    product: 'Sapphire Reserve',
    network: CardNetwork.visa,
    pattern: CardPattern.pinstripe,
    material: CardMaterial(
      gradient: [Color(0xFF26467A), Color(0xFF162E52), Color(0xFF0B1A31)],
      ink: Color(0xFFEFF3F9),
      label: Color(0xFFA7B8D1),
      brush: 0.3,
      sheen: 0.12,
    ),
  );
  static const ventureX = CardDesign(
    id: 'capital_one_venture_x',
    issuer: 'Capital One',
    product: 'Venture X',
    network: CardNetwork.visa,
    pattern: CardPattern.pinstripe,
    material: CardMaterial(
      gradient: [Color(0xFF41464C), Color(0xFF282C31), Color(0xFF17191C)],
      ink: Color(0xFFF1F1F1),
      label: Color(0xFFA5AAB0),
      brush: 0.45,
    ),
  );
  static const citiStrataPremier = CardDesign(
    id: 'citi_strata_premier',
    issuer: 'Citi',
    product: 'Strata Premier',
    network: CardNetwork.mastercard,
    material: CardMaterial(
      gradient: [Color(0xFF3657B4), Color(0xFF223D8A), Color(0xFF15275D)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFB4C2E8),
      brush: 0.2,
      sheen: 0.12,
    ),
  );
  static const discoverIt = CardDesign(
    id: 'discover_it',
    issuer: 'Discover',
    product: 'it',
    network: CardNetwork.discover,
    material: CardMaterial(
      gradient: [Color(0xFFF8F6F2), Color(0xFFEBE7E0), Color(0xFFDDD7CD)],
      ink: Color(0xFF1E1E1E),
      label: Color(0xFF7B756C),
      brush: 0.25,
    ),
  );

  /// Cards someone can pick on the "Add a card" screen, in order.
  static const addable = [
    amexCenturion,
    amexPlatinum,
    amexGold,
    chaseSapphireReserve,
    ventureX,
    citiStrataPremier,
    discoverIt,
  ];

  /// Colours for a card that isn't in the list ("Other card").
  static const customColors = <String, CardMaterial>{
    'custom_black': CardMaterial(
      gradient: [Color(0xFF2A2A2C), Color(0xFF19191A), Color(0xFF0E0E0F)],
      ink: Color(0xFFE6E6E6),
      label: Color(0xFF8E8E8E),
      brush: 0.35,
    ),
    'custom_silver': CardMaterial(
      gradient: [Color(0xFFE2E3E4), Color(0xFFC9CBCD), Color(0xFFB2B4B6)],
      ink: Color(0xFF222222),
      label: Color(0xFF5D6063),
      brush: 0.9,
    ),
    'custom_gold': CardMaterial(
      gradient: [Color(0xFFE6D3A3), Color(0xFFD1B878), Color(0xFFB79A55)],
      ink: Color(0xFF34290F),
      label: Color(0xFF6B582B),
      brush: 0.7,
    ),
    'custom_blue': CardMaterial(
      gradient: [Color(0xFF2E5FA6), Color(0xFF1E4479), Color(0xFF122B4E)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFB3C6E3),
      brush: 0.2,
      sheen: 0.12,
    ),
    'custom_green': CardMaterial(
      gradient: [Color(0xFF2F6E52), Color(0xFF1F4D39), Color(0xFF133024)],
      ink: Color(0xFFF2F7F4),
      label: Color(0xFFA9C7B8),
      brush: 0.2,
      sheen: 0.12,
    ),
    'custom_rose': CardMaterial(
      gradient: [Color(0xFFEFCFCB), Color(0xFFDDB1AB), Color(0xFFC9978F)],
      ink: Color(0xFF3B2421),
      label: Color(0xFF7A5450),
      brush: 0.6,
    ),
  };

  static const _byId = {
    'slate_platinum': slatePlatinum,
    'slate_silver': slateSilver,
    'slate_gold': slateGold,
    'amex_centurion': amexCenturion,
    'amex_platinum': amexPlatinum,
    'amex_gold': amexGold,
    'chase_sapphire_reserve': chaseSapphireReserve,
    'capital_one_venture_x': ventureX,
    'citi_strata_premier': citiStrataPremier,
    'discover_it': discoverIt,
  };

  /// The design to draw for a card. Custom cards take their colour from the
  /// design id and their names from what the member typed; unknown ids fall
  /// back to black.
  static CardDesign forCard(WalletCard card) {
    final known = _byId[card.designId];
    if (known != null && (known.isSlate || known.issuer == card.issuer)) return known;
    return CardDesign(
      id: card.designId,
      issuer: card.issuer,
      product: card.product,
      network: card.network,
      material: customColors[card.designId] ?? customColors['custom_black']!,
    );
  }

  static CardDesign slatePlan(String planId) => _byId['slate_$planId'] ?? slatePlatinum;
}
