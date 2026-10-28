import 'package:flutter_test/flutter_test.dart';
import 'package:slate/utils/format.dart';

void main() {
  group('formatMoney', () {
    test('matches the transaction list', () {
      expect(formatMoney(105000, 'USD'), r'$1,050.00');
      expect(formatMoney(240000, 'USD', signed: true), r'+$2,400.00');
      expect(formatMoney(87400, 'EUR'), '€874.00');
      expect(formatMoney(5, 'GBP'), '£0.05');
    });

    test('drops cents from round balances only when asked', () {
      expect(formatMoney(2200000, 'USD', whole: true), r'$22,000');
      expect(formatMoney(2200050, 'USD', whole: true), r'$22,000.50');
      expect(formatMoney(2200000, 'USD'), r'$22,000.00');
    });

    test('negative amounts keep the sign in front', () {
      expect(formatMoney(-1999, 'USD'), r'-$19.99');
    });
  });

  group('parseAmount', () {
    test('reads what people type', () {
      expect(parseAmount('125'), 12500);
      expect(parseAmount('1,050.5'), 105050);
      expect(parseAmount(r'$20.05'), 2005);
      expect(parseAmount(' 0.1 '), 10);
    });

    test('rejects zero, junk and fractions of a cent', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('0'), isNull);
      expect(parseAmount('0.00'), isNull);
      expect(parseAmount('1.005'), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('-5'), isNull);
    });
  });

  test('formatTime looks like "4:07pm"', () {
    expect(formatTime(DateTime(2026, 10, 27, 16, 7)), '4:07pm');
    expect(formatTime(DateTime(2026, 10, 27, 9, 12)), '9:12am');
  });

  test('formatDay names recent days', () {
    final now = DateTime(2026, 10, 28, 9);
    expect(formatDay(DateTime(2026, 10, 28, 8), now: now), 'Today');
    expect(formatDay(DateTime(2026, 10, 27, 23), now: now), 'Yesterday');
    expect(formatDay(DateTime(2026, 10, 26, 12), now: now), 'Mon, 26 Oct');
    expect(formatDay(DateTime(2025, 12, 31, 12), now: now), '31 Dec 2025');
  });

  test('names', () {
    expect(firstName('Alex Carter'), 'Alex');
    expect(firstName('  '), 'there');
    expect(initials('Alex Carter'), 'AC');
    expect(initials('cher'), 'C');
    expect(initials(''), 'S');
  });

  test('request ids are v4 UUIDs and unique', () {
    final ids = {for (var i = 0; i < 500; i++) newRequestId()};
    expect(ids, hasLength(500));
    for (final id in ids.take(20)) {
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
  });
}
