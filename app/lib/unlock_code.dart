import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Activation codes: the owner checks the payment in Alif, then makes a code in the owner app for the
/// customer's phone number and plan; the customer types it in and the app unlocks. Works fully offline.
///
/// Code = 8 digits: DDD (day the code was made, days since 1 Jan 2026, mod 1000) + 5 digits of a keyed hash
/// of phone|plan|DDD. A monthly code is valid for 30 days from that day; a lifetime code never expires.
/// The key comes from the build (--dart-define-from-file=secrets.json, kept out of git), so both apps must be
/// built with the same secrets.json.
const _secret = String.fromEnvironment('UNLOCK_SECRET', defaultValue: 'dev-only-secret');

/// True when the apps were built without the real key (test builds only).
bool get unlockSecretIsDev => _secret == 'dev-only-secret';

final _epoch = DateTime(2026, 1, 1);
int _dayNumber(DateTime d) => DateTime(d.year, d.month, d.day).difference(_epoch).inHours ~/ 24;
DateTime _dayDate(int n) => DateTime(_epoch.year, _epoch.month, _epoch.day + n);

String _mac(String phone, String plan, int ddd) {
  final h = Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode('$phone|$plan|$ddd')).bytes;
  final v = ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) & 0x7fffffff;
  return (v % 100000).toString().padLeft(5, '0');
}

String _digits(String s) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.length > 9 ? d.substring(d.length - 9) : d;
}

/// Owner app: the code for this phone (9 digits) and plan ('month' or 'life'), made today.
String makeCode(String phone, String plan, {DateTime? now}) {
  final ddd = _dayNumber(now ?? DateTime.now()) % 1000;
  return '${ddd.toString().padLeft(3, '0')}${_mac(_digits(phone), plan, ddd)}';
}

/// Shows a code as "1234 5678".
String prettyCode(String code) => code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

enum CodeResult { ok, wrong, expired }

/// Customer app: checks a code for this phone. On success gives the plan and, for monthly, the end time.
({CodeResult result, String? plan, DateTime? until}) checkCode(String code, String phone, {DateTime? now}) {
  final c = code.replaceAll(RegExp(r'\D'), '');
  final p = _digits(phone);
  if (c.length != 8 || p.length != 9) return (result: CodeResult.wrong, plan: null, until: null);
  final ddd = int.parse(c.substring(0, 3));
  final mac = c.substring(3);
  final today = _dayNumber(now ?? DateTime.now());
  // the day the code was made: the latest day with that number, allowing the owner's phone to be a day ahead
  var made = today - ((today - ddd) % 1000 + 1000) % 1000;
  if ((ddd - today % 1000 + 1000) % 1000 == 1) made = today + 1;
  if (_mac(p, 'life', ddd) == mac) return (result: CodeResult.ok, plan: 'life', until: null);
  if (_mac(p, 'month', ddd) == mac) {
    final until = _dayDate(made + 30);
    if ((now ?? DateTime.now()).isAfter(until)) return (result: CodeResult.expired, plan: 'month', until: until);
    return (result: CodeResult.ok, plan: 'month', until: until);
  }
  return (result: CodeResult.wrong, plan: null, until: null);
}
