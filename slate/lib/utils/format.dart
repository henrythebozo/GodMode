import 'dart:math';

import 'package:intl/intl.dart';

const _symbols = {'USD': r'$', 'EUR': '€', 'GBP': '£'};

String currencySymbol(String currency) => _symbols[currency] ?? '$currency ';

/// `$1,050.00`. With [whole], drops ".00" from round amounts (`$22,000`).
/// With [signed], prefixes credits with "+".
String formatMoney(
  int cents,
  String currency, {
  bool whole = false,
  bool signed = false,
}) {
  final digits = whole && cents % 100 == 0 ? 0 : 2;
  final text = NumberFormat.currency(
    locale: 'en_US',
    symbol: currencySymbol(currency),
    decimalDigits: digits,
  ).format(cents.abs() / 100);
  if (cents < 0) return '-$text';
  return signed ? '+$text' : text;
}

/// Parses what someone typed into an amount field ("1,050.5", "$20") into
/// cents. Returns null for anything that isn't a positive amount with at most
/// two decimals.
int? parseAmount(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s,$€£]'), '');
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{0,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final cents = whole * 100 + int.parse(fraction);
  return cents > 0 ? cents : null;
}

/// `4:07pm`, as in the transaction list.
String formatTime(DateTime time) =>
    DateFormat('h:mma', 'en_US').format(time.toLocal()).toLowerCase();

/// "Today", "Yesterday", or "Mon, 26 Oct" for older days.
String formatDay(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final today = _dateOnly(now ?? DateTime.now());
  final day = _dateOnly(local);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final pattern = local.year == today.year ? 'EEE, d MMM' : 'd MMM yyyy';
  return DateFormat(pattern, 'en_US').format(local);
}

String formatDateTime(DateTime time) =>
    '${formatDay(time)} · ${formatTime(time)}';

/// First name for greetings ("Hello Alex").
String firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}

String initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return 'S';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

final _random = Random.secure();

/// Random v4 UUID, used as the idempotency key for each money movement.
String newRequestId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

// UTC so the day difference is never off by one across a DST change.
DateTime _dateOnly(DateTime t) => DateTime.utc(t.year, t.month, t.day);
