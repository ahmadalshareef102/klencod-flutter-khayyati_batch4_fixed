import '../../core/dates.dart';
import '../../core/money.dart';

/// تفضيلات التنبيهات (محفوظة في جدول الإعدادات).
class NotifyPrefs {
  const NotifyPrefs({
    this.enabled = true,
    this.hour = 9,
    this.beforeDays = 1,
    this.lateAlerts = true,
    this.stock = true,
    this.debts = true,
  });

  final bool enabled;

  /// ساعة التنبيه اليومي (0-23).
  final int hour;

  /// عدد الأيام قبل موعد التسليم للتذكير المسبق (0 = بدون).
  final int beforeDays;
  final bool lateAlerts;
  final bool stock;
  final bool debts;

  NotifyPrefs copyWith({
    bool? enabled,
    int? hour,
    int? beforeDays,
    bool? lateAlerts,
    bool? stock,
    bool? debts,
  }) =>
      NotifyPrefs(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        beforeDays: beforeDays ?? this.beforeDays,
        lateAlerts: lateAlerts ?? this.lateAlerts,
        stock: stock ?? this.stock,
        debts: debts ?? this.debts,
      );
}

class DueItem {
  const DueItem(this.orderNo, this.customerName, this.dueDate);
  final String orderNo;
  final String customerName;
  final DateTime dueDate;
}

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
  });
  final int id;
  final String title;
  final String body;
  final DateTime at;
}

String _names(List<DueItem> items) {
  final names = items.map((e) => e.customerName).toList();
  final shown = names.take(3).join('، ');
  return names.length > 3 ? '$shown و${names.length - 3} آخرين' : shown;
}

/// يبني قائمة التنبيهات القادمة (غير متكررة) لأيام الأفق. دالة نقية قابلة للاختبار.
/// تُعاد جدولتها كاملة عند أي تغيير في البيانات أو عند فتح التطبيق.
List<PlannedNotification> planNotifications({
  required DateTime now,
  required NotifyPrefs prefs,
  required List<DueItem> dueItems,
  int lowStockCount = 0,
  int debtsTotal = 0,
  String currency = '',
  int horizonDays = 14,
}) {
  if (!prefs.enabled) return const [];
  final out = <PlannedNotification>[];
  final threshold = now.add(const Duration(minutes: 1));

  for (var offset = 0; offset <= horizonDays; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final at = DateTime(day.year, day.month, day.day, prefs.hour);
    if (!at.isAfter(threshold)) continue;
    final base = 1000 + offset * 10;

    final dueToday = dueItems.where((e) => dateOnly(e.dueDate) == day).toList();
    if (dueToday.isNotEmpty) {
      out.add(PlannedNotification(
        id: base + 1,
        title: 'تسليم اليوم',
        body: '${dueToday.length} طلب: ${_names(dueToday)}',
        at: at,
      ));
    }

    if (prefs.beforeDays > 0) {
      final target = DateTime(day.year, day.month, day.day + prefs.beforeDays);
      final soon = dueItems.where((e) => dateOnly(e.dueDate) == target).toList();
      if (soon.isNotEmpty) {
        out.add(PlannedNotification(
          id: base + 2,
          title: prefs.beforeDays == 1 ? 'تسليم غداً' : 'تسليم بعد ${prefs.beforeDays} أيام',
          body: '${soon.length} طلب: ${_names(soon)}',
          at: at,
        ));
      }
    }

    if (prefs.lateAlerts && offset <= 6) {
      final overdue = dueItems.where((e) => dateOnly(e.dueDate).isBefore(day)).toList();
      if (overdue.isNotEmpty) {
        out.add(PlannedNotification(
          id: base + 3,
          title: 'طلبات متأخرة',
          body: '${overdue.length} طلب تجاوز موعد التسليم: ${_names(overdue)}',
          at: at,
        ));
      }
    }

    if (prefs.stock && lowStockCount > 0 && offset <= 2) {
      out.add(PlannedNotification(
        id: base + 4,
        title: 'نقص في المخزون',
        body: '$lowStockCount مادة وصلت إلى حد التنبيه أو أقل',
        at: at,
      ));
    }

    if (prefs.debts && debtsTotal > 0 && day.weekday == DateTime.saturday) {
      final amount = currency.isEmpty ? formatMoney(debtsTotal) : '${formatMoney(debtsTotal)} $currency';
      out.add(PlannedNotification(
        id: base + 5,
        title: 'ديون مستحقة',
        body: 'إجمالي الديون المتبقية على الزبائن: $amount',
        at: at,
      ));
    }
  }
  return out;
}
