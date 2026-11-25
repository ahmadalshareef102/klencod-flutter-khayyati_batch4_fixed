import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'inventory_repository.dart';

class FabricDetailScreen extends ConsumerWidget {
  const FabricDetailScreen({super.key, required this.fabricId});
  final int fabricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(fabricProvider(fabricId)).valueOrNull;
    final user = ref.watch(sessionProvider).user;
    if (f == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final txns = ref.watch(fabricTxnsProvider(fabricId)).valueOrNull ?? const <TxnRow>[];
    final repo = ref.read(inventoryRepositoryProvider);
    final actor = user!.id;
    final isLow = InventoryRepository.isLow(f);

    Widget action(String label, IconData icon, VoidCallback onTap) => ActionChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          onPressed: onTap,
        );

    Future<void> qtyDialog(String title, String type) => showFormDialog(
          context,
          title: title,
          items: const [
            TextItem('الكمية', required: true, number: true),
            TextItem('ملاحظات'),
          ],
          onSubmit: (v) async {
            final q = parseDecimal(v[0]! as String);
            if (q == null) throw AppException('كمية غير صحيحة');
            await repo.adjust(
                actorId: actor,
                fabricId: fabricId,
                type: type,
                quantity: q,
                notes: v[1] as String?);
          },
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(f.name),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showFormDialog(
              context,
              title: 'تعديل المادة',
              items: [
                TextItem('الاسم', initial: f.name, required: true),
                TextItem('النوع', initial: f.type ?? ''),
                TextItem('اللون', initial: f.color ?? ''),
                TextItem('الرمز', initial: f.code ?? ''),
                TextItem('الوحدة', initial: f.unit),
                TextItem('حد التنبيه', initial: '${f.alertLevel}', number: true),
                TextItem('ملاحظات', initial: f.notes ?? '', maxLines: 2),
              ],
              onSubmit: (v) => repo.updateFabric(
                actorId: actor,
                id: f.id,
                name: v[0]! as String,
                type: v[1] as String?,
                color: v[2] as String?,
                code: v[3] as String?,
                supplierId: f.supplierId,
                unit: v[4]! as String,
                alertLevel: parseDecimal(v[5]! as String) ?? 0,
                notes: v[6] as String?,
              ),
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
                  Text('الكمية: ${f.quantity} ${f.unit}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: isLow ? AppColors.warning : null)),
                  if (isLow)
                    const Text('أقل من أو يساوي حد التنبيه',
                        style: TextStyle(color: AppColors.warning)),
                  Text('سعر الوحدة (متوسط مرجّح): ${formatMoney(f.unitCost)}'),
                  Text('قيمة المخزون: ${formatMoney((f.quantity * f.unitCost).round())}'),
                  if (f.type != null) Text('النوع: ${f.type}'),
                  if (f.color != null) Text('اللون: ${f.color}'),
                  if (f.code != null) Text('الرمز: ${f.code}'),
                  if (f.notes != null) Text(f.notes!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              action('شراء', Icons.shopping_cart_outlined, () {
                final suppliers = ref.read(shopSuppliersProvider(f.shopId)).valueOrNull ?? const [];
                showFormDialog(
                  context,
                  title: 'شراء ${f.name}',
                  note: 'مع مورد: المبلغ غير المدفوع يُسجَّل مستحقاً للمورد (شراء آجل). '
                      'بدون مورد: يُعتبر الشراء نقدياً.',
                  items: [
                    const TextItem('الكمية', required: true, number: true),
                    const MoneyItem('سعر الوحدة'),
                    DropItem('المورد', {for (final s in suppliers) '${s.id}': s.name}),
                    const MoneyItem('المدفوع الآن (للمورد)', required: false),
                    const TextItem('ملاحظات'),
                  ],
                  onSubmit: (v) async {
                    final q = parseDecimal(v[0]! as String);
                    if (q == null) throw AppException('كمية غير صحيحة');
                    final sid = v[2] == null ? null : int.parse(v[2]! as String);
                    final unitCost = v[1]! as int;
                    final total = (q * unitCost).round();
                    // بدون مورد: دفع نقدي كامل. مع مورد: كما أدخل المستخدم.
                    final paid = sid == null ? total : (v[3]! as int);
                    await repo.purchase(
                        actorId: actor,
                        fabricId: fabricId,
                        quantity: q,
                        unitCost: unitCost,
                        supplierId: sid,
                        paid: paid,
                        notes: v[4] as String?);
                  },
                );
              }),
              action('استلام', Icons.move_to_inbox_outlined, () => qtyDialog('استلام ${f.name}', InventoryTypes.receive)),
              action('خصم', Icons.remove_circle_outline, () => qtyDialog('خصم من ${f.name}', InventoryTypes.deduct)),
              action('هالك', Icons.delete_sweep_outlined, () => qtyDialog('هالك ${f.name}', InventoryTypes.waste)),
              if (isAdmin(user))
                action('نقل لمحل آخر', Icons.swap_horiz, () {
                  final shops = (ref.read(shopsProvider).valueOrNull ?? const <Shop>[])
                      .where((s) => s.id != f.shopId)
                      .toList();
                  showFormDialog(
                    context,
                    title: 'نقل ${f.name}',
                    items: [
                      DropItem('إلى', {for (final s in shops) '${s.id}': s.name}, required: true),
                      const TextItem('الكمية', required: true, number: true),
                      const TextItem('ملاحظات'),
                    ],
                    onSubmit: (v) async {
                      final q = parseDecimal(v[1]! as String);
                      if (q == null) throw AppException('كمية غير صحيحة');
                      await repo.transfer(
                          actorId: actor,
                          fabricId: fabricId,
                          toShopId: int.parse(v[0]! as String),
                          quantity: q,
                          notes: v[2] as String?);
                    },
                  );
                }),
            ],
          ),
          const SizedBox(height: 16),
          Text('سجل الحركة', style: Theme.of(context).textTheme.titleSmall),
          if (txns.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حركات')),
          for (final t in txns)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  InventoryTypes.increases(t.txn.type) ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: InventoryTypes.increases(t.txn.type) ? AppColors.success : AppColors.warning),
              title: Text('${InventoryTypes.label(t.txn.type)} • ${t.txn.quantity} ${f.unit}'),
              subtitle: Text([
                fmtDateTime(t.txn.createdAt),
                if (t.txn.unitCost > 0) 'سعر الوحدة ${formatMoney(t.txn.unitCost)}',
                if (t.txn.notes != null) t.txn.notes!,
              ].join(' • ')),
            ),
        ],
      ),
    );
  }
}
