import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/period_bar.dart';
import '../../core/permissions.dart';
import '../../core/ui.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'expense_repository.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  Future<void> _form(BuildContext context, WidgetRef ref, int shopId, [Expense? e]) {
    return showFormDialog(
      context,
      title: e == null ? 'إضافة مصروف' : 'تعديل المصروف',
      items: [
        DropItem('الفئة', ExpenseCategories.labels, initial: e?.category, required: true),
        MoneyItem('المبلغ', initial: e == null ? '' : formatMoney(e.amount).replaceAll(',', '')),
        DateItem('التاريخ', initial: e?.date),
        TextItem('ملاحظات', initial: e?.notes ?? '', maxLines: 2),
      ],
      onSubmit: (v) {
        final repo = ref.read(expenseRepositoryProvider);
        final actor = ref.read(sessionProvider).user!.id;
        if (e == null) {
          return repo.add(
              actorId: actor,
              shopId: shopId,
              category: v[0]! as String,
              amount: v[1]! as int,
              date: v[2]! as DateTime,
              notes: v[3] as String?);
        }
        return repo.update(
            actorId: actor,
            id: e.id,
            category: v[0]! as String,
            amount: v[1]! as int,
            date: v[2]! as DateTime,
            notes: v[3] as String?);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!canManageFinance(session.user)) {
      return Scaffold(
          appBar: AppBar(title: const Text('المصروفات')),
          body: const Center(child: Text('ليست لديك صلاحية')));
    }
    final list = ref.watch(expensesProvider).valueOrNull ?? const <Expense>[];
    final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];
    final total = list.fold<int>(0, (s, e) => s + e.amount);
    final byCat = <String, int>{};
    for (final e in list) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final shopId = session.shopId;
          if (shopId == null) {
            showMsg(context, 'اختر محلاً من الصفحة الرئيسية أولاً');
            return;
          }
          _form(context, ref, shopId);
        },
        icon: const Icon(Icons.add),
        label: const Text('مصروف'),
      ),
      body: Column(
        children: [
          const PeriodBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'بحث في الملاحظات أو الفئة', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => ref.read(expenseSearchProvider.notifier).state = v,
            ),
          ),
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الإجمالي: ${formatMoney(total)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final e in byCat.entries)
                    Text('${ExpenseCategories.label(e.key)}: ${formatMoney(e.value)}'),
                ],
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('لا توجد مصروفات في هذه الفترة'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final shopName = session.shopId == null
                          ? shops.where((s) => s.id == e.shopId).map((s) => s.name).join()
                          : '';
                      return Card(
                        child: ListTile(
                          title: Text(
                              '${ExpenseCategories.label(e.category)} • ${formatMoney(e.amount)}'),
                          subtitle: Text([
                            fmtDate(e.date),
                            if (shopName.isNotEmpty) shopName,
                            if (e.notes != null) e.notes!,
                          ].join(' • ')),
                          onTap: isAdmin(session.user) ? () => _form(context, ref, e.shopId, e) : null,
                          trailing: isAdmin(session.user)
                              ? IconButton(
                                  tooltip: 'إلغاء المصروف',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await confirmDialog(context, 'إلغاء المصروف',
                                        'يُلغى المصروف ويبقى في سجل العمليات. متابعة؟');
                                    if (ok && context.mounted) {
                                      await guard(
                                          context,
                                          () => ref
                                              .read(expenseRepositoryProvider)
                                              .voidExpense(session.user!.id, e.id));
                                    }
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
