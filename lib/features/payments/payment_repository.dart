import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';
import '../orders/order_status.dart';

class PaymentRow {
  const PaymentRow(this.payment, this.orderNo, this.customerName);
  final Payment payment;
  final String orderNo;
  final String customerName;
}

class StatementEntry {
  const StatementEntry({
    required this.date,
    required this.kind,
    required this.description,
    required this.amount,
    required this.balance,
  });
  final DateTime date;

  /// order (مدين على الزبون) | payment (دائن)
  final String kind;
  final String description;
  final int amount;
  final int balance;
}

class PaymentRepository {
  PaymentRepository(this.db);
  final AppDatabase db;

  static const methods = {'cash': 'نقداً', 'card': 'بطاقة', 'transfer': 'تحويل'};
  static String methodLabel(String k) => methods[k] ?? k;

  Future<bool> allowOverpay(int shopId) async =>
      (await db.getSetting('allow_overpay', shopId: shopId)) == '1';

  Future<void> setAllowOverpay(int actorId, int shopId, bool value) async {
    await requireAdmin(db, actorId);
    await db.setSetting('allow_overpay', value ? '1' : '0', shopId: shopId);
    await db.audit(
        userId: actorId,
        shopId: shopId,
        action: 'setting_allow_overpay',
        entity: 'setting',
        details: '$value');
  }

  Future<int> _paid(int orderId) async {
    final r = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
      'WHERE order_id = ? AND voided_at IS NULL',
      variables: [Variable.withInt(orderId)],
      readsFrom: {db.payments},
    ).getSingle();
    return r.read<int>('s');
  }

  Future<int> add({
    required int actorId,
    required int orderId,
    required int amount,
    required DateTime paidAt,
    String method = 'cash',
    String? notes,
  }) async {
    if (amount <= 0) throw AppException('المبلغ يجب أن يكون أكبر من صفر');
    if (!methods.containsKey(method)) throw AppException('طريقة دفع غير معروفة');
    await requirePayments(db, actorId);
    return db.transaction(() async {
      final o =
          await (db.select(db.orders)..where((x) => x.id.equals(orderId))).getSingle();
      if (o.status == OrderStatus.cancelled) {
        throw AppException('لا يمكن تسجيل دفعة على طلب ملغي');
      }
      final paid = await _paid(orderId);
      if (paid + amount > o.price && !await allowOverpay(o.shopId)) {
        throw AppException('المبلغ يتجاوز المتبقي (${formatMoney(o.price - paid)})');
      }
      final shop = await (db.select(db.shops)..where((s) => s.id.equals(o.shopId)))
          .getSingle();
      final prefix = shop.type == ShopTypes.women ? 'W' : 'M';
      final year = paidAt.year;
      final seq = await db.nextSequence('payment_seq_$year', shopId: o.shopId);
      final id = await db.into(db.payments).insert(PaymentsCompanion.insert(
            paymentNo: 'P-$prefix-$year-${seq.toString().padLeft(4, '0')}',
            orderId: orderId,
            customerId: o.customerId,
            shopId: o.shopId,
            amount: amount,
            paidAt: paidAt,
            method: Value(method),
            notes: Value(blankToNull(notes)),
            userId: Value(actorId),
          ));
      await db.audit(
          userId: actorId,
          shopId: o.shopId,
          action: 'add_payment',
          entity: 'payment',
          entityId: id,
          details: '${o.orderNo}: ${formatMoney(amount)}');
      return id;
    });
  }

  /// لا حذف للدفعات: الإبطال يحفظ السبب ويبقي الدفعة في السجل.
  /// لتعديل دفعة: أبطلها ثم سجّل الدفعة الصحيحة.
  Future<void> voidPayment(int actorId, int paymentId, String reason) async {
    if (reason.trim().isEmpty) throw AppException('سبب الإبطال مطلوب');
    await requireAdmin(db, actorId);
    await db.transaction(() async {
      final p = await (db.select(db.payments)..where((x) => x.id.equals(paymentId)))
          .getSingle();
      if (p.voidedAt != null) throw AppException('الدفعة مُبطلة مسبقاً');
      await (db.update(db.payments)..where((x) => x.id.equals(paymentId))).write(
          PaymentsCompanion(
              voidedAt: Value(DateTime.now()), voidReason: Value(reason.trim())));
      await db.audit(
          userId: actorId,
          shopId: p.shopId,
          action: 'void_payment',
          entity: 'payment',
          entityId: paymentId,
          details: '${formatMoney(p.amount)} - $reason');
    });
  }

  Stream<List<Payment>> watchForOrder(int orderId) {
    return (db.select(db.payments)
          ..where((p) => p.orderId.equals(orderId))
          ..orderBy([(p) => OrderingTerm.asc(p.id)]))
        .watch();
  }

  Stream<List<PaymentRow>> watchLog({int? shopId}) {
    final q = db.select(db.payments).join([
      innerJoin(db.orders, db.orders.id.equalsExp(db.payments.orderId)),
      innerJoin(db.customers, db.customers.id.equalsExp(db.payments.customerId)),
    ]);
    if (shopId != null) q.where(db.payments.shopId.equals(shopId));
    q.orderBy([
      OrderingTerm.desc(db.payments.paidAt),
      OrderingTerm.desc(db.payments.id),
    ]);
    return q.watch().map((rows) => [
          for (final r in rows)
            PaymentRow(r.readTable(db.payments), r.readTable(db.orders).orderNo,
                r.readTable(db.customers).name),
        ]);
  }

  /// كشف حساب الزبون: الطلبات (مدين) والدفعات (دائن) مع رصيد جارٍ.
  Stream<List<StatementEntry>> watchStatement(int customerId) {
    return db
        .customSelect(
          '''
SELECT date, kind, ref, amount FROM (
  SELECT o.order_date AS date, 'order' AS kind, o.order_no AS ref,
         o.price AS amount, o.id AS sid
  FROM orders o WHERE o.customer_id = ? AND o.status != 'cancelled'
  UNION ALL
  SELECT p.paid_at, 'payment', p.payment_no || ' - ' || o.order_no, p.amount, p.id
  FROM payments p JOIN orders o ON o.id = p.order_id
  WHERE p.customer_id = ? AND p.voided_at IS NULL AND o.status != 'cancelled'
) ORDER BY date, kind, sid
''',
          variables: [Variable.withInt(customerId), Variable.withInt(customerId)],
          readsFrom: {db.orders, db.payments},
        )
        .watch()
        .map((rows) {
      var balance = 0;
      final out = <StatementEntry>[];
      for (final r in rows) {
        final kind = r.read<String>('kind');
        final amount = r.read<int>('amount');
        balance += kind == 'order' ? amount : -amount;
        out.add(StatementEntry(
          date: DateTime.fromMillisecondsSinceEpoch(r.read<int>('date') * 1000),
          kind: kind,
          description: r.read<String>('ref'),
          amount: amount,
          balance: balance,
        ));
      }
      return out;
    });
  }
}
