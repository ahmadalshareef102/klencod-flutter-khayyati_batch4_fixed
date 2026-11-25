import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';

class SupplierBalance {
  const SupplierBalance(this.purchases, this.paid);
  final int purchases;
  final int paid;

  /// المستحق للمورد.
  int get due => purchases - paid;
}

class SupplierLine {
  const SupplierLine({
    required this.date,
    required this.kind,
    required this.description,
    required this.amount,
    required this.balance,
  });
  final DateTime date;
  final String kind; // purchase | payment
  final String description;
  final int amount;
  final int balance;
}

class SupplierRepository {
  SupplierRepository(this.db);
  final AppDatabase db;

  Stream<List<Supplier>> watch({int? shopId, String query = ''}) {
    final t = query.trim();
    return (db.select(db.suppliers)
          ..where((s) {
            Expression<bool> w = s.isArchived.equals(false);
            if (shopId != null) w = w & s.shopId.equals(shopId);
            if (t.isNotEmpty) w = w & (s.name.like('%$t%') | s.phone.like('%$t%'));
            return w;
          })
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .watch();
  }

  Stream<Supplier?> watchById(int id) =>
      (db.select(db.suppliers)..where((s) => s.id.equals(id))).watchSingleOrNull();

  Stream<Map<int, SupplierBalance>> watchBalances() {
    return db
        .customSelect(
          '''
SELECT s.id AS id,
 COALESCE((SELECT SUM(CAST(ROUND(t.quantity * t.unit_cost) AS INTEGER))
           FROM inventory_transactions t
           WHERE t.supplier_id = s.id AND t.type = 'purchase'), 0) AS purchases,
 COALESCE((SELECT SUM(sp.amount) FROM supplier_payments sp WHERE sp.supplier_id = s.id), 0) AS paid
FROM suppliers s
''',
          readsFrom: {db.suppliers, db.inventoryTransactions, db.supplierPayments},
        )
        .watch()
        .map((rows) => {
              for (final r in rows)
                r.read<int>('id'): SupplierBalance(r.read<int>('purchases'), r.read<int>('paid')),
            });
  }

  Future<int> create({
    required int actorId,
    required int shopId,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw AppException('اسم المورد مطلوب');
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final id = await db.into(db.suppliers).insert(SuppliersCompanion.insert(
            shopId: shopId,
            name: name.trim(),
            phone: Value(blankToNull(phone) == null ? null : normalizePhone(phone!)),
            address: Value(blankToNull(address)),
            notes: Value(blankToNull(notes)),
          ));
      await db.audit(
          userId: actorId,
          shopId: shopId,
          action: 'create_supplier',
          entity: 'supplier',
          entityId: id,
          details: name.trim());
      return id;
    });
  }

  Future<void> update({
    required int actorId,
    required int id,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw AppException('اسم المورد مطلوب');
    await requireFinance(db, actorId);
    await (db.update(db.suppliers)..where((s) => s.id.equals(id))).write(SuppliersCompanion(
      name: Value(name.trim()),
      phone: Value(blankToNull(phone) == null ? null : normalizePhone(phone!)),
      address: Value(blankToNull(address)),
      notes: Value(blankToNull(notes)),
    ));
    await db.audit(userId: actorId, action: 'update_supplier', entity: 'supplier', entityId: id);
  }

  Future<void> archive(int actorId, int id) async {
    await requireFinance(db, actorId);
    await (db.update(db.suppliers)..where((s) => s.id.equals(id)))
        .write(const SuppliersCompanion(isArchived: Value(true)));
    await db.audit(userId: actorId, action: 'archive_supplier', entity: 'supplier', entityId: id);
  }

  Future<int> pay({
    required int actorId,
    required int supplierId,
    required int amount,
    required DateTime paidAt,
    String method = 'cash',
    String? notes,
  }) async {
    if (amount <= 0) throw AppException('المبلغ يجب أن يكون أكبر من صفر');
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final bal = (await watchBalances().first)[supplierId] ?? const SupplierBalance(0, 0);
      if (amount > bal.due) {
        throw AppException('المبلغ يتجاوز المستحق (${formatMoney(bal.due)})');
      }
      final id = await db.into(db.supplierPayments).insert(SupplierPaymentsCompanion.insert(
            supplierId: supplierId,
            amount: amount,
            paidAt: paidAt,
            method: Value(method),
            notes: Value(blankToNull(notes)),
            userId: Value(actorId),
          ));
      await db.audit(
          userId: actorId,
          action: 'pay_supplier',
          entity: 'supplier',
          entityId: supplierId,
          details: formatMoney(amount));
      return id;
    });
  }

  Stream<List<SupplierLine>> watchStatement(int supplierId) {
    return db
        .customSelect(
          '''
SELECT date, kind, ref, amount FROM (
  SELECT t.created_at AS date, 'purchase' AS kind, f.name || ' × ' || t.quantity AS ref,
         CAST(ROUND(t.quantity * t.unit_cost) AS INTEGER) AS amount, t.id AS sid
  FROM inventory_transactions t JOIN fabrics f ON f.id = t.fabric_id
  WHERE t.supplier_id = ? AND t.type = 'purchase'
  UNION ALL
  SELECT sp.paid_at, 'payment', COALESCE(sp.notes, 'دفعة'), sp.amount, sp.id
  FROM supplier_payments sp WHERE sp.supplier_id = ?
) ORDER BY date, kind DESC, sid
''',
          variables: [Variable.withInt(supplierId), Variable.withInt(supplierId)],
          readsFrom: {db.inventoryTransactions, db.supplierPayments, db.fabrics},
        )
        .watch()
        .map((rows) {
      var bal = 0;
      final out = <SupplierLine>[];
      for (final r in rows) {
        final kind = r.read<String>('kind');
        final amount = r.read<int>('amount');
        bal += kind == 'purchase' ? amount : -amount;
        out.add(SupplierLine(
          date: DateTime.fromMillisecondsSinceEpoch(r.read<int>('date') * 1000),
          kind: kind,
          description: r.read<String>('ref'),
          amount: amount,
          balance: bal,
        ));
      }
      return out;
    });
  }
}
