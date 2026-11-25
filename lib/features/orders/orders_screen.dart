import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'order_status.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final canCreate = user != null && (user.role == Roles.admin || user.canCreateOrders);
    final filter = ref.watch(orderFilterProvider);
    final orders = ref.watch(ordersProvider);
    final paid = ref.watch(paidByOrderProvider).valueOrNull ?? const <int, int>{};

    final filters = <String, String>{
      'active': 'الجارية',
      'all': 'الكل',
      for (final s in OrderStatus.all) s: OrderStatus.label(s),
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/orders/new'),
              icon: const Icon(Icons.add),
              label: const Text('طلب جديد'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث برقم الطلب أو اسم الزبون أو هاتفه',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => ref.read(orderSearchProvider.notifier).state = v,
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in filters.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: filter == e.key,
                      onSelected: (_) =>
                          ref.read(orderFilterProvider.notifier).state = e.key,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: orders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Center(child: Text('تعذّر تحميل الطلبات')),
              data: (list) {
                if (list.isEmpty) return const Center(child: Text('لا توجد طلبات'));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i].order;
                    final c = list[i].customer;
                    final remaining = o.price - (paid[o.id] ?? 0);
                    final isLate = OrderStatus.isLate(o);
                    return Card(
                      shape: isLate
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.warning, width: 1.5))
                          : null,
                      child: ListTile(
                        onTap: () => context.push('/orders/${o.id}'),
                        title: Row(
                          children: [
                            Expanded(child: Text('${o.orderNo} • ${c.name}')),
                            StatusChip(o.status),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (o.garmentType != null) o.garmentType!,
                              if (o.dueDate != null) 'التسليم ${fmtDate(o.dueDate!)}',
                              if (isLate) 'متأخر',
                              if (!OrderStatus.isTerminal(o.status) && remaining > 0)
                                'المتبقي ${formatMoney(remaining)}',
                            ].join(' • '),
                            style: isLate
                                ? const TextStyle(color: AppColors.warning)
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
