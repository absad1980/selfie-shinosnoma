import 'package:flutter_test/flutter_test.dart';
import 'package:selfie_shinosnoma/unlock_code.dart';

void main() {
  final day = DateTime(2026, 11, 10, 15);

  test('lifetime code unlocks forever, only for its phone', () {
    final code = makeCode('90 123 45 67', 'life', now: day);
    expect(code.length, 8);
    expect(checkCode(code, '+992901234567', now: day).plan, 'life');
    expect(checkCode(code, '901234567', now: DateTime(2031, 5, 1)).result, CodeResult.ok);
    expect(checkCode(code, '931112233', now: day).result, CodeResult.wrong);
  });

  test('monthly code lasts 30 days, then expires', () {
    final code = makeCode('931112233', 'month', now: day);
    final r = checkCode(prettyCode(code), '93 111 22 33', now: day.add(const Duration(days: 3)));
    expect(r.result, CodeResult.ok);
    expect(r.plan, 'month');
    expect(r.until, DateTime(2026, 12, 10));
    expect(checkCode(code, '931112233', now: DateTime(2026, 12, 11)).result, CodeResult.expired);
  });

  test('owner phone a day ahead, typos and wrong plan digits are refused', () {
    final code = makeCode('927778899', 'month', now: day.add(const Duration(days: 1)));
    expect(checkCode(code, '927778899', now: day).result, CodeResult.ok);
    final bad = '${code.substring(0, 7)}${(int.parse(code[7]) + 1) % 10}';
    expect(checkCode(bad, '927778899', now: day).result, CodeResult.wrong);
    expect(checkCode('1234', '927778899', now: day).result, CodeResult.wrong);
  });

  test('codes made across the 1000-day wrap still work', () {
    final made = DateTime(2028, 9, 26); // around day 999 → 0
    final code = makeCode('905556677', 'month', now: made);
    expect(checkCode(code, '905556677', now: made.add(const Duration(days: 5))).result, CodeResult.ok);
  });
}
