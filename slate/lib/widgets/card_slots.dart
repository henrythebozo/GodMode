import 'package:flutter/widgets.dart';

/// What the app writes onto a card picture.
enum SlotField { name, last4, memberSince, issuer, product, number, expiry, network }

/// Where one detail goes on a card picture: a box of blank card surface in
/// the 392 x 247 design units of [CardArt], measured off the picture itself.
class TextSlot {
  const TextSlot(
    this.field,
    this.left,
    this.top,
    this.width,
    this.height, {
    required this.size,
    this.align = TextAlign.left,
    this.weight = FontWeight.w500,
  });

  final SlotField field;
  final double left;
  final double top;
  final double width;
  final double height;

  /// Font size (for [SlotField.network], the height of the mark).
  final double size;
  final TextAlign align;
  final FontWeight weight;

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  Alignment get alignment => switch (align) {
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      };
}

// Most backs print the number, expiry and name in the blank band under the
// signature panel and fine print, lined up with the panel's left edge.
List<TextSlot> _backBand(double top, {required double left}) => [
      TextSlot(SlotField.number, left, top, 270, 19, size: 15),
      TextSlot(SlotField.expiry, left, top + 25, 120, 14, size: 12),
      TextSlot(SlotField.name, left, top + 48, 240, 15, size: 12),
    ];

// Amex fronts: last four just right of the contactless mark, the year under
// the MEMBER SINCE ribbon, the name along the bottom inside the border.
List<TextSlot> _amexFront({double contactlessTop = 124, double ribbonBottom = 180, double nameTop = 204}) => [
      TextSlot(SlotField.last4, 324, contactlessTop, 46, 18, size: 13, weight: FontWeight.w600),
      TextSlot(SlotField.memberSince, 262, ribbonBottom + 2, 60, 14, size: 11, align: TextAlign.center, weight: FontWeight.w600),
      TextSlot(SlotField.name, 30, nameTop, 220, 16, size: 13),
    ];

// Slate's own cards: the name at the bottom left, as in the reference design.
const _slateFront = [TextSlot(SlotField.name, 24, 196, 200, 17, size: 13, weight: FontWeight.w600)];

// Blank cards in a chosen colour, for cards the member describes themselves.
// Every one has its chip at about (43, 82) and contactless top right.
const _customFront = [
  TextSlot(SlotField.issuer, 22, 20, 300, 17, size: 13, weight: FontWeight.w700),
  TextSlot(SlotField.product, 22, 40, 300, 14, size: 10.5),
  TextSlot(SlotField.number, 22, 140, 280, 20, size: 16),
  TextSlot(SlotField.name, 22, 200, 230, 16, size: 12.5),
  TextSlot(SlotField.network, 270, 188, 102, 38, size: 26, align: TextAlign.right),
];

/// Slots per picture, by its name in `assets/cards/`. Pictures not listed
/// (Chase, Capital One and Discover fronts) carry no personal text, like the
/// real cards.
final cardSlots = <String, List<TextSlot>>{
  'slate_platinum': _slateFront,
  'slate_silver': _slateFront,
  'slate_gold': _slateFront,
  'slate_platinum_back': _backBand(136, left: 17),
  'slate_silver_back': _backBand(142, left: 17.5),
  'slate_gold_back': _backBand(140, left: 17),
  'amex_centurion': _amexFront(contactlessTop: 121),
  'amex_centurion_back': [
    const TextSlot(SlotField.number, 18, 172, 270, 17, size: 14),
    const TextSlot(SlotField.expiry, 18, 193, 120, 13, size: 11),
    const TextSlot(SlotField.name, 18, 211, 240, 14, size: 12),
  ],
  'amex_platinum': _amexFront(),
  'amex_platinum_back': _backBand(138, left: 16),
  'amex_gold': _amexFront(contactlessTop: 134, ribbonBottom: 193, nameTop: 209),
  'amex_gold_back': _backBand(150, left: 17),
  'chase_sapphire_reserve_back': _backBand(124, left: 13),
  'capital_one_venture_x_back': _backBand(124, left: 14.5),
  'citi_strata_premier': const [TextSlot(SlotField.name, 18, 214, 200, 14, size: 12)],
  'citi_strata_premier_back': _backBand(136, left: 17.5),
  'discover_it_back': _backBand(138, left: 19),
  for (final color in const ['black', 'silver', 'gold', 'blue', 'green', 'rose']) 'custom_$color': _customFront,
  'custom_black_back': _backBand(136, left: 15),
  'custom_silver_back': _backBand(136, left: 16),
  'custom_gold_back': _backBand(138, left: 18),
  'custom_blue_back': _backBand(138, left: 11),
  'custom_green_back': _backBand(136, left: 15.5),
  'custom_rose_back': _backBand(136, left: 15.5),
};
