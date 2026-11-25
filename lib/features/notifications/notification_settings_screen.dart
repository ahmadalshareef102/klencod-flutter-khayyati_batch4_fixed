import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import 'notification_providers.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<NotificationSettingsScreen> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await ref.read(notificationServiceProvider).areEnabled();
    if (mounted) setState(() => _allowed = ok);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notifyPrefsProvider);
    final notifier = ref.read(notifyPrefsProvider.notifier);
    final service = ref.read(notificationServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات التنبيهات')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('تفعيل التنبيهات'),
            subtitle: const Text('تعمل بدون إنترنت ومن داخل الجهاز'),
            value: prefs.enabled,
            onChanged: (v) => notifier.update(prefs.copyWith(enabled: v)),
          ),
          if (_allowed == false)
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('إذن الإشعارات غير ممنوح'),
              subtitle: const Text('اضغط لطلب الإذن، أو فعّله من إعدادات الجهاز'),
              onTap: () async {
                await service.requestPermission();
                await _check();
              },
            ),
          ListTile(
            title: const Text('وقت التنبيه اليومي'),
            subtitle: Text('الساعة ${prefs.hour.toString().padLeft(2, '0')}:00'),
            trailing: const Icon(Icons.schedule),
            enabled: prefs.enabled,
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: prefs.hour, minute: 0),
              );
              if (t != null) await notifier.update(prefs.copyWith(hour: t.hour));
            },
          ),
          ListTile(
            title: const Text('تذكير قبل موعد التسليم'),
            subtitle: Text(prefs.beforeDays == 0
                ? 'بدون تذكير مسبق'
                : prefs.beforeDays == 1
                    ? 'قبل يوم واحد'
                    : 'قبل ${prefs.beforeDays} أيام'),
            enabled: prefs.enabled,
            trailing: DropdownButton<int>(
              value: prefs.beforeDays,
              items: [
                for (var i = 0; i <= 3; i++)
                  DropdownMenuItem(value: i, child: Text(i == 0 ? 'بدون' : '$i')),
              ],
              onChanged: prefs.enabled
                  ? (v) => notifier.update(prefs.copyWith(beforeDays: v ?? 1))
                  : null,
            ),
          ),
          SwitchListTile(
            title: const Text('الطلبات المتأخرة'),
            value: prefs.lateAlerts,
            onChanged:
                prefs.enabled ? (v) => notifier.update(prefs.copyWith(lateAlerts: v)) : null,
          ),
          SwitchListTile(
            title: const Text('نقص المخزون'),
            subtitle: const Text('للمدير ومن لديه صلاحية مالية'),
            value: prefs.stock,
            onChanged: prefs.enabled ? (v) => notifier.update(prefs.copyWith(stock: v)) : null,
          ),
          SwitchListTile(
            title: const Text('الديون المستحقة'),
            subtitle: const Text('ملخص أسبوعي كل يوم سبت'),
            value: prefs.debts,
            onChanged: prefs.enabled ? (v) => notifier.update(prefs.copyWith(debts: v)) : null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('إرسال إشعار تجريبي'),
            onTap: () async {
              await service.requestPermission();
              await service.showNow('خياطتي', 'هذا إشعار تجريبي ✓');
              if (context.mounted) showMsg(context, 'أُرسل الإشعار التجريبي');
              await _check();
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'ملاحظات: تُجدول التنبيهات للأيام الـ14 القادمة وتُحدَّث تلقائياً عند فتح التطبيق '
              'أو تغيّر البيانات، فافتح التطبيق مرة كل أسبوعين على الأقل. بعض الأجهزة توقف '
              'التطبيقات في الخلفية لتوفير الطاقة؛ إن لم تصل التنبيهات فاستثنِ خياطتي من '
              'تحسين البطارية في إعدادات الجهاز.',
            ),
          ),
        ],
      ),
    );
  }
}
