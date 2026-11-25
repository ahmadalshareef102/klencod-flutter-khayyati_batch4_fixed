import 'dates.dart';

enum PeriodKind { today, week, month, custom }

/// فترة زمنية: [from] شاملة و[to] غير شاملة (بداية اليوم التالي).
class Period {
  const Period(this.kind, this.from, this.to);
  final PeriodKind kind;
  final DateTime from;
  final DateTime to;

  static Period of(PeriodKind kind, {DateTime? now, DateTime? customFrom, DateTime? customTo}) {
    final today = dateOnly(now ?? DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    switch (kind) {
      case PeriodKind.today:
        return Period(kind, today, tomorrow);
      case PeriodKind.week:
        // الأسبوع يبدأ يوم السبت
        final back = (today.weekday + 1) % 7;
        return Period(kind, today.subtract(Duration(days: back)), tomorrow);
      case PeriodKind.month:
        return Period(kind, DateTime(today.year, today.month, 1), tomorrow);
      case PeriodKind.custom:
        final f = dateOnly(customFrom ?? today);
        final t = dateOnly(customTo ?? today).add(const Duration(days: 1));
        return Period(kind, f, t);
    }
  }

  String get label {
    final last = to.subtract(const Duration(days: 1));
    return from == dateOnly(last) ? fmtDate(from) : '${fmtDate(from)} - ${fmtDate(last)}';
  }
}
