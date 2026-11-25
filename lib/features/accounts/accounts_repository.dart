import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';

/// ملخص مالي قابل للتفسير. كل بند مُعرَّف في الواجهة بنص واضح.
class AccountsSummary {
  const AccountsSummary({
    required this.newOrdersCount,
    required this.newOrdersValue,
    required this.collected,
    required this.deliveredCount,
    required this.revenue,
    required this.fabricCost,
    required this.laborCost,
    required this.otherDirectCost,
    required this.wasteCost,
    required this.operatingExpenses,
    required this.outstandingDebts,
    required this.advancesOnOpenOrders,
  });

  final int newOrdersCount;
  final int newOrdersValue;
  final int collected;
  final int deliveredCount;
  final int revenue;
  final int fabricCost;
  final int laborCost;
  final int otherDirectCost;
  final int wasteCost;
  final int operatingExpenses;
  final int outstandingDebts;
  final int advancesOnOpenOrders;

  int get directCosts => laborCost + otherDirectCost;
  int get grossProfit => revenue - fabricCost - directCosts;
  int get netProfit => grossProfit - operatingExpenses - wasteCost;
}

class AccountsRepository {
  AccountsRepository(this.db);
  final AppDatabase db;

  /// [from] شاملة و[to] غير شاملة. الإيراد يُعترف به عند التسليم وليس عند أخذ العربون.
  Stream<AccountsSummary> watchSummary({
    int? shopId,
    required DateTime from,
    required DateTime to,
  }) {
    final sb = StringBuffer('SELECT ');
    final vars = <Variable>[];
    final fromV = Variable.withDateTime(from);
    final toV = Variable.withDateTime(to);
    String sf(String col) => shopId == null ? '' : ' AND $col = ?';
    List<Variable> sv() => shopId == null ? <Variable>[] : [Variable.withInt(shopId)];
    var first = true;
    void col(String name, String sql, List<Variable> v) {
      if (!first) sb.write(', ');
      first = false;
      sb.write('($sql) AS $name');
      vars.addAll(v);
    }

    const delivered =
        "o.status = 'delivered' AND o.id IN (SELECT h.order_id FROM order_status_history h "
        "WHERE h.new_status = 'delivered' AND h.changed_at >= ? AND h.changed_at < ?)";

    col(
        'new_cnt',
        "SELECT COUNT(*) FROM orders o WHERE o.status != 'cancelled' "
            "AND o.order_date >= ? AND o.order_date < ?${sf('o.shop_id')}",
        [fromV, toV, ...sv()]);
    col(
        'new_value',
        "SELECT COALESCE(SUM(o.price), 0) FROM orders o WHERE o.status != 'cancelled' "
            "AND o.order_date >= ? AND o.order_date < ?${sf('o.shop_id')}",
        [fromV, toV, ...sv()]);
    col(
        'collected',
        'SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.voided_at IS NULL '
            "AND p.paid_at >= ? AND p.paid_at < ?${sf('p.shop_id')}",
        [fromV, toV, ...sv()]);
    col('del_cnt', "SELECT COUNT(*) FROM orders o WHERE $delivered${sf('o.shop_id')}",
        [fromV, toV, ...sv()]);
    col(
        'revenue',
        "SELECT COALESCE(SUM(o.price), 0) FROM orders o WHERE $delivered${sf('o.shop_id')}",
        [fromV, toV, ...sv()]);
    for (final kind in ['fabric', 'labor', 'other']) {
      col(
          '${kind}_cost',
          "SELECT COALESCE(SUM(c.amount), 0) FROM order_costs c WHERE c.kind = '$kind' "
              "AND c.order_id IN (SELECT o.id FROM orders o WHERE $delivered${sf('o.shop_id')})",
          [fromV, toV, ...sv()]);
    }
    col(
        'waste',
        'SELECT COALESCE(SUM(CAST(ROUND(t.quantity * t.unit_cost) AS INTEGER)), 0) '
            "FROM inventory_transactions t WHERE t.type = 'waste' "
            "AND t.created_at >= ? AND t.created_at < ?${sf('t.shop_id')}",
        [fromV, toV, ...sv()]);
    col(
        'expenses',
        'SELECT COALESCE(SUM(e.amount), 0) FROM expenses e WHERE e.voided_at IS NULL '
            "AND e.date >= ? AND e.date < ?${sf('e.shop_id')}",
        [fromV, toV, ...sv()]);
    col(
        'debts',
        'SELECT COALESCE(SUM(r), 0) FROM (SELECT o.price - COALESCE((SELECT SUM(p.amount) '
            'FROM payments p WHERE p.order_id = o.id AND p.voided_at IS NULL), 0) AS r '
            "FROM orders o WHERE o.status != 'cancelled'${sf('o.shop_id')}) WHERE r > 0",
        sv());
    col(
        'advances',
        'SELECT COALESCE(SUM(p.amount), 0) FROM payments p JOIN orders o ON o.id = p.order_id '
            "WHERE p.voided_at IS NULL AND o.status NOT IN ('delivered', 'cancelled')${sf('o.shop_id')}",
        sv());

    return db
        .customSelect(
          sb.toString(),
          variables: vars,
          readsFrom: {
            db.orders,
            db.payments,
            db.orderCosts,
            db.expenses,
            db.inventoryTransactions,
            db.orderStatusHistory,
          },
        )
        .watchSingle()
        .map((r) => AccountsSummary(
              newOrdersCount: r.read<int>('new_cnt'),
              newOrdersValue: r.read<int>('new_value'),
              collected: r.read<int>('collected'),
              deliveredCount: r.read<int>('del_cnt'),
              revenue: r.read<int>('revenue'),
              fabricCost: r.read<int>('fabric_cost'),
              laborCost: r.read<int>('labor_cost'),
              otherDirectCost: r.read<int>('other_cost'),
              wasteCost: r.read<int>('waste'),
              operatingExpenses: r.read<int>('expenses'),
              outstandingDebts: r.read<int>('debts'),
              advancesOnOpenOrders: r.read<int>('advances'),
            ));
  }
}
