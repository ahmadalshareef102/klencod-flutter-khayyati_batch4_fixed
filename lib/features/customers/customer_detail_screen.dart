import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import '../measurements/measurement_repository.dart';
import '../orders/order_status.dart';
import 'customer_form_dialog.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final int customerId;

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref, bool archived) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archived ? 'استعادة الزبون' : 'أرشفة الزبون'),
        content: Text(archived
            ? 'هل تريد إعادة الزبون إلى القائمة؟'
            : 'سيُخفى الزبون من القائمة مع بقاء طلباته وحساباته محفوظة. متابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true) return;
    final actor = ref.read(sessionProvider).user!.id;
    await ref
        .read(customerRepositoryProvider)
        .setArchived(actor, customerId, !archived);
    if (context.mounted && !archived) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerByIdProvider(customerId)).valueOrNull;
    if (customer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final summary = ref.watch(customerSummaryProvider(customerId)).valueOrNull;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(customer.name),
          actions: [
            IconButton(
              tooltip: 'كشف الحساب',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => context.push('/customers/$customerId/statement'),
            ),
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      CustomerFormDialog(shopId: customer.shopId, customer: customer)),
            ),
            IconButton(
              tooltip: customer.isArchived ? 'استعادة' : 'أرشفة',
              icon: Icon(customer.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              onPressed: () => _toggleArchive(context, ref, customer.isArchived),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'الطلبات'), Tab(text: 'المقاسات')]),
        ),
        body: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.phone,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (customer.address != null) Text(customer.address!),
                    if (customer.notes != null) Text(customer.notes!),
                    Text('مسجّل منذ ${fmtDate(customer.createdAt)}'),
                    const Divider(),
                    if (summary != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Stat('الطلبات', '${summary.ordersCount}'),
                          _Stat('إجمالي المدفوع', formatMoney(summary.totalPaid)),
                          _Stat('إجمالي الدين', formatMoney(summary.debt),
                              color: summary.debt > 0 ? AppColors.warning : null),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OrdersTab(customerId: customerId, archived: customer.isArchived),
                  _MeasurementsTab(customerId: customerId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.customerId, required this.archived});
  final int customerId;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(customerOrdersProvider(customerId)).valueOrNull ?? const [];
    final user = ref.watch(sessionProvider).user;
    final canCreate = !archived && user != null && (user.role == Roles.admin || user.canCreateOrders);
    return Column(
      children: [
        if (canCreate)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: () => context.push('/orders/new?customerId=$customerId'),
              icon: const Icon(Icons.add),
              label: const Text('طلب جديد'),
            ),
          ),
        Expanded(
          child: orders.isEmpty
              ? const Center(child: Text('لا توجد طلبات'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (_, i) {
                    final o = orders[i].order;
                    return Card(
                      child: ListTile(
                        title: Text(o.orderNo),
                        subtitle: Text(
                            '${o.garmentType ?? 'طلب'} • ${fmtDate(o.orderDate)} • ${formatMoney(o.price)}'),
                        trailing: StatusChip(o.status),
                        onTap: () => context.push('/orders/${o.id}'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MeasurementsTab extends ConsumerWidget {
  const _MeasurementsTab({required this.customerId});
  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(measurementsForCustomerProvider(customerId)).valueOrNull ?? const [];
    final repo = ref.read(measurementRepositoryProvider);
    final actor = ref.read(sessionProvider).user!.id;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            onPressed: () => context.push('/measurements/edit?customerId=$customerId'),
            icon: const Icon(Icons.add),
            label: const Text('سجل مقاسات جديد'),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('لا توجد مقاسات محفوظة'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final m = list[i];
                    final values = MeasurementFields.decode(m.valuesJson);
                    return Card(
                      child: ListTile(
                        title: Text(m.label),
                        subtitle: Text(
                            '${fmtDate(m.createdAt)} • ${values.length} مقاس\n${values.entries.take(4).map((e) => '${e.key}: ${e.value}').join(' ، ')}'),
                        isThreeLine: true,
                        onTap: () => context.push(
                            '/measurements/edit?customerId=$customerId&measurementId=${m.id}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'copy') {
                              await repo.duplicate(actor, m.id);
                            } else if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('حذف سجل المقاسات'),
                                  content: const Text(
                                      'الطلبات السابقة تحتفظ بنسخها الثابتة ولن تتأثر. متابعة؟'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('إلغاء')),
                                    TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('حذف')),
                                  ],
                                ),
                              );
                              if (ok == true) await repo.delete(actor, m.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'copy', child: Text('نسخ')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
