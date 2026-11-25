import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/period.dart';
import '../features/accounts/accounts_repository.dart';
import '../features/customers/customer_repository.dart';
import '../features/debts/debt_models.dart';
import '../features/expenses/expense_repository.dart';
import '../features/inventory/inventory_repository.dart';
import '../features/measurements/measurement_repository.dart';
import '../features/invoices/invoice_models.dart';
import '../features/invoices/invoice_service.dart';
import '../features/orders/order_costs_repository.dart';
import '../features/orders/order_repository.dart';
import '../features/orders/order_status.dart';
import '../features/payments/payment_repository.dart';
import '../features/suppliers/supplier_repository.dart';
import 'db/app_database.dart';
import 'providers.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
    (ref) => CustomerRepository(ref.watch(databaseProvider)));
final measurementRepositoryProvider = Provider<MeasurementRepository>(
    (ref) => MeasurementRepository(ref.watch(databaseProvider)));
final orderRepositoryProvider = Provider<OrderRepository>(
    (ref) => OrderRepository(ref.watch(databaseProvider)));

/// المحل الفعّال للقوائم (null = كل المحلات للمدير).
final _shopIdProvider = Provider<int?>(
    (ref) => ref.watch(sessionProvider.select((s) => s.shopId)));

// ---------- الزبائن ----------
final customerSearchProvider = StateProvider<String>((ref) => '');

final customersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watch(
        shopId: ref.watch(_shopIdProvider),
        query: ref.watch(customerSearchProvider),
      );
});

final customerByIdProvider =
    StreamProvider.autoDispose.family<Customer?, int>((ref, id) {
  return ref.watch(customerRepositoryProvider).watchById(id);
});

final customerSummaryProvider =
    StreamProvider.autoDispose.family<CustomerSummary, int>((ref, id) {
  return ref.watch(customerRepositoryProvider).watchSummary(id);
});

final customerOrdersProvider = StreamProvider.autoDispose
    .family<List<OrderWithCustomer>, int>((ref, id) {
  return ref.watch(orderRepositoryProvider).watchForCustomer(id);
});

// ---------- المقاسات ----------
final measurementsForCustomerProvider =
    StreamProvider.autoDispose.family<List<Measurement>, int>((ref, id) {
  return ref.watch(measurementRepositoryProvider).watchForCustomer(id);
});

// ---------- الطلبات ----------
/// 'active' | 'all' | مفتاح مرحلة
final orderFilterProvider = StateProvider<String>((ref) => 'active');
final orderSearchProvider = StateProvider<String>((ref) => '');

final ordersProvider =
    StreamProvider.autoDispose<List<OrderWithCustomer>>((ref) {
  final filter = ref.watch(orderFilterProvider);
  return ref.watch(orderRepositoryProvider).watch(
        shopId: ref.watch(_shopIdProvider),
        status: OrderStatus.all.contains(filter) ? filter : null,
        activeOnly: filter == 'active',
        query: ref.watch(orderSearchProvider),
      );
});

/// كل الطلبات الجارية (للوحة الرئيسية).
final activeOrdersProvider =
    StreamProvider.autoDispose<List<OrderWithCustomer>>((ref) {
  return ref.watch(orderRepositoryProvider).watch(
        shopId: ref.watch(_shopIdProvider),
        activeOnly: true,
      );
});

final paidByOrderProvider = StreamProvider.autoDispose<Map<int, int>>((ref) {
  return ref.watch(orderRepositoryProvider).watchPaidByOrder();
});

final orderDetailProvider =
    StreamProvider.autoDispose.family<OrderWithCustomer?, int>((ref, id) {
  return ref.watch(orderRepositoryProvider).watchOne(id);
});

final orderPaidProvider =
    StreamProvider.autoDispose.family<int, int>((ref, id) {
  return ref.watch(orderRepositoryProvider).watchPaidFor(id);
});

final orderHistoryProvider = StreamProvider.autoDispose
    .family<List<OrderStatusChange>, int>((ref, id) {
  return ref.watch(orderRepositoryProvider).watchHistory(id);
});

final orderMeasurementProvider =
    FutureProvider.autoDispose.family<Map<String, String>?, int>((ref, id) async {
  final raw = await ref.watch(orderRepositoryProvider).measurementSnapshot(id);
  if (raw == null) return null;
  final m = jsonDecode(raw) as Map<String, dynamic>;
  return m.map((k, v) => MapEntry(k, v.toString()));
});

// ---------- مستخدمون ----------
final shopWorkersProvider =
    StreamProvider.autoDispose.family<List<User>, int>((ref, shopId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)
        ..where((u) => u.shopId.equals(shopId))
        ..where((u) => u.isActive.equals(true))
        ..orderBy([(u) => OrderingTerm.asc(u.fullName)]))
      .watch();
});

final userByIdProvider =
    StreamProvider.autoDispose.family<User?, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)..where((u) => u.id.equals(id))).watchSingleOrNull();
});


// ======================= الدفعة 3 =======================
final paymentRepositoryProvider = Provider<PaymentRepository>(
    (ref) => PaymentRepository(ref.watch(databaseProvider)));
final expenseRepositoryProvider = Provider<ExpenseRepository>(
    (ref) => ExpenseRepository(ref.watch(databaseProvider)));
final accountsRepositoryProvider = Provider<AccountsRepository>(
    (ref) => AccountsRepository(ref.watch(databaseProvider)));
final inventoryRepositoryProvider = Provider<InventoryRepository>(
    (ref) => InventoryRepository(ref.watch(databaseProvider)));
final orderCostsRepositoryProvider = Provider<OrderCostsRepository>(
    (ref) => OrderCostsRepository(ref.watch(databaseProvider)));
final supplierRepositoryProvider = Provider<SupplierRepository>(
    (ref) => SupplierRepository(ref.watch(databaseProvider)));

/// نوع المحل (men/women) من رقمه.
final shopTypeProvider = Provider.family<String?, int>((ref, id) {
  final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];
  for (final s in shops) {
    if (s.id == id) return s.type;
  }
  return null;
});

// ---------- الدفعات والديون ----------
final orderPaymentsProvider =
    StreamProvider.autoDispose.family<List<Payment>, int>((ref, id) {
  return ref.watch(paymentRepositoryProvider).watchForOrder(id);
});

final paymentLogProvider = StreamProvider.autoDispose<List<PaymentRow>>((ref) {
  return ref.watch(paymentRepositoryProvider).watchLog(shopId: ref.watch(_shopIdProvider));
});

final statementProvider =
    StreamProvider.autoDispose.family<List<StatementEntry>, int>((ref, id) {
  return ref.watch(paymentRepositoryProvider).watchStatement(id);
});

final debtOrdersProvider =
    StreamProvider.autoDispose<List<OrderWithCustomer>>((ref) {
  return ref.watch(orderRepositoryProvider).watch(
        shopId: ref.watch(_shopIdProvider),
        archived: null,
        excludeCancelled: true,
      );
});

final customerDebtsProvider = Provider.autoDispose<List<CustomerDebt>>((ref) {
  final orders = ref.watch(debtOrdersProvider).valueOrNull ?? const <OrderWithCustomer>[];
  final paid = ref.watch(paidByOrderProvider).valueOrNull ?? const <int, int>{};
  final map = <int, List<DebtRow>>{};
  for (final o in orders) {
    final p = paid[o.order.id] ?? 0;
    if (o.order.price - p > 0) {
      map.putIfAbsent(o.customer.id, () => []).add(DebtRow(o.order, o.customer, p));
    }
  }
  final list = [for (final rows in map.values) CustomerDebt(rows.first.customer, rows)];
  list.sort((a, b) => b.total.compareTo(a.total));
  return list;
});

// ---------- الفترة والحسابات والمصروفات ----------
final periodProvider = StateProvider<Period>((ref) => Period.of(PeriodKind.month));

final accountsSummaryProvider =
    StreamProvider.autoDispose<AccountsSummary>((ref) {
  final p = ref.watch(periodProvider);
  return ref.watch(accountsRepositoryProvider).watchSummary(
      shopId: ref.watch(_shopIdProvider), from: p.from, to: p.to);
});

/// ملخص الشهر الحالي للوحة الرئيسية.
final monthSummaryProvider = StreamProvider.autoDispose<AccountsSummary>((ref) {
  final p = Period.of(PeriodKind.month);
  return ref.watch(accountsRepositoryProvider).watchSummary(
      shopId: ref.watch(_shopIdProvider), from: p.from, to: p.to);
});

final expenseSearchProvider = StateProvider<String>((ref) => '');

final expensesProvider = StreamProvider.autoDispose<List<Expense>>((ref) {
  final p = ref.watch(periodProvider);
  return ref.watch(expenseRepositoryProvider).watch(
        shopId: ref.watch(_shopIdProvider),
        from: p.from,
        to: p.to,
        query: ref.watch(expenseSearchProvider),
      );
});

// ---------- المخزون ----------
final fabricSearchProvider = StateProvider<String>((ref) => '');

final fabricsProvider = StreamProvider.autoDispose<List<Fabric>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchFabrics(
      shopId: ref.watch(_shopIdProvider), query: ref.watch(fabricSearchProvider));
});

/// مواد محل معيّن (لقوائم الاختيار).
final shopFabricsProvider =
    StreamProvider.autoDispose.family<List<Fabric>, int>((ref, shopId) {
  return ref.watch(inventoryRepositoryProvider).watchFabrics(shopId: shopId);
});

final fabricProvider = StreamProvider.autoDispose.family<Fabric?, int>((ref, id) {
  return ref.watch(inventoryRepositoryProvider).watchFabric(id);
});

final fabricTxnsProvider =
    StreamProvider.autoDispose.family<List<TxnRow>, int>((ref, id) {
  return ref.watch(inventoryRepositoryProvider).watchTransactions(id);
});

final orderCostsProvider =
    StreamProvider.autoDispose.family<List<OrderCost>, int>((ref, id) {
  return ref.watch(orderCostsRepositoryProvider).watch(id);
});

// ---------- الموردون ----------
final supplierSearchProvider = StateProvider<String>((ref) => '');

final suppliersProvider = StreamProvider.autoDispose<List<Supplier>>((ref) {
  return ref.watch(supplierRepositoryProvider).watch(
      shopId: ref.watch(_shopIdProvider), query: ref.watch(supplierSearchProvider));
});

final shopSuppliersProvider =
    StreamProvider.autoDispose.family<List<Supplier>, int>((ref, shopId) {
  return ref.watch(supplierRepositoryProvider).watch(shopId: shopId);
});

final supplierBalancesProvider =
    StreamProvider.autoDispose<Map<int, SupplierBalance>>((ref) {
  return ref.watch(supplierRepositoryProvider).watchBalances();
});

final supplierByIdProvider =
    StreamProvider.autoDispose.family<Supplier?, int>((ref, id) {
  return ref.watch(supplierRepositoryProvider).watchById(id);
});

final supplierStatementProvider =
    StreamProvider.autoDispose.family<List<SupplierLine>, int>((ref, id) {
  return ref.watch(supplierRepositoryProvider).watchStatement(id);
});

final allowOverpayProvider =
    FutureProvider.autoDispose.family<bool, int>((ref, shopId) {
  return ref.watch(paymentRepositoryProvider).allowOverpay(shopId);
});

// ======================= الدفعة 4: الفواتير =======================
final invoiceServiceProvider = Provider<InvoiceService>(
    (ref) => InvoiceService(ref.watch(databaseProvider)));

final invoiceSettingsRepositoryProvider = Provider<InvoiceSettingsRepository>(
    (ref) => InvoiceSettingsRepository(ref.watch(databaseProvider)));
