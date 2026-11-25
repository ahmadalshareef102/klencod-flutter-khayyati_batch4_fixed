import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'inventory_repository.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!canManageFinance(session.user)) {
      return Scaffold(
          appBar: AppBar(title: const Text('المخزون')),
          body: const Center(child: Text('ليست لديك صلاحية')));
    }
    final list = ref.watch(fabricsProvider).valueOrNull ?? const [];
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final low = list.where(InventoryRepository.isLow).length;

    return Scaffold(
      appBar: AppBar(title: const Text('المخزون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final shopId = session.shopId;
          if (shopId == null) {
            showMsg(context, 'اختر محلاً من الصفحة الرئيسية أولاً');
            return;
          }
          showFormDialog(
            context,
            title: 'مادة جديدة',
            note: 'تبدأ الكمية من صفر؛ سجّل الكمية عبر «شراء» أو «استلام».',
            items: const [
              TextItem('الاسم', required: true),
              TextItem('النوع'),
              TextItem('اللون'),
              TextItem('الرمز'),
              TextItem('الوحدة', initial: 'متر'),
              TextItem('حد التنبيه (الكمية)', number: true),
              TextItem('ملاحظات', maxLines: 2),
            ],
            onSubmit: (v) async {
              await ref.read(inventoryRepositoryProvider).createFabric(
                    actorId: session.user!.id,
                    shopId: shopId,
                    name: v[0]! as String,
                    type: v[1] as String?,
                    color: v[2] as String?,
                    code: v[3] as String?,
                    unit: v[4]! as String,
                    alertLevel: parseDecimal(v[5]! as String) ?? 0,
                    notes: v[6] as String?,
                  );
            },
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('مادة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'بحث بالاسم أو اللون أو الرمز', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => ref.read(fabricSearchProvider.notifier).state = v,
            ),
          ),
          if (low > 0)
            Card(
              color: AppColors.warning.withValues(alpha: 0.15),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                title: Text('$low مادة تحت حد التنبيه'),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('لا توجد مواد'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final f = list[i];
                      final isLow = InventoryRepository.isLow(f);
                      final shopName = session.shopId == null
                          ? shops.where((s) => s.id == f.shopId).map((s) => s.name).join()
                          : '';
                      return Card(
                        child: ListTile(
                          title: Text([f.name, if (f.color != null) f.color!].join(' • ')),
                          subtitle: Text([
                            if (f.code != null) f.code!,
                            if (shopName.isNotEmpty) shopName,
                          ].join(' • ')),
                          trailing: Text('${f.quantity} ${f.unit}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isLow ? AppColors.warning : null)),
                          onTap: () => context.push('/inventory/${f.id}'),
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
