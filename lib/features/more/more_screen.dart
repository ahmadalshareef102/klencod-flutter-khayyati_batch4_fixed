import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions.dart';
import '../../data/providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    final finance = canManageFinance(user);

    Widget item(IconData icon, String title, String subtitle, String route) => Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push(route),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (finance) ...[
          item(Icons.account_balance_wallet_outlined, 'الديون', 'ديون الزبائن وسجل التحصيل', '/debts'),
          item(Icons.bar_chart_outlined, 'الحسابات والأرباح', 'الإيرادات والتكاليف وصافي الربح', '/accounts'),
          item(Icons.receipt_outlined, 'المصروفات', 'الإيجار والكهرباء والأجور وغيرها', '/expenses'),
          item(Icons.inventory_2_outlined, 'المخزون', 'الأقمشة والمواد وحركتها', '/inventory'),
          item(Icons.local_shipping_outlined, 'الموردون', 'المشتريات والمستحقات والدفعات', '/suppliers'),
        ],
        if (isAdmin(user))
          item(Icons.groups_outlined, 'العاملون', 'الحسابات والصلاحيات', '/staff'),
        if (!finance && !isAdmin(user))
          const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('لا توجد أقسام إضافية متاحة لحسابك'))),
      ],
    );
  }
}
