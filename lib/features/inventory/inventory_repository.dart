import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';
import '../orders/order_status.dart';

class InventoryTypes {
  static const purchase = 'purchase';
  static const receive = 'receive';
  static const deduct = 'deduct';
  static const usage = 'usage';
  static const waste = 'waste';
  static const transferIn = 'transfer_in';
  static const transferOut = 'transfer_out';
  static const usageReversal = 'usage_reversal';

  static const labels = {
    purchase: 'شراء',
    receive: 'استلام',
    deduct: 'خصم',
    usage: 'استخدام لطلب',
    waste: 'هالك',
    transferIn: 'نقل وارد',
    transferOut: 'نقل صادر',
    usageReversal: 'استرجاع استخدام',
  };
  static String label(String t) => labels[t] ?? t;

  /// الحركات التي تزيد الكمية.
  static bool increases(String t) =>
      t == purchase || t == receive || t == transferIn || t == usageReversal;
}

class TxnRow {
  const TxnRow(this.txn, this.fabricName);
  final InventoryTransaction txn;
  final String fabricName;
}

double _r3(double x) => double.parse(x.toStringAsFixed(3));

class InventoryRepository {
  InventoryRepository(this.db);
  final AppDatabase db;

  // ---------- المواد ----------
  Stream<List<Fabric>> watchFabrics({int? shopId, String query = '', bool archived = false}) {
    final t = query.trim().toLowerCase();
    return (db.select(db.fabrics)
          ..where((f) {
            Expression<bool> w = f.isArchived.equals(archived);
            if (shopId != null) w = w & f.shopId.equals(shopId);
            return w;
          })
          ..orderBy([(f) => OrderingTerm.asc(f.name)]))
        .watch()
        .map((l) => t.isEmpty
            ? l
            : l
                .where((f) =>
                    f.name.toLowerCase().contains(t) ||
                    (f.code ?? '').toLowerCase().contains(t) ||
                    (f.color ?? '').toLowerCase().contains(t))
                .toList());
  }

  Stream<Fabric?> watchFabric(int id) =>
      (db.select(db.fabrics)..where((f) => f.id.equals(id))).watchSingleOrNull();

  Future<Fabric> getFabric(int id) =>
      (db.select(db.fabrics)..where((f) => f.id.equals(id))).getSingle();

  static bool isLow(Fabric f) => f.alertLevel > 0 && f.quantity <= f.alertLevel;

  Future<int> createFabric({
    required int actorId,
    required int shopId,
    required String name,
    String? type,
    String? color,
    String? code,
    int? supplierId,
    String unit = 'متر',
    int unitCost = 0,
    double alertLevel = 0,
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw AppException('اسم المادة مطلوب');
    if (unitCost < 0 || alertLevel < 0) throw AppException('قيمة غير صحيحة');
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final id = await db.into(db.fabrics).insert(FabricsCompanion.insert(
            shopId: shopId,
            name: name.trim(),
            type: Value(blankToNull(type)),
            color: Value(blankToNull(color)),
            code: Value(blankToNull(code)),
            supplierId: Value(supplierId),
            unit: Value(unit.trim().isEmpty ? 'متر' : unit.trim()),
            unitCost: Value(unitCost),
            alertLevel: Value(alertLevel),
            notes: Value(blankToNull(notes)),
          ));
      await db.audit(
          userId: actorId,
          shopId: shopId,
          action: 'create_fabric',
          entity: 'fabric',
          entityId: id,
          details: name.trim());
      return id;
    });
  }

  Future<void> updateFabric({
    required int actorId,
    required int id,
    required String name,
    String? type,
    String? color,
    String? code,
    int? supplierId,
    required String unit,
    required double alertLevel,
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw AppException('اسم المادة مطلوب');
    await requireFinance(db, actorId);
    await db.transaction(() async {
      final f = await getFabric(id);
      await (db.update(db.fabrics)..where((x) => x.id.equals(id))).write(FabricsCompanion(
        name: Value(name.trim()),
        type: Value(blankToNull(type)),
        color: Value(blankToNull(color)),
        code: Value(blankToNull(code)),
        supplierId: Value(supplierId),
        unit: Value(unit.trim().isEmpty ? 'متر' : unit.trim()),
        alertLevel: Value(alertLevel),
        notes: Value(blankToNull(notes)),
      ));
      await db.audit(
          userId: actorId,
          shopId: f.shopId,
          action: 'update_fabric',
          entity: 'fabric',
          entityId: id);
    });
  }

  Future<void> setArchived(int actorId, int id, bool archived) async {
    await requireFinance(db, actorId);
    final f = await getFabric(id);
    await (db.update(db.fabrics)..where((x) => x.id.equals(id)))
        .write(FabricsCompanion(isArchived: Value(archived)));
    await db.audit(
        userId: actorId,
        shopId: f.shopId,
        action: archived ? 'archive_fabric' : 'restore_fabric',
        entity: 'fabric',
        entityId: id);
  }

  // ---------- الحركات ----------
  /// تطبيق حركة داخل transaction قائمة. الكمية دائماً موجبة، والاتجاه حسب النوع.
  Future<int> _apply({
    required int actorId,
    required Fabric fabric,
    required String type,
    required double quantity,
    required int unitCost,
    int? orderId,
    int? supplierId,
    int? reversesTxnId,
    String? notes,
  }) async {
    final q = _r3(quantity);
    if (q <= 0) throw AppException('الكمية يجب أن تكون أكبر من صفر');
    final fresh = await getFabric(fabric.id);
    final newQty = _r3(
        InventoryTypes.increases(type) ? fresh.quantity + q : fresh.quantity - q);
    if (newQty < 0) {
      throw AppException(
          'الكمية غير كافية. المتاح ${fresh.quantity} ${fresh.unit}');
    }
    await (db.update(db.fabrics)..where((x) => x.id.equals(fabric.id)))
        .write(FabricsCompanion(quantity: Value(newQty)));
    return db.into(db.inventoryTransactions).insert(
        InventoryTransactionsCompanion.insert(
          fabricId: fabric.id,
          shopId: fresh.shopId,
          type: type,
          quantity: q,
          unitCost: Value(unitCost),
          supplierId: Value(supplierId),
          orderId: Value(orderId),
          reversesTxnId: Value(reversesTxnId),
          notes: Value(blankToNull(notes)),
          userId: Value(actorId),
        ));
  }

  /// شراء: يزيد المخزون ويحدّث سعر الوحدة بمتوسط مرجّح.
  /// مع مورد: [paid] هو المدفوع فوراً والباقي يُسجَّل مستحقاً للمورد.
  /// بدون مورد: يُعتبر الشراء نقدياً بالكامل.
  Future<int> purchase({
    required int actorId,
    required int fabricId,
    required double quantity,
    required int unitCost,
    int? supplierId,
    int paid = 0,
    String? notes,
  }) async {
    if (unitCost <= 0) throw AppException('سعر الوحدة يجب أن يكون أكبر من صفر');
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final f = await getFabric(fabricId);
      final total = (_r3(quantity) * unitCost).round();
      if (paid < 0 || paid > total) {
        throw AppException('المدفوع يجب أن يكون بين 0 و${formatMoney(total)}');
      }
      final oldValue = f.quantity * f.unitCost;
      final newQty = f.quantity + _r3(quantity);
      final avg = newQty <= 0 ? unitCost : ((oldValue + total) / newQty).round();
      final id = await _apply(
        actorId: actorId,
        fabric: f,
        type: InventoryTypes.purchase,
        quantity: quantity,
        unitCost: unitCost,
        supplierId: supplierId,
        notes: notes,
      );
      await (db.update(db.fabrics)..where((x) => x.id.equals(f.id)))
          .write(FabricsCompanion(unitCost: Value(avg)));
      if (supplierId != null && paid > 0) {
        await db.into(db.supplierPayments).insert(SupplierPaymentsCompanion.insert(
              supplierId: supplierId,
              amount: paid,
              paidAt: DateTime.now(),
              notes: const Value('دفعة عند الشراء'),
              userId: Value(actorId),
            ));
      }
      await db.audit(
          userId: actorId,
          shopId: f.shopId,
          action: 'inventory_purchase',
          entity: 'inventory',
          entityId: id,
          details: '${f.name} × $quantity = ${formatMoney(total)}');
      return id;
    });
  }

  /// استلام/خصم/هالك. الهالك والخصم يُسجَّلان بتكلفة الوحدة الحالية.
  Future<int> adjust({
    required int actorId,
    required int fabricId,
    required String type,
    required double quantity,
    String? notes,
  }) async {
    if (type != InventoryTypes.receive &&
        type != InventoryTypes.deduct &&
        type != InventoryTypes.waste) {
      throw AppException('نوع حركة غير صالح');
    }
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final f = await getFabric(fabricId);
      final id = await _apply(
          actorId: actorId,
          fabric: f,
          type: type,
          quantity: quantity,
          unitCost: f.unitCost,
          notes: notes);
      await db.audit(
          userId: actorId,
          shopId: f.shopId,
          action: 'inventory_$type',
          entity: 'inventory',
          entityId: id,
          details: '${f.name} × $quantity');
      return id;
    });
  }

  /// نقل بين المحلين (للمدير). تُنشأ المادة في المحل الوجهة إن لم توجد.
  Future<void> transfer({
    required int actorId,
    required int fabricId,
    required int toShopId,
    required double quantity,
    String? notes,
  }) async {
    await requireAdmin(db, actorId);
    await db.transaction(() async {
      final src = await getFabric(fabricId);
      if (src.shopId == toShopId) throw AppException('اختر المحل الآخر');
      final existing = await (db.select(db.fabrics)
            ..where((f) =>
                f.shopId.equals(toShopId) &
                f.name.equals(src.name) &
                f.unit.equals(src.unit) &
                f.isArchived.equals(false)))
          .get();
      final dst = existing.where((f) => f.color == src.color && f.code == src.code);
      Fabric target;
      if (dst.isNotEmpty) {
        target = dst.first;
      } else {
        final id = await db.into(db.fabrics).insert(FabricsCompanion.insert(
              shopId: toShopId,
              name: src.name,
              type: Value(src.type),
              color: Value(src.color),
              code: Value(src.code),
              unit: Value(src.unit),
              unitCost: Value(src.unitCost),
              alertLevel: Value(src.alertLevel),
            ));
        target = await getFabric(id);
      }
      final q = _r3(quantity);
      await _apply(
          actorId: actorId,
          fabric: src,
          type: InventoryTypes.transferOut,
          quantity: q,
          unitCost: src.unitCost,
          notes: notes);
      final oldValue = target.quantity * target.unitCost;
      final newQty = target.quantity + q;
      final avg = ((oldValue + q * src.unitCost) / newQty).round();
      await _apply(
          actorId: actorId,
          fabric: target,
          type: InventoryTypes.transferIn,
          quantity: q,
          unitCost: src.unitCost,
          notes: notes);
      await (db.update(db.fabrics)..where((x) => x.id.equals(target.id)))
          .write(FabricsCompanion(unitCost: Value(avg)));
      await db.audit(
          userId: actorId,
          shopId: src.shopId,
          action: 'inventory_transfer',
          entity: 'fabric',
          entityId: fabricId,
          details: '${src.name} × $q → محل $toShopId');
    });
  }

  // ---------- الربط بالطلبات ----------
  /// يخصم القماش من المخزون مرة واحدة لكل (طلب، مادة) ويسجّل تكلفة الاستخدام.
  /// لتكرار الخصم يجب استرجاع الاستخدام السابق أولاً.
  Future<int> useOnOrder({
    required int actorId,
    required int orderId,
    required int fabricId,
    required double quantity,
  }) async {
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final o =
          await (db.select(db.orders)..where((x) => x.id.equals(orderId))).getSingle();
      if (OrderStatus.isTerminal(o.status)) {
        throw AppException('لا يمكن ربط قماش بطلب مُسلَّم أو ملغي');
      }
      final f = await getFabric(fabricId);
      if (f.shopId != o.shopId) throw AppException('المادة تتبع المحل الآخر');
      final prev = await (db.select(db.inventoryTransactions)
            ..where((t) =>
                t.orderId.equals(orderId) &
                t.fabricId.equals(fabricId) &
                t.type.equals(InventoryTypes.usage)))
          .get();
      for (final t in prev) {
        final reversed = await (db.select(db.inventoryTransactions)
              ..where((r) => r.reversesTxnId.equals(t.id)))
            .get();
        if (reversed.isEmpty) {
          throw AppException(
              'خُصمت هذه المادة لهذا الطلب مسبقاً. استرجع الاستخدام السابق أولاً');
        }
      }
      final q = _r3(quantity);
      final txnId = await _apply(
          actorId: actorId,
          fabric: f,
          type: InventoryTypes.usage,
          quantity: q,
          unitCost: f.unitCost,
          orderId: orderId);
      final cost = (q * f.unitCost).round();
      final costId = await db.into(db.orderCosts).insert(OrderCostsCompanion.insert(
            orderId: orderId,
            kind: 'fabric',
            amount: cost,
            description: Value('${f.name} × $q ${f.unit}'),
            inventoryTxnId: Value(txnId),
          ));
      await db.audit(
          userId: actorId,
          shopId: o.shopId,
          action: 'use_fabric_on_order',
          entity: 'order',
          entityId: orderId,
          details: '${f.name} × $q = ${formatMoney(cost)}');
      return costId;
    });
  }

  /// استرجاع استخدام سابق بحركة موثقة (مرة واحدة فقط لكل استخدام).
  Future<void> reverseUsage(int actorId, int costId, {String? reason}) async {
    await requireFinance(db, actorId);
    await db.transaction(() async {
      final c =
          await (db.select(db.orderCosts)..where((x) => x.id.equals(costId))).getSingle();
      if (c.kind != 'fabric' || c.amount < 0 || c.inventoryTxnId == null) {
        throw AppException('هذا القيد ليس استخداماً لقماش');
      }
      final already = await (db.select(db.orderCosts)
            ..where((x) => x.reversesCostId.equals(costId)))
          .get();
      if (already.isNotEmpty) throw AppException('تم استرجاع هذا الاستخدام مسبقاً');
      final t = await (db.select(db.inventoryTransactions)
            ..where((x) => x.id.equals(c.inventoryTxnId!)))
          .getSingle();
      final f = await getFabric(t.fabricId);
      final rid = await _apply(
          actorId: actorId,
          fabric: f,
          type: InventoryTypes.usageReversal,
          quantity: t.quantity,
          unitCost: t.unitCost,
          orderId: c.orderId,
          reversesTxnId: t.id,
          notes: reason);
      await db.into(db.orderCosts).insert(OrderCostsCompanion.insert(
            orderId: c.orderId,
            kind: 'fabric',
            amount: -c.amount,
            description: Value('استرجاع: ${c.description ?? ''}'),
            inventoryTxnId: Value(rid),
            reversesCostId: Value(costId),
          ));
      await db.audit(
          userId: actorId,
          action: 'reverse_fabric_usage',
          entity: 'order',
          entityId: c.orderId,
          details: c.description);
    });
  }

  /// يسترجع كل الاستخدامات غير المسترجعة لطلب (مثلاً عند الإلغاء).
  Future<int> reverseAllUsageForOrder(int actorId, int orderId, {String? reason}) async {
    await requireFinance(db, actorId);
    final costs = await (db.select(db.orderCosts)
          ..where((c) => c.orderId.equals(orderId) & c.kind.equals('fabric')))
        .get();
    final reversedIds = costs.map((c) => c.reversesCostId).whereType<int>().toSet();
    var n = 0;
    for (final c in costs) {
      if (c.amount > 0 && c.inventoryTxnId != null && !reversedIds.contains(c.id)) {
        await reverseUsage(actorId, c.id, reason: reason);
        n++;
      }
    }
    return n;
  }

  // ---------- السجلات ----------
  Stream<List<TxnRow>> watchTransactions(int fabricId) {
    final q = db.select(db.inventoryTransactions).join([
      innerJoin(db.fabrics, db.fabrics.id.equalsExp(db.inventoryTransactions.fabricId)),
    ])
      ..where(db.inventoryTransactions.fabricId.equals(fabricId))
      ..orderBy([OrderingTerm.desc(db.inventoryTransactions.id)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            TxnRow(r.readTable(db.inventoryTransactions), r.readTable(db.fabrics).name)
        ]);
  }
}
