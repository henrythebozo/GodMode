import 'package:flutter/material.dart';

import '../data/models.dart';

/// The colours of one card: [gradient] stands in while its picture loads and
/// paints the colour swatches on the "Add a card" screen; [ink] and [label]
/// are for the details the app writes onto the picture (name, last four).
class CardMaterial {
  const CardMaterial({required this.gradient, required this.ink, required this.label});

  final List<Color> gradient;
  final Color ink;
  final Color label;

  // Slate's own plans, sampled from the reference frames.
  static const platinum = CardMaterial(
    gradient: [Color(0xFFC5C1BC), Color(0xFFBCB8B2), Color(0xFFBAB6B0)],
    ink: Color(0xFF2A2826),
    label: Color(0xFF6B6763),
  );
  static const silver = CardMaterial(
    gradient: [Color(0xFF9DA6AE), Color(0xFF8A939B), Color(0xFF7C858D)],
    ink: Color(0xFF1F2326),
    label: Color(0xFF4A5056),
  );
  static const gold = CardMaterial(
    gradient: [Color(0xFFE6D6B6), Color(0xFFD9C6A2), Color(0xFFC9B48D)],
    ink: Color(0xFF3A3022),
    label: Color(0xFF75674B),
  );
}

/// One card face the app can show. Each has a photoreal picture of the front
/// and back in `assets/cards/` (see [frontArt]); the app writes the member's
/// own details onto it.
class CardDesign {
  const CardDesign({
    required this.id,
    required this.issuer,
    required this.product,
    required this.network,
    required this.material,
    this.nickname,
  });

  final String id;
  final String issuer;
  final String product;
  final CardNetwork network;
  final CardMaterial material;

  /// How people know the card ("The Black Card"), shown in the picker.
  final String? nickname;

  bool get isSlate => id.startsWith('slate_');
  String get name => '${shortIssuer(issuer)} $product';

  /// Cards the member described themselves ("Other card") use a blank card in
  /// their chosen colour, with the bank and card name written on by the app.
  bool get isCustom => !CardCatalog._byId.containsKey(id);

  String get _art => CardCatalog.customColors.containsKey(id) || CardCatalog._byId.containsKey(id) ? id : 'custom_black';

  /// The picture's name in `assets/cards/` ("amex_gold", "amex_gold_back").
  String art({bool back = false}) => back ? '${_art}_back' : _art;
  String get frontArt => 'assets/cards/${art()}.webp';
  String get backArt => 'assets/cards/${art(back: true)}.webp';
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
  );
  static const slateSilver = CardDesign(
    id: 'slate_silver',
    issuer: 'Slate',
    product: 'Silver',
    network: CardNetwork.visa,
    material: CardMaterial.silver,
  );
  static const slateGold = CardDesign(
    id: 'slate_gold',
    issuer: 'Slate',
    product: 'Gold',
    network: CardNetwork.visa,
    material: CardMaterial.gold,
  );

  static const amexCenturion = CardDesign(
    id: 'amex_centurion',
    issuer: 'American Express',
    product: 'Centurion',
    network: CardNetwork.amex,
    nickname: 'The Black Card',
    material: CardMaterial(
      gradient: [Color(0xFF2C2C2D), Color(0xFF1B1B1C), Color(0xFF111112)],
      ink: Color(0xFFD2D2D2), // the engraving is bare titanium
      label: Color(0xFF8E8E8E),
    ),
  );
  static const amexPlatinum = CardDesign(
    id: 'amex_platinum',
    issuer: 'American Express',
    product: 'Platinum',
    network: CardNetwork.amex,
    material: CardMaterial(
      gradient: [Color(0xFFF0F0EE), Color(0xFFDADBD9), Color(0xFFC3C4C2)],
      ink: Color(0xFF1C1C1C),
      label: Color(0xFF4D4D4D),
    ),
  );
  static const amexGold = CardDesign(
    id: 'amex_gold',
    issuer: 'American Express',
    product: 'Gold',
    network: CardNetwork.amex,
    material: CardMaterial(
      gradient: [Color(0xFFEBDAA5), Color(0xFFDCC386), Color(0xFFC8AA63)],
      ink: Color(0xFF1F1910),
      label: Color(0xFF5E4C26),
    ),
  );
  static const chaseSapphireReserve = CardDesign(
    id: 'chase_sapphire_reserve',
    issuer: 'Chase',
    product: 'Sapphire Reserve',
    network: CardNetwork.visa,
    material: CardMaterial(
      gradient: [Color(0xFF101C3E), Color(0xFF0A1229), Color(0xFF05091A)],
      ink: Color(0xFFF2F3F6),
      label: Color(0xFFB4BBCE),
    ),
  );
  static const ventureX = CardDesign(
    id: 'capital_one_venture_x',
    issuer: 'Capital One',
    product: 'Venture X',
    network: CardNetwork.visa,
    material: CardMaterial(
      gradient: [Color(0xFF1E5078), Color(0xFF164064), Color(0xFF0F2E4B)],
      ink: Color(0xFFEDF0F4),
      label: Color(0xFFC0C8D3),
    ),
  );
  static const citiStrataPremier = CardDesign(
    id: 'citi_strata_premier',
    issuer: 'Citi',
    product: 'Strata Premier',
    network: CardNetwork.mastercard,
    material: CardMaterial(
      gradient: [Color(0xFF6B6D71), Color(0xFF47494D), Color(0xFF2D2F33)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFD0D2D6),
    ),
  );
  static const discoverIt = CardDesign(
    id: 'discover_it',
    issuer: 'Discover',
    product: 'it',
    network: CardNetwork.discover,
    material: CardMaterial(
      gradient: [Color(0xFF6CAAB3), Color(0xFF4C8B95), Color(0xFF326C76)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFDCEBEE),
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
      label: Color(0xFF9A9A9A),
    ),
    'custom_silver': CardMaterial(
      gradient: [Color(0xFFE2E3E4), Color(0xFFC9CBCD), Color(0xFFB2B4B6)],
      ink: Color(0xFF222222),
      label: Color(0xFF55585B),
    ),
    'custom_gold': CardMaterial(
      gradient: [Color(0xFFE6D3A3), Color(0xFFD1B878), Color(0xFFB79A55)],
      ink: Color(0xFF2F250E),
      label: Color(0xFF6B582B),
    ),
    'custom_blue': CardMaterial(
      gradient: [Color(0xFF2E5FA6), Color(0xFF1E4479), Color(0xFF122B4E)],
      ink: Color(0xFFFFFFFF),
      label: Color(0xFFB3C6E3),
    ),
    'custom_green': CardMaterial(
      gradient: [Color(0xFF2F6E52), Color(0xFF1F4D39), Color(0xFF133024)],
      ink: Color(0xFFF2F7F4),
      label: Color(0xFFA9C7B8),
    ),
    'custom_rose': CardMaterial(
      gradient: [Color(0xFFEFCFCB), Color(0xFFDDB1AB), Color(0xFFC9978F)],
      ink: Color(0xFF3B2421),
      label: Color(0xFF7A5450),
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
    final color = customColors.containsKey(card.designId) ? card.designId : 'custom_black';
    return CardDesign(
      id: color,
      issuer: card.issuer,
      product: card.product,
      network: card.network,
      material: customColors[color]!,
    );
  }

  static CardDesign slatePlan(String planId) => _byId['slate_$planId'] ?? slatePlatinum;
}
