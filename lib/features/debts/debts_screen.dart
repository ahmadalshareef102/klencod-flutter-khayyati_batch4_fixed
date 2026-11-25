import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import '../orders/order_status.dart';
import '../payments/payment_repository.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    if (!canManageFinance(user)) {
      return Scaffold(
          appBar: AppBar(title: const Text('الديون')),
          body: const Center(child: Text('ليست لديك صلاحية عرض الديون')));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الديون'),
          bottom: const TabBar(tabs: [Tab(text: 'ديون الزبائن'), Tab(text: 'سجل التحصيل')]),
        ),
        body: const TabBarView(children: [_DebtsTab(), _CollectionsTab()]),
      ),
    );
  }
}

class _DebtsTab extends ConsumerWidget {
  const _DebtsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(customerDebtsProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final session = ref.watch(sessionProvider);
    final total = debts.fold<int>(0, (s, d) => s + d.total);
    final today = dateOnly(DateTime.now());

    // إجمالي الديون حسب المحل (للعرض الموحد)
    final byShop = <int, int>{};
    for (final d in debts) {
      byShop[d.customer.shopId] = (byShop[d.customer.shopId] ?? 0) + d.total;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إجمالي الديون: ${formatMoney(total)}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (session.shopId == null)
                  for (final s in shops)
                    Text('${s.name}: ${formatMoney(byShop[s.id] ?? 0)}'),
                const SizedBox(height: 4),
                Text('الدين = قيمة الطلبات غير الملغاة − الدفعات غير المُبطلة. '
                    'تاريخ الاستحقاق هو موعد تسليم الطلب.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        if (debts.isEmpty)
          const Padding(
              padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد ديون'))),
        for (final d in debts)
          Card(
            child: ExpansionTile(
              title: Text(d.customer.name),
              subtitle: Text(d.customer.phone),
              trailing: Text(formatMoney(d.total),
                  style: const TextStyle(
                      color: AppColors.warning, fontWeight: FontWeight.bold)),
              children: [
                for (final r in d.rows)
                  ListTile(
                    dense: true,
                    title: Text('${r.order.orderNo} • ${formatMoney(r.remaining)} متبقٍ'),
                    subtitle: Text([
                      'السعر ${formatMoney(r.order.price)}',
                      'الواصل ${formatMoney(r.paid)}',
                      if (r.order.dueDate != null) 'الاستحقاق ${fmtDate(r.order.dueDate!)}',
                      if (r.order.dueDate != null &&
                          dateOnly(r.order.dueDate!).isBefore(today) &&
                          r.order.status != OrderStatus.delivered)
                        'متأخر',
                    ].join(' • ')),
                    trailing: StatusChip(r.order.status),
                    onTap: () => context.push('/orders/${r.order.id}'),
                  ),
                TextButton(
                  onPressed: () => context.push('/customers/${d.customer.id}/statement'),
                  child: const Text('كشف الحساب'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(paymentLogProvider).valueOrNull ?? const <PaymentRow>[];
    final user = ref.watch(sessionProvider).user;
    if (log.isEmpty) return const Center(child: Text('لا توجد دفعات'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: log.length,
      itemBuilder: (_, i) {
        final r = log[i];
        final p = r.payment;
        final voided = p.voidedAt != null;
        return Card(
          child: ListTile(
            title: Text('${formatMoney(p.amount)} • ${r.customerName}',
                style: voided
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null),
            subtitle: Text([
              p.paymentNo,
              r.orderNo,
              fmtDate(p.paidAt),
              PaymentRepository.methodLabel(p.method),
              if (voided) 'مُبطلة: ${p.voidReason ?? ''}',
            ].join(' • ')),
            trailing: (!voided && isAdmin(user))
                ? IconButton(
                    tooltip: 'إبطال',
                    icon: const Icon(Icons.block),
                    onPressed: () => voidPaymentFlow(context, ref, p.id),
                  )
                : null,
            onTap: () => context.push('/orders/${p.orderId}'),
          ),
        );
      },
    );
  }
}

/// حوار إبطال دفعة (للمدير) مع سبب إجباري.
Future<void> voidPaymentFlow(BuildContext context, WidgetRef ref, int paymentId) {
  return showFormDialog(
    context,
    title: 'إبطال الدفعة',
    note: 'لا تُحذف الدفعة؛ تبقى في السجل كمُبطلة مع السبب. لتصحيح مبلغ: أبطلها ثم سجّل الدفعة الصحيحة.',
    items: const [TextItem('سبب الإبطال', required: true)],
    okLabel: 'إبطال',
    onSubmit: (v) => ref
        .read(paymentRepositoryProvider)
        .voidPayment(ref.read(sessionProvider).user!.id, paymentId, v[0]! as String),
  );
}
