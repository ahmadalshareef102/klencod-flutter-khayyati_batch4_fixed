import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khayyati/core/constants.dart';
import 'package:khayyati/core/period.dart';
import 'package:khayyati/core/security/password_hasher.dart';
import 'package:khayyati/data/db/app_database.dart';
import 'package:khayyati/features/accounts/accounts_repository.dart';
import 'package:khayyati/features/auth/auth_repository.dart';
import 'package:khayyati/features/customers/customer_repository.dart';
import 'package:khayyati/features/expenses/expense_repository.dart';
import 'package:khayyati/features/inventory/inventory_repository.dart';
import 'package:khayyati/features/orders/order_costs_repository.dart';
import 'package:khayyati/features/orders/order_repository.dart';
import 'package:khayyati/features/orders/order_status.dart';
import 'package:khayyati/features/payments/payment_repository.dart';
import 'package:khayyati/features/suppliers/supplier_repository.dart';

void main() {
  late AppDatabase db;
  late AuthRepository auth;
  late CustomerRepository customers;
  late OrderRepository orders;
  late PaymentRepository payments;
  late ExpenseRepository expenses;
  late InventoryRepository inventory;
  late OrderCostsRepository costs;
  late SupplierRepository suppliers;
  late AccountsRepository accounts;
  late int admin;
  late int plainWorker; // بدون صلاحيات مالية ولا إنشاء طلبات

  const menShop = 1;
  const womenShop = 2;
  final orderDate = DateTime(2026, 3, 1);

  Future<int> newOrder({int price = 100000, int deposit = 0, int shop = menShop}) async {
    final c = await customers.create(
        actorId: admin, shopId: shop, name: 'زبون', phone: '05${DateTime.now().microsecondsSinceEpoch}');
    return orders.create(
        admin,
        OrderInput(
            shopId: shop,
            customerId: c,
            orderDate: orderDate,
            dueDate: DateTime(2026, 3, 10),
            price: price,
            deposit: deposit));
  }

  Future<int> newFabric({int shop = menShop}) =>
      inventory.createFabric(actorId: admin, shopId: shop, name: 'قطن', color: 'أبيض', alertLevel: 3);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auth = AuthRepository(db, hasher: PasswordHasher(iterations: 1000));
    customers = CustomerRepository(db);
    orders = OrderRepository(db);
    payments = PaymentRepository(db);
    expenses = ExpenseRepository(db);
    inventory = InventoryRepository(db);
    costs = OrderCostsRepository(db);
    suppliers = SupplierRepository(db);
    accounts = AccountsRepository(db);
    admin = (await auth.createAdmin(
            fullName: 'المدير', username: 'admin', password: 'password123'))
        .id;
    plainWorker = (await auth.createWorker(
            actorId: admin,
            fullName: 'عامل',
            username: 'w1',
            password: 'workerpass1',
            shopId: menShop,
            canCreateOrders: false))
        .id;
  });
  tearDown(() => db.close());

  group('الدفعات', () {
    test('دفعات متعددة ومنع التجاوز وإعداد السماح', () async {
      final o = await newOrder(price: 10000, deposit: 2000);
      await payments.add(actorId: admin, orderId: o, amount: 3000, paidAt: orderDate);
      expect(await orders.paidFor(o), 5000);
      await expectLater(
          payments.add(actorId: admin, orderId: o, amount: 6000, paidAt: orderDate),
          throwsA(isA<AppException>()));
      await expectLater(
          payments.add(actorId: admin, orderId: o, amount: 0, paidAt: orderDate),
          throwsA(isA<AppException>()));
      await payments.setAllowOverpay(admin, menShop, true);
      await payments.add(actorId: admin, orderId: o, amount: 6000, paidAt: orderDate);
      expect(await orders.paidFor(o), 11000);
    });

    test('الإبطال بسبب للمدير فقط ولا يُحتسب المبطل', () async {
      final o = await newOrder(price: 10000);
      final p = await payments.add(
          actorId: admin, orderId: o, amount: 4000, paidAt: orderDate);
      await expectLater(payments.voidPayment(admin, p, '  '), throwsA(isA<AppException>()));
      await expectLater(payments.voidPayment(plainWorker, p, 'خطأ'),
          throwsA(isA<AppException>()));
      await payments.voidPayment(admin, p, 'مبلغ خاطئ');
      expect(await orders.paidFor(o), 0);
      await expectLater(payments.voidPayment(admin, p, 'مرة أخرى'),
          throwsA(isA<AppException>()));
      // الدفعة باقية في السجل
      expect((await db.select(db.payments).get()).single.voidReason, 'مبلغ خاطئ');
    });

    test('لا دفعات على طلب ملغي ولا من عامل بلا صلاحية', () async {
      final o = await newOrder(price: 10000);
      await expectLater(
          payments.add(actorId: plainWorker, orderId: o, amount: 100, paidAt: orderDate),
          throwsA(isA<AppException>()));
      await orders.changeStatus(admin, o, OrderStatus.cancelled, 'إلغاء');
      await expectLater(
          payments.add(actorId: admin, orderId: o, amount: 100, paidAt: orderDate),
          throwsA(isA<AppException>()));
    });

    test('كشف الحساب برصيد جارٍ', () async {
      final o = await newOrder(price: 10000, deposit: 2500);
      final cust = (await orders.getById(o)).customerId;
      await payments.add(actorId: admin, orderId: o, amount: 1000, paidAt: orderDate);
      final st = await payments.watchStatement(cust).first;
      expect(st.map((e) => e.kind), ['order', 'payment', 'payment']);
      expect(st.last.balance, 6500);
    });
  });

  group('المصروفات', () {
    test('إضافة وتعديل وإلغاء مع الصلاحيات', () async {
      final id = await expenses.add(
          actorId: admin,
          shopId: menShop,
          category: 'rent',
          amount: 50000,
          date: DateTime.now());
      await expectLater(
          expenses.add(
              actorId: plainWorker,
              shopId: menShop,
              category: 'rent',
              amount: 1,
              date: DateTime.now()),
          throwsA(isA<AppException>()));
      await expectLater(
          expenses.add(
              actorId: admin, shopId: menShop, category: 'x', amount: 1, date: DateTime.now()),
          throwsA(isA<AppException>()));
      await expenses.update(
          actorId: admin, id: id, category: 'water', amount: 40000, date: DateTime.now());
      final from = DateTime.now().subtract(const Duration(days: 1));
      final to = DateTime.now().add(const Duration(days: 1));
      expect((await expenses.watch(from: from, to: to).first).single.amount, 40000);
      await expenses.voidExpense(admin, id);
      expect(await expenses.watch(from: from, to: to).first, isEmpty);
      expect((await expenses.watch(from: from, to: to, includeVoided: true).first).length, 1);
    });
  });

  group('المخزون والموردون', () {
    test('شراء آجل بمتوسط مرجّح ومستحقات المورد', () async {
      final f = await newFabric();
      final s = await suppliers.create(actorId: admin, shopId: menShop, name: 'مورد');
      await inventory.purchase(
          actorId: admin, fabricId: f, quantity: 10, unitCost: 5000, supplierId: s, paid: 20000);
      await inventory.purchase(
          actorId: admin, fabricId: f, quantity: 10, unitCost: 7000, supplierId: s);
      final fab = await inventory.getFabric(f);
      expect(fab.quantity, 20);
      expect(fab.unitCost, 6000);
      var bal = (await suppliers.watchBalances().first)[s]!;
      expect(bal.purchases, 120000);
      expect(bal.due, 100000);

      await expectLater(
          suppliers.pay(actorId: admin, supplierId: s, amount: 100001, paidAt: DateTime.now()),
          throwsA(isA<AppException>()));
      await suppliers.pay(actorId: admin, supplierId: s, amount: 40000, paidAt: DateTime.now());
      bal = (await suppliers.watchBalances().first)[s]!;
      expect(bal.due, 60000);
      final st = await suppliers.watchStatement(s).first;
      expect(st.last.balance, 60000);

      await expectLater(
          inventory.purchase(actorId: admin, fabricId: f, quantity: 1, unitCost: 100, paid: 500),
          throwsA(isA<AppException>()));
    });

    test('الاستخدام على الطلب: خصم مرة واحدة ومنع التكرار والاسترجاع الموثق', () async {
      final f = await newFabric();
      await inventory.purchase(actorId: admin, fabricId: f, quantity: 10, unitCost: 6000);
      final o = await newOrder();

      final c1 = await inventory.useOnOrder(
          actorId: admin, orderId: o, fabricId: f, quantity: 4);
      expect((await inventory.getFabric(f)).quantity, 6);
      var list = await costs.watch(o).first;
      expect(list.single.amount, 24000);

      await expectLater(
          inventory.useOnOrder(actorId: admin, orderId: o, fabricId: f, quantity: 1),
          throwsA(isA<AppException>()));
      await expectLater(
          inventory.useOnOrder(actorId: plainWorker, orderId: o, fabricId: f, quantity: 1),
          throwsA(isA<AppException>()));

      await inventory.reverseUsage(admin, c1);
      expect((await inventory.getFabric(f)).quantity, 10);
      list = await costs.watch(o).first;
      expect(list.fold<int>(0, (s, c) => s + c.amount), 0);
      await expectLater(inventory.reverseUsage(admin, c1), throwsA(isA<AppException>()));

      // بعد الاسترجاع يُسمح بخصم جديد
      await inventory.useOnOrder(actorId: admin, orderId: o, fabricId: f, quantity: 2);
      expect((await inventory.getFabric(f)).quantity, 8);
    });

    test('منع الرصيد السالب، وإرجاع الأقمشة عند الإلغاء', () async {
      final f = await newFabric();
      await inventory.purchase(actorId: admin, fabricId: f, quantity: 3, unitCost: 1000);
      final o = await newOrder();
      await expectLater(
          inventory.useOnOrder(actorId: admin, orderId: o, fabricId: f, quantity: 5),
          throwsA(isA<AppException>()));
      expect((await inventory.getFabric(f)).quantity, 3);

      await inventory.useOnOrder(actorId: admin, orderId: o, fabricId: f, quantity: 2);
      await orders.changeStatus(admin, o, OrderStatus.cancelled, 'إلغاء');
      expect(await inventory.reverseAllUsageForOrder(admin, o), 1);
      expect((await inventory.getFabric(f)).quantity, 3);
      expect(await inventory.reverseAllUsageForOrder(admin, o), 0);
    });

    test('النقل بين المحلين ينشئ المادة في الوجهة ويحفظ الحركتين', () async {
      final f = await newFabric();
      await inventory.purchase(actorId: admin, fabricId: f, quantity: 10, unitCost: 5000);
      await expectLater(
          inventory.transfer(actorId: plainWorker, fabricId: f, toShopId: womenShop, quantity: 1),
          throwsA(isA<AppException>()));
      await inventory.transfer(actorId: admin, fabricId: f, toShopId: womenShop, quantity: 4);
      expect((await inventory.getFabric(f)).quantity, 6);
      final dst = await inventory.watchFabrics(shopId: womenShop).first;
      expect(dst.single.quantity, 4);
      expect(dst.single.unitCost, 5000);
      final txs = await db.select(db.inventoryTransactions).get();
      expect(txs.map((t) => t.type), containsAll(['transfer_out', 'transfer_in']));
      await expectLater(
          inventory.transfer(actorId: admin, fabricId: f, toShopId: womenShop, quantity: 100),
          throwsA(isA<AppException>()));
    });

    test('تنبيه النقص', () async {
      final f = await newFabric(); // حد التنبيه 3
      await inventory.purchase(actorId: admin, fabricId: f, quantity: 5, unitCost: 1000);
      expect(InventoryRepository.isLow(await inventory.getFabric(f)), isFalse);
      await inventory.adjust(
          actorId: admin, fabricId: f, type: InventoryTypes.deduct, quantity: 2);
      expect(InventoryRepository.isLow(await inventory.getFabric(f)), isTrue);
    });
  });

  group('الحسابات والأرباح', () {
    test('الإيراد عند التسليم والعربون ليس ربحاً ولا ازدواج في التكلفة', () async {
      final f = await newFabric();
      await inventory.purchase(actorId: admin, fabricId: f, quantity: 10, unitCost: 3000);

      // طلب سيُسلَّم: سعر 100000، عربون 30000
      final delivered = await newOrder(price: 100000, deposit: 30000);
      await inventory.useOnOrder(actorId: admin, orderId: delivered, fabricId: f, quantity: 10);
      await costs.add(actorId: admin, orderId: delivered, kind: 'labor', amount: 10000);
      await orders.changeStatus(admin, delivered, OrderStatus.delivered, null);

      // طلب مفتوح بعربون 20000
      await newOrder(price: 50000, deposit: 20000);

      await expenses.add(
          actorId: admin,
          shopId: menShop,
          category: 'rent',
          amount: 5000,
          date: DateTime.now());

      final p = Period.of(PeriodKind.custom,
          customFrom: DateTime(2026, 1, 1),
          customTo: DateTime.now().add(const Duration(days: 1)));
      final s = await accounts.watchSummary(shopId: menShop, from: p.from, to: p.to).first;

      expect(s.newOrdersCount, 2);
      expect(s.newOrdersValue, 150000);
      expect(s.collected, 50000);
      expect(s.deliveredCount, 1);
      expect(s.revenue, 100000);
      expect(s.fabricCost, 30000);
      expect(s.laborCost, 10000);
      expect(s.grossProfit, 60000);
      expect(s.operatingExpenses, 5000);
      expect(s.netProfit, 55000);
      expect(s.outstandingDebts, 70000 + 30000);
      expect(s.advancesOnOpenOrders, 20000);

      // المحل الآخر مفصول تماماً، والإجمالي يجمع
      final other = await accounts.watchSummary(shopId: womenShop, from: p.from, to: p.to).first;
      expect(other.revenue, 0);
      expect(other.newOrdersCount, 0);
      final all = await accounts.watchSummary(from: p.from, to: p.to).first;
      expect(all.revenue, 100000);
    });

    test('الهالك يُخصم من الربح الصافي', () async {
      final f = await newFabric();
      await inventory.purchase(actorId: admin, fabricId: f, quantity: 10, unitCost: 6000);
      await inventory.adjust(
          actorId: admin, fabricId: f, type: InventoryTypes.waste, quantity: 2);
      final p = Period.of(PeriodKind.today);
      final s = await accounts.watchSummary(shopId: menShop, from: p.from, to: p.to).first;
      expect(s.wasteCost, 12000);
      expect(s.netProfit, -12000);
    });
  });

  test('الفترات: بداية الأسبوع السبت ونهاية غير شاملة', () {
    final wed = DateTime(2026, 11, 25); // أربعاء
    final w = Period.of(PeriodKind.week, now: wed);
    expect(w.from, DateTime(2026, 11, 21)); // السبت
    expect(w.to, DateTime(2026, 11, 26));
    final m = Period.of(PeriodKind.month, now: wed);
    expect(m.from, DateTime(2026, 11, 1));
  });
}
