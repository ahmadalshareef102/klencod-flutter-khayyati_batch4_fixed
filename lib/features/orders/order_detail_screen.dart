import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/image_store.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../data/db/app_database.dart';
import '../../core/text_utils.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import '../debts/debts_screen.dart';
import '../payments/payment_repository.dart';
import 'order_status.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  void _msg(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, String current, int remaining) async {
    final result = await showDialog<({String status, String? note})>(
      context: context,
      builder: (_) => _StatusDialog(current: current),
    );
    if (result == null || !context.mounted) return;
    if (result.status == OrderStatus.delivered && remaining > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('مبلغ متبقٍ'),
          content: Text('المتبقي على الزبون ${formatMoney(remaining)}. هل تريد تسليم الطلب؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسليم')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(orderRepositoryProvider).changeStatus(
          ref.read(sessionProvider).user!.id, orderId, result.status, result.note);
    } on AppException catch (e) {
      if (context.mounted) _msg(context, e.message);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, int paid) async {
    final ctrl = TextEditingController();
    final costs = ref.read(orderCostsProvider(orderId)).valueOrNull ?? const <OrderCost>[];
    final hasFabric = costs.any((c) => c.kind == 'fabric' && c.amount > 0 && c.reversesCostId == null) &&
        canManageFinance(ref.read(sessionProvider).user);
    var returnFabric = true;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: StatefulBuilder(
          builder: (ctx, setSt) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasFabric)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إرجاع الأقمشة المستخدمة للمخزون'),
                value: returnFabric,
                onChanged: (v) => setSt(() => returnFabric = v ?? true),
              ),
            if (paid > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('تنبيه: توجد دفعات بقيمة ${formatMoney(paid)} على هذا الطلب.'),
              ),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'سبب الإلغاء (مطلوب)'),
            ),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('إلغاء الطلب')),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || !context.mounted) return;
    try {
      final actor = ref.read(sessionProvider).user!.id;
      await ref
          .read(orderRepositoryProvider)
          .changeStatus(actor, orderId, OrderStatus.cancelled, reason);
      if (hasFabric && returnFabric) {
        await ref
            .read(inventoryRepositoryProvider)
            .reverseAllUsageForOrder(actor, orderId, reason: 'إلغاء الطلب');
      }
    } on AppException catch (e) {
      if (context.mounted) _msg(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(orderDetailProvider(orderId)).valueOrNull;
    if (data == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final o = data.order;
    final c = data.customer;
    final user = ref.watch(sessionProvider).user;
    final canEdit = user != null &&
        (user.role == Roles.admin || user.canCreateOrders) &&
        !OrderStatus.isTerminal(o.status);
    final paid = ref.watch(orderPaidProvider(orderId)).valueOrNull ?? 0;
    final remaining = o.price - paid;
    final history = ref.watch(orderHistoryProvider(orderId)).valueOrNull ?? const [];
    final measures = ref.watch(orderMeasurementProvider(orderId)).valueOrNull;
    final worker =
        o.workerId == null ? null : ref.watch(userByIdProvider(o.workerId!)).valueOrNull;
    final terminal = OrderStatus.isTerminal(o.status);
    final isLate = OrderStatus.isLate(o);
    final isWomen = ref.watch(shopTypeProvider(o.shopId)) == ShopTypes.women;
    final payments = ref.watch(orderPaymentsProvider(orderId)).valueOrNull ?? const <Payment>[];
    final costs = ref.watch(orderCostsProvider(orderId)).valueOrNull ?? const <OrderCost>[];
    final finance = canManageFinance(user);

    Widget row(String k, String? v) => v == null || v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 110,
                    child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
                Expanded(child: Text(v)),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(o.orderNo),
        actions: [
          IconButton(
            tooltip: 'طباعة / معاينة',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('الفاتورة'),
                      subtitle: const Text('A4 أو ورق حراري حسب إعدادات المحل'),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/invoice/${o.id}?kind=invoice');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: const Text('ورقة الطلب (للورشة)'),
                      subtitle: const Text('المقاسات والرسم وبيانات العميل'),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/invoice/${o.id}?kind=sheet');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/orders/${o.id}/edit'),
            ),
          if (user != null && user.role == Roles.admin)
            IconButton(
              tooltip: o.isArchived ? 'استعادة' : 'أرشفة',
              icon: Icon(o.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              onPressed: () async {
                await ref
                    .read(orderRepositoryProvider)
                    .setArchived(user.id, o.id, !o.isArchived);
                if (context.mounted && !o.isArchived) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              StatusChip(o.status),
              if (isLate) ...[
                const SizedBox(width: 8),
                const Text('متأخر',
                    style: TextStyle(
                        color: AppColors.warning, fontWeight: FontWeight.bold)),
              ],
              if (o.isArchived) ...[
                const SizedBox(width: 8),
                const Text('مؤرشف'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  row('الزبون', '${c.name} • ${c.phone}'),
                  row('تاريخ الطلب', fmtDate(o.orderDate)),
                  row('موعد التسليم', o.dueDate == null ? null : fmtDate(o.dueDate!)),
                  row('نوع التفصيل', o.garmentType),
                  row('الموديل', o.model),
                  row('القماش', o.fabricType),
                  row('اللون', o.color),
                  row(isWomen ? 'تابع التفصيل' : 'التفاصيل', o.details),
                  row('العامل', worker?.fullName),
                  row('ملاحظات', o.notes),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Money('السعر', formatMoney(o.price)),
                  _Money(isWomen ? 'الواصل' : 'المدفوع', formatMoney(paid), color: AppColors.success),
                  _Money('المتبقي', formatMoney(remaining),
                      color: remaining > 0 ? AppColors.warning : null),
                ],
              ),
            ),
          ),
          if (o.imagePath != null) ...[
            const SizedBox(height: 8),
            StoredImage(path: o.imagePath!, height: 220),
          ],
          if (o.sketchPath != null) ...[
            const SizedBox(height: 8),
            Text('الرسم', style: Theme.of(context).textTheme.titleSmall),
            StoredImage(path: o.sketchPath!, height: 220),
          ],
          const SizedBox(height: 8),
          _PaymentsCard(orderId: orderId, payments: payments, canAdd: canTakePayments(user) && o.status != OrderStatus.cancelled, isAdminUser: isAdmin(user), remaining: remaining),
          if (finance)
            _CostsCard(orderId: orderId, shopId: o.shopId, costs: costs, closed: terminal),
          if (measures != null && measures.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المقاسات (نسخة ثابتة)',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in measures.entries)
                          Chip(label: Text('${e.key}: ${e.value}')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('سجل الطلب', style: Theme.of(context).textTheme.titleSmall),
          for (final h in history)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, size: 12, color: OrderStatus.color(h.newStatus)),
              title: Text(h.oldStatus == null
                  ? OrderStatus.label(h.newStatus)
                  : '${OrderStatus.label(h.oldStatus!)} ← ${OrderStatus.label(h.newStatus)}'),
              subtitle: Text(
                  [fmtDateTime(h.changedAt), if (h.note != null) h.note!].join(' • ')),
            ),
          if (!terminal) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _changeStatus(context, ref, o.status, remaining),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('تغيير الحالة'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => _cancel(context, ref, paid),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الطلب'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money(this.label, this.value, {this.color});
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

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.current});
  final String current;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  String? _selected;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = OrderStatus.all
        .where((s) => s != widget.current && s != OrderStatus.cancelled)
        .toList();
    return AlertDialog(
      title: const Text('تغيير الحالة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in options)
              ListTile(
                dense: true,
                selected: _selected == s,
                leading: Icon(_selected == s
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked),
                title: Text(OrderStatus.label(s)),
                onTap: () => setState(() => _selected = s),
              ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        TextButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, (status: _selected!, note: _note.text)),
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}


class _PaymentsCard extends ConsumerWidget {
  const _PaymentsCard({
    required this.orderId,
    required this.payments,
    required this.canAdd,
    required this.isAdminUser,
    required this.remaining,
  });
  final int orderId;
  final List<Payment> payments;
  final bool canAdd;
  final bool isAdminUser;
  final int remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('الدفعات', style: Theme.of(context).textTheme.titleSmall)),
                if (canAdd)
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('تسجيل دفعة'),
                    onPressed: () => showFormDialog(
                      context,
                      title: 'تسجيل دفعة',
                      note: remaining > 0 ? 'المتبقي ${formatMoney(remaining)}' : null,
                      items: [
                        const MoneyItem('المبلغ'),
                        const DateItem('التاريخ'),
                        const DropItem('طريقة الدفع', PaymentRepository.methods, initial: 'cash'),
                        const TextItem('ملاحظات'),
                      ],
                      onSubmit: (v) async {
                        await ref.read(paymentRepositoryProvider).add(
                            actorId: ref.read(sessionProvider).user!.id,
                            orderId: orderId,
                            amount: v[0]! as int,
                            paidAt: v[1]! as DateTime,
                            method: (v[2] as String?) ?? 'cash',
                            notes: v[3] as String?);
                      },
                    ),
                  ),
              ],
            ),
            if (payments.isEmpty) const Text('لا توجد دفعات'),
            for (final p in payments)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(formatMoney(p.amount),
                    style: p.voidedAt != null
                        ? const TextStyle(decoration: TextDecoration.lineThrough)
                        : null),
                subtitle: Text([
                  p.paymentNo,
                  fmtDate(p.paidAt),
                  PaymentRepository.methodLabel(p.method),
                  if (p.notes != null) p.notes!,
                  if (p.voidedAt != null) 'مُبطلة: ${p.voidReason ?? ''}',
                ].join(' • ')),
                trailing: (p.voidedAt == null && isAdminUser)
                    ? IconButton(
                        tooltip: 'إبطال',
                        icon: const Icon(Icons.block),
                        onPressed: () => voidPaymentFlow(context, ref, p.id),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _CostsCard extends ConsumerWidget {
  const _CostsCard({
    required this.orderId,
    required this.shopId,
    required this.costs,
    required this.closed,
  });
  final int orderId;
  final int shopId;
  final List<OrderCost> costs;
  final bool closed;

  static const _kinds = {'labor': 'أجر عامل', 'other': 'تكلفة أخرى'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.read(sessionProvider).user!.id;
    final reversed = costs.map((c) => c.reversesCostId).whereType<int>().toSet();
    final total = costs.fold<int>(0, (s, c) => s + c.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تكاليف الطلب (إجمالي ${formatMoney(total)})',
                style: Theme.of(context).textTheme.titleSmall),
            if (!closed)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.checkroom_outlined),
                    label: const Text('خصم قماش'),
                    onPressed: () {
                      final fabrics = ref.read(shopFabricsProvider(shopId)).valueOrNull ?? const <Fabric>[];
                      showFormDialog(
                        context,
                        title: 'خصم قماش من المخزون',
                        note: 'يُخصم مرة واحدة لكل مادة، وتُسجَّل تكلفته على الطلب.',
                        items: [
                          DropItem(
                              'المادة',
                              {
                                for (final f in fabrics)
                                  '${f.id}': '${f.name}${f.color == null ? '' : ' - ${f.color}'} (${f.quantity} ${f.unit})'
                              },
                              required: true),
                          const TextItem('الكمية المستخدمة', required: true, number: true),
                        ],
                        onSubmit: (v) async {
                          final q = parseDecimal(v[1]! as String);
                          if (q == null) throw AppException('كمية غير صحيحة');
                          await ref.read(inventoryRepositoryProvider).useOnOrder(
                              actorId: actor,
                              orderId: orderId,
                              fabricId: int.parse(v[0]! as String),
                              quantity: q);
                        },
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('أجرة / تكلفة'),
                    onPressed: () {
                      final workers = ref.read(shopWorkersProvider(shopId)).valueOrNull ?? const <User>[];
                      showFormDialog(
                        context,
                        title: 'إضافة تكلفة',
                        items: [
                          const DropItem('النوع', _kinds, initial: 'labor', required: true),
                          const MoneyItem('المبلغ'),
                          DropItem('العامل', {for (final w in workers) '${w.id}': w.fullName}),
                          const TextItem('الوصف'),
                        ],
                        onSubmit: (v) async {
                          await ref.read(orderCostsRepositoryProvider).add(
                              actorId: actor,
                              orderId: orderId,
                              kind: v[0]! as String,
                              amount: v[1]! as int,
                              workerId: v[2] == null ? null : int.parse(v[2]! as String),
                              description: v[3] as String?);
                        },
                      );
                    },
                  ),
                ],
              ),
            for (final c in costs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${c.kind == 'fabric' ? 'قماش' : c.kind == 'labor' ? 'أجر' : 'أخرى'} • ${formatMoney(c.amount)}',
                    style: reversed.contains(c.id) || c.amount < 0
                        ? const TextStyle(color: Colors.grey)
                        : null),
                subtitle: Text([fmtDate(c.createdAt), if (c.description != null) c.description!].join(' • ')),
                trailing: (!closed && c.amount > 0 && !reversed.contains(c.id))
                    ? IconButton(
                        tooltip: c.kind == 'fabric' ? 'استرجاع للمخزون' : 'عكس',
                        icon: const Icon(Icons.undo),
                        onPressed: () async {
                          final ok = await confirmDialog(
                              context,
                              c.kind == 'fabric' ? 'استرجاع القماش' : 'عكس التكلفة',
                              c.kind == 'fabric'
                                  ? 'تعود الكمية للمخزون بحركة موثقة. متابعة؟'
                                  : 'يُضاف قيد عكسي موثّق. متابعة؟');
                          if (ok && context.mounted) {
                            await guard(context, () async {
                              if (c.kind == 'fabric') {
                                await ref.read(inventoryRepositoryProvider).reverseUsage(actor, c.id);
                              } else {
                                await ref.read(orderCostsRepositoryProvider).reverse(actor, c.id);
                              }
                            });
                          }
                        },
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
