import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers_domain.dart';

class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key, required this.customerId});
  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerByIdProvider(customerId)).valueOrNull;
    final entries = ref.watch(statementProvider(customerId)).valueOrNull ?? const [];
    final balance = entries.isEmpty ? 0 : entries.last.balance;
    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب ${customer?.name ?? ''}')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: const Text('الرصيد المستحق على الزبون'),
              trailing: Text(formatMoney(balance),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: balance > 0 ? AppColors.warning : AppColors.success)),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('لا توجد حركات'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isOrder = e.kind == 'order';
                      return Card(
                        child: ListTile(
                          dense: true,
                          leading: Icon(isOrder ? Icons.receipt_long : Icons.payments_outlined,
                              color: isOrder ? AppColors.warning : AppColors.success),
                          title: Text('${isOrder ? 'طلب' : 'دفعة'} • ${e.description}'),
                          subtitle: Text(fmtDate(e.date)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${isOrder ? '+' : '−'}${formatMoney(e.amount)}'),
                              Text('الرصيد ${formatMoney(e.balance)}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
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
