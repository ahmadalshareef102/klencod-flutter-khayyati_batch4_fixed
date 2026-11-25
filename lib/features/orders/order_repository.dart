import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';
import 'order_status.dart';

class OrderWithCustomer {
  const OrderWithCustomer(this.order, this.customer);
  final Order order;
  final Customer customer;
}

class OrderInput {
  const OrderInput({
    required this.shopId,
    required this.customerId,
    required this.orderDate,
    required this.price,
    this.dueDate,
    this.garmentType,
    this.model,
    this.fabricType,
    this.color,
    this.details,
    this.imagePath,
    this.sketchPath,
    this.workerId,
    this.deposit = 0,
    this.notes,
    this.measurementId,
  });

  final int shopId;
  final int customerId;
  final DateTime orderDate;
  final DateTime? dueDate;
  final String? garmentType;
  final String? model;
  final String? fabricType;
  final String? color;
  final String? details;
  final String? imagePath;
  final String? sketchPath;
  final int? workerId;
  final int price;
  final int deposit;
  final String? notes;
  final int? measurementId;
}

class OrderRepository {
  OrderRepository(this.db);
  final AppDatabase db;

  JoinedSelectStatement<HasResultSet, dynamic> _joined() =>
      db.select(db.orders).join([
        innerJoin(db.customers, db.customers.id.equalsExp(db.orders.customerId)),
      ]);

  OrderWithCustomer _map(TypedResult r) =>
      OrderWithCustomer(r.readTable(db.orders), r.readTable(db.customers));

  /// [status] = مرحلة محددة. [activeOnly] = استبعاد المسلَّم والملغي.
  Stream<List<OrderWithCustomer>> watch({
    int? shopId,
    String? status,
    bool activeOnly = false,
    String query = '',
    bool? archived = false,
    bool excludeCancelled = false,
  }) {
    final q = _joined();
    Expression<bool> w =
        archived == null ? const Constant(true) : db.orders.isArchived.equals(archived);
    if (excludeCancelled) w = w & db.orders.status.equals(OrderStatus.cancelled).not();
    if (shopId != null) w = w & db.orders.shopId.equals(shopId);
    if (status != null) w = w & db.orders.status.equals(status);
    if (activeOnly) {
      w = w &
          db.orders.status
              .isNotIn([OrderStatus.delivered, OrderStatus.cancelled]);
    }
    q.where(w);
    q.orderBy([
      OrderingTerm.asc(db.orders.dueDate),
      OrderingTerm.desc(db.orders.id),
    ]);
    final t = query.trim().toLowerCase();
    return q.watch().map((rows) {
      final list = rows.map(_map).toList();
      if (t.isEmpty) return list;
      final phone = normalizePhone(t);
      return list
          .where((o) =>
              o.order.orderNo.toLowerCase().contains(t) ||
              o.customer.name.toLowerCase().contains(t) ||
              (phone.isNotEmpty && o.customer.phone.contains(phone)))
          .toList();
    });
  }

  Stream<List<OrderWithCustomer>> watchForCustomer(int customerId) {
    final q = _joined()
      ..where(db.orders.customerId.equals(customerId))
      ..orderBy([OrderingTerm.desc(db.orders.id)]);
    return q.watch().map((rows) => rows.map(_map).toList());
  }

  Stream<OrderWithCustomer?> watchOne(int orderId) {
    final q = _joined()..where(db.orders.id.equals(orderId));
    return q.watch().map((rows) => rows.isEmpty ? null : _map(rows.first));
  }

  Future<Order> getById(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  Stream<List<OrderStatusChange>> watchHistory(int orderId) {
    return (db.select(db.orderStatusHistory)
          ..where((h) => h.orderId.equals(orderId))
          ..orderBy([(h) => OrderingTerm.desc(h.id)]))
        .watch();
  }

  Future<String?> measurementSnapshot(int orderId) async {
    final row = await (db.select(db.orderMeasurements)
          ..where((m) => m.orderId.equals(orderId)))
        .getSingleOrNull();
    return row?.valuesJson;
  }

  Future<int> paidFor(int orderId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
      'WHERE order_id = ? AND voided_at IS NULL',
      variables: [Variable.withInt(orderId)],
      readsFrom: {db.payments},
    ).getSingle();
    return row.read<int>('s');
  }

  Stream<int> watchPaidFor(int orderId) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
          'WHERE order_id = ? AND voided_at IS NULL',
          variables: [Variable.withInt(orderId)],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((r) => r.read<int>('s'));
  }

  Stream<Map<int, int>> watchPaidByOrder() {
    return db
        .customSelect(
          'SELECT order_id, SUM(amount) AS s FROM payments '
          'WHERE voided_at IS NULL GROUP BY order_id',
          readsFrom: {db.payments},
        )
        .watch()
        .map((rows) => {
              for (final r in rows) r.read<int>('order_id'): r.read<int>('s'),
            });
  }

  Future<int> create(int actorId, OrderInput i) async {
    if (i.price < 0 || i.deposit < 0) {
      throw AppException('المبالغ لا يمكن أن تكون سالبة');
    }
    if (i.deposit > i.price) {
      throw AppException('العربون لا يمكن أن يتجاوز سعر الطلب');
    }
    return db.transaction(() async {
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(i.customerId)))
          .getSingleOrNull();
      if (customer == null || customer.shopId != i.shopId) {
        throw AppException('الزبون غير تابع لهذا المحل');
      }
      if (customer.isArchived) throw AppException('الزبون مؤرشف');
      final shop = await (db.select(db.shops)..where((s) => s.id.equals(i.shopId)))
          .getSingle();
      final prefix = shop.type == ShopTypes.women ? 'W' : 'M';
      final year = i.orderDate.year;
      final seq = await db.nextSequence('order_seq_$year', shopId: i.shopId);
      final orderNo = '$prefix-$year-${seq.toString().padLeft(4, '0')}';

      final id = await db.into(db.orders).insert(OrdersCompanion.insert(
            orderNo: orderNo,
            shopId: i.shopId,
            customerId: i.customerId,
            orderDate: i.orderDate,
            dueDate: Value(i.dueDate),
            garmentType: Value(blankToNull(i.garmentType)),
            model: Value(blankToNull(i.model)),
            fabricType: Value(blankToNull(i.fabricType)),
            color: Value(blankToNull(i.color)),
            details: Value(blankToNull(i.details)),
            imagePath: Value(i.imagePath),
            sketchPath: Value(i.sketchPath),
            workerId: Value(i.workerId),
            price: Value(i.price),
            deposit: Value(i.deposit),
            notes: Value(blankToNull(i.notes)),
          ));

      await db.into(db.orderStatusHistory).insert(
          OrderStatusHistoryCompanion.insert(
            orderId: id,
            newStatus: OrderStatus.newOrder,
            userId: Value(actorId),
            note: const Value('إنشاء الطلب'),
          ));

      if (i.measurementId != null) {
        final m = await (db.select(db.measurements)
              ..where((x) => x.id.equals(i.measurementId!)))
            .getSingleOrNull();
        if (m == null || m.customerId != i.customerId) {
          throw AppException('سجل المقاسات لا يتبع هذا الزبون');
        }
        // نسخة ثابتة: لا تتأثر بتعديل مقاسات الزبون لاحقاً.
        await db.into(db.orderMeasurements).insert(
            OrderMeasurementsCompanion.insert(orderId: id, valuesJson: m.valuesJson));
      }

      if (i.deposit > 0) {
        final pseq = await db.nextSequence('payment_seq_$year', shopId: i.shopId);
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              paymentNo: 'P-$prefix-$year-${pseq.toString().padLeft(4, '0')}',
              orderId: id,
              customerId: i.customerId,
              shopId: i.shopId,
              amount: i.deposit,
              paidAt: i.orderDate,
              notes: const Value('عربون عند إنشاء الطلب'),
              userId: Value(actorId),
            ));
      }

      await db.audit(
          userId: actorId,
          shopId: i.shopId,
          action: 'create_order',
          entity: 'order',
          entityId: id,
          details: orderNo);
      return id;
    });
  }

  /// تعديل بيانات الطلب. لا يمس الدفعات ولا المقاسات المحفوظة ولا الحالة.
  Future<void> update(int actorId, int orderId, OrderInput i) async {
    if (i.price < 0) throw AppException('المبالغ لا يمكن أن تكون سالبة');
    return db.transaction(() async {
      final old = await getById(orderId);
      if (OrderStatus.isTerminal(old.status)) {
        throw AppException('لا يمكن تعديل طلب مُسلَّم أو ملغي');
      }
      final paid = await paidFor(orderId);
      if (i.price < paid) {
        throw AppException(
            'السعر أقل من المبلغ المدفوع (${formatMoney(paid)}). عالج الدفعات أولاً');
      }
      await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
          OrdersCompanion(
            dueDate: Value(i.dueDate),
            garmentType: Value(blankToNull(i.garmentType)),
            model: Value(blankToNull(i.model)),
            fabricType: Value(blankToNull(i.fabricType)),
            color: Value(blankToNull(i.color)),
            details: Value(blankToNull(i.details)),
            imagePath: Value(i.imagePath),
            sketchPath: Value(i.sketchPath),
            workerId: Value(i.workerId),
            price: Value(i.price),
            notes: Value(blankToNull(i.notes)),
          ));
      await db.audit(
          userId: actorId,
          shopId: old.shopId,
          action: 'update_order',
          entity: 'order',
          entityId: orderId,
          details: old.price == i.price
              ? null
              : 'تعديل السعر: ${formatMoney(old.price)} → ${formatMoney(i.price)}');
    });
  }

  Future<void> changeStatus(
      int actorId, int orderId, String newStatus, String? note) async {
    if (!OrderStatus.all.contains(newStatus)) {
      throw AppException('حالة غير معروفة');
    }
    return db.transaction(() async {
      final o = await getById(orderId);
      if (OrderStatus.isTerminal(o.status)) {
        throw AppException('الطلب ${OrderStatus.label(o.status)} ولا يمكن تغيير حالته');
      }
      if (o.status == newStatus) throw AppException('الطلب بهذه الحالة بالفعل');
      if (newStatus == OrderStatus.cancelled && blankToNull(note) == null) {
        throw AppException('سبب الإلغاء مطلوب');
      }
      await (db.update(db.orders)..where((x) => x.id.equals(orderId)))
          .write(OrdersCompanion(status: Value(newStatus)));
      await db.into(db.orderStatusHistory).insert(
          OrderStatusHistoryCompanion.insert(
            orderId: orderId,
            oldStatus: Value(o.status),
            newStatus: newStatus,
            userId: Value(actorId),
            note: Value(blankToNull(note)),
          ));
      await db.audit(
          userId: actorId,
          shopId: o.shopId,
          action: 'change_order_status',
          entity: 'order',
          entityId: orderId,
          details: '${o.status} → $newStatus');
    });
  }

  Future<void> setArchived(int actorId, int orderId, bool archived) {
    return db.transaction(() async {
      final o = await getById(orderId);
      await (db.update(db.orders)..where((x) => x.id.equals(orderId)))
          .write(OrdersCompanion(isArchived: Value(archived)));
      await db.audit(
          userId: actorId,
          shopId: o.shopId,
          action: archived ? 'archive_order' : 'restore_order',
          entity: 'order',
          entityId: orderId);
    });
  }
}
