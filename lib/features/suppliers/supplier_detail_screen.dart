import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import '../payments/payment_repository.dart';

class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});
  final int supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(supplierByIdProvider(supplierId)).valueOrNull;
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final lines = ref.watch(supplierStatementProvider(supplierId)).valueOrNull ?? const [];
    final due = lines.isEmpty ? 0 : lines.last.balance;
    final repo = ref.read(supplierRepositoryProvider);
    final actor = ref.read(sessionProvider).user!.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showFormDialog(
              context,
              title: 'تعديل المورد',
              items: [
                TextItem('الاسم', initial: s.name, required: true),
                TextItem('الهاتف', initial: s.phone ?? ''),
                TextItem('العنوان', initial: s.address ?? ''),
                TextItem('ملاحظات', initial: s.notes ?? '', maxLines: 2),
              ],
              onSubmit: (v) => repo.update(
                  actorId: actor,
                  id: s.id,
                  name: v[0]! as String,
                  phone: v[1] as String?,
                  address: v[2] as String?,
                  notes: v[3] as String?),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.phone != null) Text(s.phone!),
                  if (s.address != null) Text(s.address!),
                  if (s.notes != null) Text(s.notes!),
                  const SizedBox(height: 8),
                  Text('المستحق للمورد: ${formatMoney(due)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: due > 0 ? AppColors.warning : null)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: due <= 0
                ? null
                : () => showFormDialog(
                      context,
                      title: 'دفعة للمورد',
                      note: 'المستحق الحالي ${formatMoney(due)}',
                      items: [
                        const MoneyItem('المبلغ'),
                        const DateItem('التاريخ'),
                        const DropItem('طريقة الدفع', PaymentRepository.methods, initial: 'cash'),
                        const TextItem('ملاحظات'),
                      ],
                      onSubmit: (v) async {
                        await repo.pay(
                            actorId: actor,
                            supplierId: s.id,
                            amount: v[0]! as int,
                            paidAt: v[1]! as DateTime,
                            method: (v[2] as String?) ?? 'cash',
                            notes: v[3] as String?);
                      },
                    ),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('تسجيل دفعة'),
          ),
          const SizedBox(height: 16),
          Text('كشف الحساب', style: Theme.of(context).textTheme.titleSmall),
          if (lines.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حركات')),
          for (final l in lines)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(l.kind == 'purchase' ? Icons.shopping_cart_outlined : Icons.payments_outlined,
                  color: l.kind == 'purchase' ? AppColors.warning : AppColors.success),
              title: Text('${l.kind == 'purchase' ? 'شراء' : 'دفعة'} • ${l.description}'),
              subtitle: Text(fmtDate(l.date)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${l.kind == 'purchase' ? '+' : '−'}${formatMoney(l.amount)}'),
                  Text('الرصيد ${formatMoney(l.balance)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
