import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import '../inventory/inventory_repository.dart';
import '../orders/order_repository.dart';
import 'notification_planner.dart';
import 'notification_service.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

class NotifyPrefsNotifier extends StateNotifier<NotifyPrefs> {
  NotifyPrefsNotifier(this._read, this._write) : super(const NotifyPrefs()) {
    _load();
  }
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  Future<void> _load() async {
    final enabled = await _read('notif_enabled');
    final hour = int.tryParse(await _read('notif_hour') ?? '');
    final before = int.tryParse(await _read('notif_before_days') ?? '');
    final lateFlag = await _read('notif_late');
    final stock = await _read('notif_stock');
    final debts = await _read('notif_debts');
    if (!mounted) return;
    state = NotifyPrefs(
      enabled: enabled != '0',
      hour: (hour != null && hour >= 0 && hour <= 23) ? hour : 9,
      beforeDays: (before != null && before >= 0 && before <= 7) ? before : 1,
      lateAlerts: lateFlag != '0',
      stock: stock != '0',
      debts: debts != '0',
    );
  }

  Future<void> update(NotifyPrefs p) async {
    state = p;
    await _write('notif_enabled', p.enabled ? '1' : '0');
    await _write('notif_hour', '${p.hour}');
    await _write('notif_before_days', '${p.beforeDays}');
    await _write('notif_late', p.lateAlerts ? '1' : '0');
    await _write('notif_stock', p.stock ? '1' : '0');
    await _write('notif_debts', p.debts ? '1' : '0');
  }
}

final notifyPrefsProvider = StateNotifierProvider<NotifyPrefsNotifier, NotifyPrefs>((ref) {
  final db = ref.watch(databaseProvider);
  return NotifyPrefsNotifier(
    (k) => db.getSetting(k),
    (k, v) => db.setSetting(k, v),
  );
});

/// المحل المسموح للمستخدم: المدير يرى الكل، والعامل محله فقط.
final _notifyShopProvider = Provider<int?>((ref) {
  final u = ref.watch(sessionProvider.select((s) => s.user));
  if (u == null || u.role == Roles.admin) return null;
  return u.shopId;
});

final notifyOrdersProvider = StreamProvider<List<OrderWithCustomer>>((ref) {
  return ref.watch(orderRepositoryProvider).watch(
        shopId: ref.watch(_notifyShopProvider),
        activeOnly: true,
      );
});

final notifyLowStockProvider = StreamProvider<int>((ref) {
  final user = ref.watch(sessionProvider.select((s) => s.user));
  if (!canManageFinance(user)) return Stream.value(0);
  return ref
      .watch(inventoryRepositoryProvider)
      .watchFabrics(shopId: ref.watch(_notifyShopProvider))
      .map((l) => l.where(InventoryRepository.isLow).length);
});

final notifyDebtsProvider = StreamProvider<int>((ref) {
  final user = ref.watch(sessionProvider.select((s) => s.user));
  if (!canManageFinance(user)) return Stream.value(0);
  final now = DateTime.now();
  return ref
      .watch(accountsRepositoryProvider)
      .watchSummary(
        shopId: ref.watch(_notifyShopProvider),
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day + 1),
      )
      .map((s) => s.outstandingDebts);
});

/// يراقب البيانات ويُعيد جدولة التنبيهات (مع تأخير بسيط لتجميع التغييرات).
final notificationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(notificationServiceProvider);
  Timer? timer;

  void schedule() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(sessionProvider).user;
      if (user == null) {
        await service.cancelAll();
        return;
      }
      final orders = ref.read(notifyOrdersProvider).valueOrNull ?? const <OrderWithCustomer>[];
      final plan = planNotifications(
        now: DateTime.now(),
        prefs: ref.read(notifyPrefsProvider),
        dueItems: [
          for (final o in orders)
            if (o.order.dueDate != null)
              DueItem(o.order.orderNo, o.customer.name, o.order.dueDate!),
        ],
        lowStockCount: ref.read(notifyLowStockProvider).valueOrNull ?? 0,
        debtsTotal: ref.read(notifyDebtsProvider).valueOrNull ?? 0,
      );
      await service.apply(plan);
    });
  }

  for (final p in <ProviderListenable<Object?>>[
    sessionProvider,
    notifyPrefsProvider,
    notifyOrdersProvider,
    notifyLowStockProvider,
    notifyDebtsProvider,
  ]) {
    ref.listen<Object?>(p, (_, __) => schedule());
  }
  ref.onDispose(() => timer?.cancel());
  schedule();
});
