import '../../data/db/app_database.dart';

class DebtRow {
  const DebtRow(this.order, this.customer, this.paid);
  final Order order;
  final Customer customer;
  final int paid;
  int get remaining => order.price - paid;
}

class CustomerDebt {
  const CustomerDebt(this.customer, this.rows);
  final Customer customer;
  final List<DebtRow> rows;
  int get total => rows.fold(0, (s, r) => s + r.remaining);
}
