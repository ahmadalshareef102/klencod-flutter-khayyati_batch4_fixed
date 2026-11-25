/// تحويل الأرقام العربية والفارسية إلى لاتينية.
String normalizeDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

String normalizePhone(String s) =>
    normalizeDigits(s).replaceAll(RegExp(r'[\s\-()]'), '');

/// يحوّل نص رقم (قد يحتوي فاصلة عربية) إلى رقم عشري أو null.
double? parseDecimal(String input) {
  final t = normalizeDigits(input)
      .trim()
      .replaceAll(',', '.')
      .replaceAll('٫', '.')
      .replaceAll('،', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}

String? blankToNull(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}
