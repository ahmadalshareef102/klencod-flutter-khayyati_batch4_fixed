import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!canManageFinance(session.user)) {
      return Scaffold(
          appBar: AppBar(title: const Text('الموردون')),
          body: const Center(child: Text('ليست لديك صلاحية')));
    }
    final list = ref.watch(suppliersProvider).valueOrNull ?? const [];
    final bal = ref.watch(supplierBalancesProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('الموردون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final shopId = session.shopId;
          if (shopId == null) {
            showMsg(context, 'اختر محلاً من الصفحة الرئيسية أولاً');
            return;
          }
          showFormDialog(
            context,
            title: 'مورد جديد',
            items: const [
              TextItem('الاسم', required: true),
              TextItem('الهاتف'),
              TextItem('العنوان'),
              TextItem('ملاحظات', maxLines: 2),
            ],
            onSubmit: (v) async {
              await ref.read(supplierRepositoryProvider).create(
                  actorId: session.user!.id,
                  shopId: shopId,
                  name: v[0]! as String,
                  phone: v[1] as String?,
                  address: v[2] as String?,
                  notes: v[3] as String?);
            },
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('مورد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'بحث بالاسم أو الهاتف', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => ref.read(supplierSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('لا يوجد موردون'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final s = list[i];
                      final due = bal[s.id]?.due ?? 0;
                      return Card(
                        child: ListTile(
                          title: Text(s.name),
                          subtitle: Text(s.phone ?? ''),
                          trailing: Text(due > 0 ? 'مستحق ${formatMoney(due)}' : 'لا مستحقات',
                              style: TextStyle(color: due > 0 ? AppColors.warning : null)),
                          onTap: () => context.push('/suppliers/${s.id}'),
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
