import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.ordersCount,
    required this.totalPrice,
    required this.totalPaid,
  });
  final int ordersCount;
  final int totalPrice;
  final int totalPaid;

  /// إجمالي الدين = قيمة الطلبات غير الملغاة - المدفوع عليها.
  int get debt => totalPrice - totalPaid;
}

class CustomerRepository {
  CustomerRepository(this.db);
  final AppDatabase db;

  Stream<List<Customer>> watch({
    int? shopId,
    String query = '',
    bool archived = false,
  }) {
    final t = query.trim();
    final q = db.select(db.customers)
      ..where((c) {
        Expression<bool> e = c.isArchived.equals(archived);
        if (shopId != null) e = e & c.shopId.equals(shopId);
        if (t.isNotEmpty) {
          e = e & (c.name.like('%$t%') | c.phone.like('%${normalizePhone(t)}%'));
        }
        return e;
      })
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return q.watch();
  }

  Stream<Customer?> watchById(int id) =>
      (db.select(db.customers)..where((c) => c.id.equals(id))).watchSingleOrNull();

  Future<Customer> getById(int id) =>
      (db.select(db.customers)..where((c) => c.id.equals(id))).getSingle();

  Future<Customer?> findByPhone(int shopId, String phone, {int? excludeId}) async {
    final p = normalizePhone(phone);
    if (p.isEmpty) return null;
    final rows = await (db.select(db.customers)
          ..where((c) {
            Expression<bool> e = c.shopId.equals(shopId) & c.phone.equals(p);
            if (excludeId != null) e = e & c.id.isNotValue(excludeId);
            return e;
          })
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> create({
    required int actorId,
    required int shopId,
    required String name,
    required String phone,
    String? address,
    String? notes,
  }) async {
    final n = name.trim();
    final p = normalizePhone(phone);
    if (n.isEmpty) throw AppException('اسم الزبون مطلوب');
    if (p.isEmpty) throw AppException('رقم الهاتف مطلوب');
    return db.transaction(() async {
      final id = await db.into(db.customers).insert(CustomersCompanion.insert(
            shopId: shopId,
            name: n,
            phone: p,
            address: Value(blankToNull(address)),
            notes: Value(blankToNull(notes)),
          ));
      await db.audit(
          userId: actorId,
          shopId: shopId,
          action: 'create_customer',
          entity: 'customer',
          entityId: id,
          details: n);
      return id;
    });
  }

  Future<void> update({
    required int actorId,
    required int id,
    required String name,
    required String phone,
    String? address,
    String? notes,
  }) async {
    final n = name.trim();
    final p = normalizePhone(phone);
    if (n.isEmpty) throw AppException('اسم الزبون مطلوب');
    if (p.isEmpty) throw AppException('رقم الهاتف مطلوب');
    await db.transaction(() async {
      final old = await getById(id);
      await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            name: Value(n),
            phone: Value(p),
            address: Value(blankToNull(address)),
            notes: Value(blankToNull(notes)),
          ));
      await db.audit(
          userId: actorId,
          shopId: old.shopId,
          action: 'update_customer',
          entity: 'customer',
          entityId: id);
    });
  }

  /// أرشفة آمنة: لا حذف للزبائن، فتبقى طلباتهم وحساباتهم سليمة.
  Future<void> setArchived(int actorId, int id, bool archived) async {
    await db.transaction(() async {
      final old = await getById(id);
      await (db.update(db.customers)..where((c) => c.id.equals(id)))
          .write(CustomersCompanion(isArchived: Value(archived)));
      await db.audit(
          userId: actorId,
          shopId: old.shopId,
          action: archived ? 'archive_customer' : 'restore_customer',
          entity: 'customer',
          entityId: id);
    });
  }

  Stream<CustomerSummary> watchSummary(int customerId) {
    return db
        .customSelect(
          '''
SELECT
 (SELECT COUNT(*) FROM orders WHERE customer_id = ? AND status != 'cancelled') AS cnt,
 (SELECT COALESCE(SUM(price), 0) FROM orders WHERE customer_id = ? AND status != 'cancelled') AS total,
 (SELECT COALESCE(SUM(p.amount), 0) FROM payments p JOIN orders o ON o.id = p.order_id
   WHERE p.customer_id = ? AND o.status != 'cancelled' AND p.voided_at IS NULL) AS paid
''',
          variables: [
            Variable.withInt(customerId),
            Variable.withInt(customerId),
            Variable.withInt(customerId),
          ],
          readsFrom: {db.orders, db.payments},
        )
        .watchSingle()
        .map((r) => CustomerSummary(
              ordersCount: r.read<int>('cnt'),
              totalPrice: r.read<int>('total'),
              totalPaid: r.read<int>('paid'),
            ));
  }
}
