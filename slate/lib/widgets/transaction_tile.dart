import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';

/// Arrow glyph for a ledger row: a thin Iconsax arrow, tilted for transfers.
class TxnIcon extends StatelessWidget {
  const TxnIcon({super.key, required this.kind, this.size = 20, this.color = SlateColors.text});

  final TxnKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      TxnKind.transferOut => Transform.rotate(
          angle: math.pi / 4,
          child: Icon(Iconsax.arrow_up_3_copy, size: size, color: color),
        ),
      TxnKind.transferIn => Transform.rotate(
          angle: math.pi * 1.25,
          child: Icon(Iconsax.arrow_up_3_copy, size: size, color: color),
        ),
      TxnKind.topUp => Icon(Iconsax.add_copy, size: size, color: color),
      TxnKind.conversionIn ||
      TxnKind.conversionOut =>
        Icon(Iconsax.arrow_swap_horizontal_copy, size: size, color: color),
      TxnKind.cardFee => Icon(Iconsax.card_copy, size: size * 0.95, color: color),
    };
  }
}

/// One row of "Recent transactions": icon, title over time, amount.
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.txn, this.onTap, this.showDate = false});

  final Txn txn;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final amount = formatMoney(txn.amountCents, txn.currency, signed: txn.isCredit);
    final subtitle = showDate ? formatDateTime(txn.createdAt) : formatTime(txn.createdAt);
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      haptic: false,
      semanticLabel: '${txn.title}, $amount, $subtitle',
      child: ConstrainedBox(
        // 73pt rows as in the reference; taller when text is enlarged.
        constraints: const BoxConstraints(minHeight: 73),
        child: Row(
          children: [
            SizedBox(width: 44, child: Center(child: TxnIcon(kind: txn.kind))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(txn.title, style: SlateText.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(subtitle, style: SlateText.caption.copyWith(fontSize: 11.5)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              amount,
              style: SlateText.body.copyWith(
                color: txn.isCredit ? SlateColors.positive : SlateColors.text,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
