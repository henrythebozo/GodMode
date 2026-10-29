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

  /// Fine wavy lines across the whole face, as engraved on Amex metal cards.
  engraved,
}

/// Which layout a face follows. Each known card is laid out like the real
/// one; anything else uses [generic].
enum CardStyle { slate, amex, chaseSapphire, ventureX, citiStrata, discoverIt, generic }

enum ChipFinish { gold, silver }

/// One card face the app can draw: laid out and coloured like the real card,
/// with the issuer's marks drawn by the app rather than copied from them.
class CardDesign {
  const CardDesign({
    required this.id,
    required this.issuer,
    required this.product,
    required this.network,
    required this.material,
    this.style = CardStyle.generic,
    this.chip = true,
    this.chipFinish = ChipFinish.gold,
    this.showIssuer = true,
    this.pattern = CardPattern.none,
    this.networkTier,
    this.nickname,
  });

  final String id;
  final String issuer;
  final String product;
  final CardNetwork network;
  final CardMaterial material;
  final CardStyle style;

  /// Bank cards have an EMV chip; Slate's own cards are chipless, as in the
  /// reference design.
  final bool chip;
  final ChipFinish chipFinish;
  final bool showIssuer;
  final CardPattern pattern;

  /// Printed under the network mark on the back ("Infinite" on Visa Infinite cards).
  final String? networkTier;

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
    style: CardStyle.slate,
    chip: false,
    showIssuer: false,
  );
  static const slateSilver = CardDesign(
    id: 'slate_silver',
    issuer: 'Slate',
    product: 'Silver',
    network: CardNetwork.visa,
    material: CardMaterial.silver,
    style: CardStyle.slate,
    chip: false,
    showIssuer: false,
  );
  static const slateGold = CardDesign(
    id: 'slate_gold',
    issuer: 'Slate',
    product: 'Gold',
    network: CardNetwork.visa,
    material: CardMaterial.gold,
    style: CardStyle.slate,
    chip: false,
    showIssuer: false,
  );

  // Colours sampled from each issuer's own card art.
  static const amexCenturion = CardDesign(
    id: 'amex_centurion',
    issuer: 'American Express',
    product: 'Centurion',
    network: CardNetwork.amex,
    style: CardStyle.amex,
    chipFinish: ChipFinish.silver,
    nickname: 'The Black Card',
    pattern: CardPattern.engraved,
    material: CardMaterial(
      gradient: [Color(0xFF2C2C2D), Color(0xFF1B1B1C), Color(0xFF111112)],
      ink: Color(0xFFC4C4C4), // the engraving is bare titanium
      label: Color(0xFF8E8E8E),
      brush: 0.35,
      sheen: 0.06,
    ),
  );
  static const amexPlatinum = CardDesign(
    id: 'amex_platinum',
    issuer: 'American Express',
    product: 'Platinum',
    network: CardNetwork.amex,
    style: CardStyle.amex,
    chipFinish: ChipFinish.silver,
    pattern: CardPattern.engraved,
    material: CardMaterial(
      gradient: [Color(0xFFF0F0EE), Color(0xFFDADBD9), Color(0xFFC3C4C2)],
      ink: Color(0xFF161616),
      label: Color(0xFF4D4D4D),
      brush: 1,
      sheen: 0.12,
    ),
  );
  static const amexGold = CardDesign(
    id: 'amex_gold',
    issuer: 'American Express',
    product: 'Gold',
    network: CardNetwork.amex,
    style: CardStyle.amex,
    pattern: CardPattern.engraved,
    material: CardMaterial(
      gradient: [Color(0xFFEBDAA5), Color(0xFFDCC386), Color(0xFFC8AA63)],
      ink: Color(0xFF1C160B),
      label: Color(0xFF5E4C26),
      brush: 0.9,
    ),
  );
  static const chaseSapphireReserve = CardDesign(
    id: 'chase_sapphire_reserve',
    issuer: 'Chase',
    product: 'Sapphire Reserve',
    network: CardNetwork.visa,
    style: CardStyle.chaseSapphire,
    chipFinish: ChipFinish.silver,
    networkTier: 'Infinite',
    material: CardMaterial(
      gradient: [Color(0xFF101C3E), Color(0xFF0A1229), Color(0xFF05091A)],
      ink: Color(0xFFF2F3F6),
      label: Color(0xFFB4BBCE),
      brush: 0,
      sheen: 0.03,
    ),
  );
  static const ventureX = CardDesign(
    id: 'capital_one_venture_x',
    issuer: 'Capital One',
    product: 'Venture X',
    network: CardNetwork.visa,
    style: CardStyle.ventureX,
    chipFinish: ChipFinish.silver,
    networkTier: 'Infinite',
    material: CardMaterial(
      gradient: [Color(0xFF1E5078), Color(0xFF164064), Color(0xFF0F2E4B)],
      ink: Color(0xFFE8ECF1),
      label: Color(0xFFC0C8D3),
      brush: 0.12,
      sheen: 0.08,
    ),
  );
  static const citiStrataPremier = CardDesign(
    id: 'citi_strata_premier',
    issuer: 'Citi',
    product: 'Strata Premier',
    network: CardNetwork.mastercard,
    style: CardStyle.citiStrata,
    chipFinish: ChipFinish.silver,
    material: CardMaterial(
      gradient: [Color(0xFF6B6D71), Color(0xFF47494D), Color(0xFF2D2F33)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFD0D2D6),
      brush: 0.3,
      sheen: 0.08,
    ),
  );
  static const discoverIt = CardDesign(
    id: 'discover_it',
    issuer: 'Discover',
    product: 'it',
    network: CardNetwork.discover,
    style: CardStyle.discoverIt,
    chipFinish: ChipFinish.silver,
    material: CardMaterial(
      gradient: [Color(0xFF6CAAB3), Color(0xFF4C8B95), Color(0xFF326C76)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFDCEBEE),
      brush: 1.4,
      sheen: 0.1,
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
