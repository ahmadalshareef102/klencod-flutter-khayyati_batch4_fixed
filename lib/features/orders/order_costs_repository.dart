import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';
import 'order_status.dart';

class OrderCostsRepository {
  OrderCostsRepository(this.db);
  final AppDatabase db;

  Stream<List<OrderCost>> watch(int orderId) {
    return (db.select(db.orderCosts)
          ..where((c) => c.orderId.equals(orderId))
          ..orderBy([(c) => OrderingTerm.asc(c.id)]))
        .watch();
  }

  /// أجر عامل (labor) أو تكلفة مباشرة أخرى (other).
  Future<int> add({
    required int actorId,
    required int orderId,
    required String kind,
    required int amount,
    String? description,
    int? workerId,
  }) async {
    if (kind != 'labor' && kind != 'other') throw AppException('نوع تكلفة غير صالح');
    if (amount <= 0) throw AppException('المبلغ يجب أن يكون أكبر من صفر');
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final o =
          await (db.select(db.orders)..where((x) => x.id.equals(orderId))).getSingle();
      if (o.status == OrderStatus.cancelled) {
        throw AppException('لا يمكن إضافة تكلفة لطلب ملغي');
      }
      final id = await db.into(db.orderCosts).insert(OrderCostsCompanion.insert(
            orderId: orderId,
            kind: kind,
            amount: amount,
            description: Value(blankToNull(description)),
            workerId: Value(workerId ?? o.workerId),
          ));
      await db.audit(
          userId: actorId,
          shopId: o.shopId,
          action: 'add_order_cost',
          entity: 'order',
          entityId: orderId,
          details: '$kind: ${formatMoney(amount)}');
      return id;
    });
  }

  /// عكس تكلفة بقيد سالب موثّق (لا حذف).
  Future<void> reverse(int actorId, int costId) async {
    await requireFinance(db, actorId);
    await db.transaction(() async {
      final c =
          await (db.select(db.orderCosts)..where((x) => x.id.equals(costId))).getSingle();
      if (c.kind == 'fabric') {
        throw AppException('تكلفة القماش تُعكس من خلال استرجاع الاستخدام');
      }
      if (c.amount < 0) throw AppException('هذا قيد عكسي');
      final dup = await (db.select(db.orderCosts)
            ..where((x) => x.reversesCostId.equals(costId)))
          .get();
      if (dup.isNotEmpty) throw AppException('تم عكس هذه التكلفة مسبقاً');
      await db.into(db.orderCosts).insert(OrderCostsCompanion.insert(
            orderId: c.orderId,
            kind: c.kind,
            amount: -c.amount,
            description: Value('عكس: ${c.description ?? ''}'),
            workerId: Value(c.workerId),
            reversesCostId: Value(costId),
          ));
      await db.audit(
          userId: actorId,
          action: 'reverse_order_cost',
          entity: 'order',
          entityId: c.orderId,
          details: formatMoney(c.amount));
    });
  }
}
