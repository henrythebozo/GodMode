import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/transaction_tile.dart';

/// Every transaction, grouped by day, with search ("See all" and the
/// magnifier on the home header).
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.autofocusSearch = false});

  final bool autofocusSearch;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(Txn t, String q) {
    if (q.isEmpty) return true;
    final haystack = [
      t.title,
      t.description,
      t.counterpartyName ?? '',
      t.currency,
      formatMoney(t.amountCents, t.currency),
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.text.trim().toLowerCase();
    final rows = state.feed.where((t) => _matches(t, q)).toList();
    final groups = <String, List<Txn>>{};
    for (final t in rows) {
      groups.putIfAbsent(formatDay(t.createdAt), () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Iconsax.arrow_left_2_copy, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Transactions', style: SlateText.title),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: TextField(
              controller: _query,
              autofocus: widget.autofocusSearch,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: SlateText.small,
              decoration: InputDecoration(
                hintText: 'Search transactions',
                prefixIcon: const Icon(Iconsax.search_normal_1_copy, size: 18, color: SlateColors.muted),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Iconsax.close_circle_copy, size: 18, color: SlateColors.muted),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      q.isEmpty ? 'No transactions yet.' : 'Nothing matches "$q".',
                      style: SlateText.caption.copyWith(fontSize: 13),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: state.refresh,
                    color: SlateColors.ink,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.paddingOf(context).bottom + 24),
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 2),
                            child: Text(
                              entry.key,
                              style: SlateText.caption.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          for (final t in entry.value)
                            TransactionTile(txn: t, onTap: () => showTransactionSheet(context, t)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Receipt for one transaction.
Future<void> showTransactionSheet(BuildContext context, Txn txn) {
  final state = AppScope.read(context);
  final credit = txn.kind == TxnKind.conversionOut ? state.conversionCredit(txn) : null;
  final rows = <(String, String)>[
    ('Status', 'Completed'),
    ('Date', formatDateTime(txn.createdAt)),
    if (txn.kind == TxnKind.transferOut) ('To', txn.counterpartyName ?? 'Slate member'),
    if (txn.kind == TxnKind.transferIn) ('From', txn.counterpartyName ?? 'Slate member'),
    if (credit != null) ('You received', formatMoney(credit.amountCents, credit.currency)),
    if (txn.description.isNotEmpty &&
        txn.kind != TxnKind.conversionOut &&
        txn.kind != TxnKind.topUp)
      ('Note', txn.description),
    if (txn.kind == TxnKind.conversionOut) ('Exchange', txn.description),
    ('Balance after', formatMoney(txn.balanceAfterCents, txn.currency)),
    ('Reference', txn.id.length > 8 ? txn.id.substring(0, 8).toUpperCase() : txn.id.toUpperCase()),
  ];
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: SlateColors.field, shape: BoxShape.circle),
              child: Center(child: TxnIcon(kind: txn.kind, size: 24)),
            ),
            const SizedBox(height: 14),
            Text(txn.title, style: SlateText.title),
            const SizedBox(height: 6),
            Text(
              formatMoney(txn.amountCents, txn.currency, signed: txn.isCredit),
              style: SlateText.balance.copyWith(
                color: txn.isCredit ? SlateColors.positive : SlateColors.text,
                fontSize: 34,
              ),
            ),
            const SizedBox(height: 20),
            for (final (i, (label, value)) in rows.indexed) ...[
              if (i > 0) const Hairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  children: [
                    Text(label, style: SlateText.caption.copyWith(fontSize: 13)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(value, textAlign: TextAlign.right, style: SlateText.small),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
