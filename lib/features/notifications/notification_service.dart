import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_planner.dart';

/// غلاف رفيع حول إشعارات Android المحلية. لا يحتاج إنترنت.
/// الجدولة بتوقيت مطلق (UTC instant) فلا تتأثر بمنطقة الجهاز،
/// وبوضع inexact لتجنب صلاحية المنبهات الدقيقة ولتوفير البطارية.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'khayyati_alerts',
      'تنبيهات خياطتي',
      channelDescription: 'تنبيهات التسليم والمخزون والديون',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermission() async {
    await init();
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> areEnabled() async {
    await init();
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNow(String title, String body) async {
    await init();
    if (!_ready) return;
    await _plugin.show(999, title, body, _details);
  }

  Future<void> cancelAll() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// يستبدل كل التنبيهات المجدولة بالخطة الجديدة.
  Future<void> apply(List<PlannedNotification> plan) async {
    await init();
    if (!_ready) return;
    try {
      if (plan.isNotEmpty && !_permissionAsked) {
        _permissionAsked = true;
        await requestPermission();
      }
      await _plugin.cancelAll();
      for (final p in plan) {
        await _plugin.zonedSchedule(
          p.id,
          p.title,
          p.body,
          tz.TZDateTime.from(p.at, tz.UTC),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // الإشعارات ميزة مساندة: لا نُسقط التطبيق إن فشلت الجدولة.
    }
  }
}
