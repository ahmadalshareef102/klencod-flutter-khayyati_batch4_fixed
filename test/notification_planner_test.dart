import 'package:flutter_test/flutter_test.dart';
import 'package:khayyati/features/notifications/notification_planner.dart';

void main() {
  // الأربعاء 25 نوفمبر 2026، الساعة 8:00
  final now = DateTime(2026, 11, 25, 8);
  final today = DateTime(2026, 11, 25);
  final items = [
    DueItem('M-2026-0001', 'أحمد', today),
    DueItem('M-2026-0002', 'سالم', today.add(const Duration(days: 1))),
    DueItem('M-2026-0003', 'خالد', DateTime(2026, 11, 20)),
  ];

  PlannedNotification? byId(List<PlannedNotification> l, int id) {
    for (final p in l) {
      if (p.id == id) return p;
    }
    return null;
  }

  test('تسليم اليوم والتذكير المسبق والمتأخر في يوم واحد', () {
    final plan = planNotifications(now: now, prefs: const NotifyPrefs(), dueItems: items);
    expect(byId(plan, 1001)!.title, 'تسليم اليوم');
    expect(byId(plan, 1001)!.body, contains('أحمد'));
    expect(byId(plan, 1002)!.title, 'تسليم غداً');
    expect(byId(plan, 1002)!.body, contains('سالم'));
    final overdue = byId(plan, 1003)!;
    expect(overdue.title, 'طلبات متأخرة');
    expect(overdue.body, contains('خالد'));
    expect(overdue.at, DateTime(2026, 11, 25, 9));
    // في اليوم التالي يصبح طلب أحمد متأخراً أيضاً
    expect(byId(plan, 1013)!.body, startsWith('2 طلب'));
    expect(byId(plan, 1011)!.body, contains('سالم'));
  });

  test('لا تنبيه لوقت فات، ولا شيء عند التعطيل', () {
    final afterNine = planNotifications(
        now: DateTime(2026, 11, 25, 10), prefs: const NotifyPrefs(), dueItems: items);
    expect(byId(afterNine, 1001), isNull);
    expect(byId(afterNine, 1011), isNotNull);
    expect(
        planNotifications(
            now: now, prefs: const NotifyPrefs(enabled: false), dueItems: items),
        isEmpty);
  });

  test('الإعدادات: التذكير المسبق بعدة أيام وإيقاف المتأخر', () {
    final plan = planNotifications(
      now: now,
      prefs: const NotifyPrefs(beforeDays: 2, lateAlerts: false),
      dueItems: [DueItem('x', 'سالم', DateTime(2026, 11, 27)), ...items],
    );
    expect(byId(plan, 1002)!.title, 'تسليم بعد 2 أيام');
    expect(byId(plan, 1002)!.body, contains('سالم'));
    expect(byId(plan, 1003), isNull);
  });

  test('المخزون يومين فقط، والديون كل سبت', () {
    final plan = planNotifications(
        now: now, prefs: const NotifyPrefs(), dueItems: const [], lowStockCount: 3, debtsTotal: 250000);
    expect(byId(plan, 1004)!.body, contains('3'));
    expect(byId(plan, 1024), isNotNull);
    expect(byId(plan, 1034), isNull);
    final sat = byId(plan, 1035)!; // السبت 28 نوفمبر
    expect(sat.at.weekday, DateTime.saturday);
    expect(sat.body, contains('2,500'));
    expect(
        planNotifications(
                now: now, prefs: const NotifyPrefs(), dueItems: const [], debtsTotal: 0)
            .where((p) => p.id % 10 == 5),
        isEmpty);
  });

  test('اختصار الأسماء والمعرّفات فريدة', () {
    final many = [
      for (var i = 0; i < 5; i++) DueItem('n$i', 'زبون$i', today),
    ];
    final plan = planNotifications(now: now, prefs: const NotifyPrefs(), dueItems: many);
    expect(byId(plan, 1001)!.body, contains('و2 آخرين'));
    final ids = plan.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
