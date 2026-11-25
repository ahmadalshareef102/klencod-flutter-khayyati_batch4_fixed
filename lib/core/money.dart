import 'text_utils.dart';

/// المبالغ تُخزَّن كأعداد صحيحة بأصغر وحدة (مئة وحدة = 1.00).
int? parseMoney(String input) {
  final v = parseDecimal(input);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

String formatMoney(int minor) {
  final neg = minor < 0;
  final a = minor.abs();
  final whole = a ~/ 100;
  final frac = a % 100;
  final s = StringBuffer(_group(whole));
  if (frac != 0) {
    s.write('.${frac.toString().padLeft(2, '0')}');
  }
  return neg ? '-$s' : s.toString();
}

String _group(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
