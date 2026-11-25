import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import '../customers/customers_screen.dart';
import '../more/more_screen.dart';
import '../orders/order_status.dart';
import '../orders/orders_screen.dart';
import '../settings/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <_Tab>[
      const _Tab('الرئيسية', Icons.home_outlined, Icons.home, _HomePage()),
      const _Tab('الطلبات', Icons.receipt_long_outlined, Icons.receipt_long, OrdersScreen()),
      const _Tab('الزبائن', Icons.people_outline, Icons.people, CustomersScreen()),
      const _Tab('المزيد', Icons.apps_outlined, Icons.apps, MoreScreen()),
      const _Tab('الإعدادات', Icons.settings_outlined, Icons.settings, SettingsScreen()),
    ];
    final i = _index.clamp(0, pages.length - 1);
    return Scaffold(
      appBar: AppBar(title: Text(pages[i].label)),
      body: pages[i].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: [
          for (final t in pages)
            NavigationDestination(
                icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class _HomePage extends ConsumerWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final shop = ref.watch(currentShopProvider);
    final active = ref.watch(activeOrdersProvider).valueOrNull ?? const [];
    final today = dateOnly(DateTime.now());
    final finance = canManageFinance(session.user);
    final month = finance ? ref.watch(monthSummaryProvider).valueOrNull : null;

    final lateCount = active.where((o) => OrderStatus.isLate(o.order)).length;
    final ready = active.where((o) => o.order.status == OrderStatus.ready).length;
    final dueToday = active.where((o) {
      final d = o.order.dueDate;
      return d != null && dateOnly(d) == today;
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('أهلاً، ${session.user?.fullName ?? ''}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (session.isAdmin && shops.length == 2)
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: 0, label: Text('الإجمالي')),
              for (final s in shops)
                ButtonSegment(
                    value: s.id,
                    label: Text(s.type == ShopTypes.men ? 'الرجالي' : 'العبايات')),
            ],
            selected: {session.shopId ?? 0},
            onSelectionChanged: (v) => ref
                .read(sessionProvider.notifier)
                .selectShop(v.first == 0 ? null : v.first),
          ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(shop?.name ?? 'التقرير الموحد للمحلين'),
            subtitle: Text(shop == null
                ? 'اختر محلاً لإضافة الزبائن والطلبات'
                : [shop.phone, shop.address]
                    .whereType<String>()
                    .where((e) => e.isNotEmpty)
                    .join(' - ')),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            _StatCard('طلبات جارية', '${active.length}', Icons.pending_actions),
            _StatCard('جاهزة للتسليم', '$ready', Icons.check_circle_outline),
            _StatCard('تسليم اليوم', '$dueToday', Icons.today),
            _StatCard('متأخرة', '$lateCount', Icons.warning_amber_rounded),
            if (month != null) ...[
              _StatCard('محصّل هذا الشهر', formatMoney(month.collected), Icons.payments_outlined),
              _StatCard('الديون المتبقية', formatMoney(month.outstandingDebts), Icons.account_balance_wallet_outlined),
              _StatCard('مصروفات الشهر', formatMoney(month.operatingExpenses), Icons.receipt_outlined),
              _StatCard('صافي الربح التقديري', formatMoney(month.netProfit), Icons.trending_up),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
