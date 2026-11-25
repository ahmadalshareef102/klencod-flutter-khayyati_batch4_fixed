import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khayyati/core/constants.dart';
import 'package:khayyati/core/money.dart';
import 'package:khayyati/core/security/password_hasher.dart';
import 'package:khayyati/core/text_utils.dart';
import 'package:khayyati/data/db/app_database.dart';
import 'package:khayyati/features/auth/auth_repository.dart';
import 'package:khayyati/features/customers/customer_repository.dart';
import 'package:khayyati/features/measurements/measurement_repository.dart';
import 'package:khayyati/features/orders/order_repository.dart';
import 'package:khayyati/features/orders/order_status.dart';

void main() {
  late AppDatabase db;
  late CustomerRepository customers;
  late MeasurementRepository measurements;
  late OrderRepository orders;
  late int actor;

  const menShop = 1;
  const womenShop = 2;
  final orderDate = DateTime(2026, 3, 1);

  Future<int> newCustomer({int shop = menShop, String phone = '0500000001'}) =>
      customers.create(actorId: actor, shopId: shop, name: 'زبون', phone: phone);

  OrderInput input(int customerId,
          {int shop = menShop, int price = 10000, int deposit = 0, int? measurementId}) =>
      OrderInput(
        shopId: shop,
        customerId: customerId,
        orderDate: orderDate,
        dueDate: DateTime(2026, 3, 10),
        price: price,
        deposit: deposit,
        measurementId: measurementId,
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    customers = CustomerRepository(db);
    measurements = MeasurementRepository(db);
    orders = OrderRepository(db);
    final auth = AuthRepository(db, hasher: PasswordHasher(iterations: 1000));
    final admin = await auth.createAdmin(
        fullName: 'المدير', username: 'admin', password: 'password123');
    actor = admin.id;
  });
  tearDown(() => db.close());

  group('أدوات', () {
    test('تحويل الأرقام العربية والمبالغ', () {
      expect(normalizePhone('٠٥٠ ١٢٣-٤٥٦٧'), '0501234567');
      expect(parseMoney('١٢٫٥'), 1250);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney('-5'), isNull);
      expect(formatMoney(123456789), '1,234,567.89');
      expect(formatMoney(5000), '50');
    });
  });

  group('الزبائن', () {
    test('اكتشاف الهاتف المكرر مع توحيد الأرقام داخل نفس المحل فقط', () async {
      final id = await newCustomer(phone: '0501234567');
      final dup = await customers.findByPhone(menShop, '٠٥٠١٢٣٤٥٦٧');
      expect(dup?.id, id);
      expect(await customers.findByPhone(menShop, '0501234567', excludeId: id), isNull);
      expect(await customers.findByPhone(womenShop, '0501234567'), isNull);
    });

    test('الأرشفة تخفي الزبون دون حذفه', () async {
      final id = await newCustomer();
      await customers.setArchived(actor, id, true);
      expect(await customers.watch(shopId: menShop).first, isEmpty);
      expect((await customers.watch(shopId: menShop, archived: true).first).length, 1);
      expect((await customers.getById(id)).isArchived, isTrue);
    });
  });

  group('المقاسات', () {
    test('تنظيف القيم وإضافة حقل مخصص ومنع التكرار', () async {
      final c = await newCustomer();
      final id = await measurements.create(
          actorId: actor,
          customerId: c,
          label: '',
          values: {'الصدر': '٥٠٫٥', 'الخصر': '', 'الكتف': '45'});
      final m = await measurements.getById(id);
      expect(m.label, 'سجل مقاسات');
      expect(MeasurementFields.decode(m.valuesJson), {'الصدر': '50.5', 'الكتف': '45'});

      await expectLater(
        measurements.create(
            actorId: actor, customerId: c, label: 'x', values: {'الصدر': 'abc'}),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        measurements.create(actorId: actor, customerId: c, label: 'x', values: {}),
        throwsA(isA<AppException>()),
      );

      await measurements.addExtraField(menShop, 'محيط الساق');
      expect(await measurements.extraFields(menShop), ['محيط الساق']);
      await expectLater(measurements.addExtraField(menShop, 'محيط الساق'),
          throwsA(isA<AppException>()));
      await expectLater(measurements.addExtraField(menShop, 'الصدر'),
          throwsA(isA<AppException>()));
      // الحقول المخصصة لكل محل على حدة
      expect(await measurements.extraFields(womenShop), isEmpty);
    });
  });

  group('الطلبات', () {
    test('أرقام فريدة متسلسلة لكل محل وسنة', () async {
      final m = await newCustomer();
      final w = await newCustomer(shop: womenShop, phone: '0509999999');
      final a = await orders.create(actor, input(m));
      final b = await orders.create(actor, input(m));
      final c = await orders.create(actor, input(w, shop: womenShop));
      expect((await orders.getById(a)).orderNo, 'M-2026-0001');
      expect((await orders.getById(b)).orderNo, 'M-2026-0002');
      expect((await orders.getById(c)).orderNo, 'W-2026-0001');
    });

    test('العربون ينشئ دفعة ويُحتسب المدفوع والمتبقي', () async {
      final cu = await newCustomer();
      final id = await orders.create(actor, input(cu, price: 20000, deposit: 5000));
      expect(await orders.paidFor(id), 5000);
      final summary = await customers.watchSummary(cu).first;
      expect(summary.ordersCount, 1);
      expect(summary.totalPrice, 20000);
      expect(summary.totalPaid, 5000);
      expect(summary.debt, 15000);
      final pays = await db.select(db.payments).get();
      expect(pays.single.paymentNo, 'P-M-2026-0001');
    });

    test('رفض العربون الأكبر من السعر والزبون من محل آخر', () async {
      final m = await newCustomer();
      final w = await newCustomer(shop: womenShop, phone: '0508888888');
      await expectLater(orders.create(actor, input(m, price: 1000, deposit: 2000)),
          throwsA(isA<AppException>()));
      await expectLater(orders.create(actor, input(w, shop: menShop)),
          throwsA(isA<AppException>()));
      expect(await db.select(db.orders).get(), isEmpty);
    });

    test('المقاسات نسخة ثابتة لا تتأثر بتعديل سجل الزبون', () async {
      final cu = await newCustomer();
      final mid = await measurements.create(
          actorId: actor, customerId: cu, label: 'أ', values: {'الصدر': '50'});
      final oid = await orders.create(actor, input(cu, measurementId: mid));
      await measurements.update(
          actorId: actor, id: mid, label: 'أ', values: {'الصدر': '99'});
      final snap = jsonDecode((await orders.measurementSnapshot(oid))!) as Map;
      expect(snap['الصدر'], '50');
    });

    test('سجل الحالات وقيود الانتقال', () async {
      final cu = await newCustomer();
      final id = await orders.create(actor, input(cu));
      await orders.changeStatus(actor, id, OrderStatus.cutting, 'بدأ القص');
      await expectLater(orders.changeStatus(actor, id, OrderStatus.cutting, null),
          throwsA(isA<AppException>()));
      await expectLater(orders.changeStatus(actor, id, OrderStatus.cancelled, '  '),
          throwsA(isA<AppException>()));
      await orders.changeStatus(actor, id, OrderStatus.cancelled, 'طلب الزبون');
      await expectLater(orders.changeStatus(actor, id, OrderStatus.sewing, null),
          throwsA(isA<AppException>()));

      final history = await orders.watchHistory(id).first;
      expect(history.map((h) => h.newStatus),
          [OrderStatus.cancelled, OrderStatus.cutting, OrderStatus.newOrder]);
      expect(history[1].oldStatus, OrderStatus.newOrder);
      expect(history[1].userId, actor);

      // الطلب الملغي لا يُحتسب في الدين
      expect((await customers.watchSummary(cu).first).totalPrice, 0);
    });

    test('التعديل لا يسمح بسعر أقل من المدفوع ولا يمس الدفعات', () async {
      final cu = await newCustomer();
      final id = await orders.create(actor, input(cu, price: 10000, deposit: 6000));
      await expectLater(orders.update(actor, id, input(cu, price: 5000)),
          throwsA(isA<AppException>()));
      await orders.update(actor, id, input(cu, price: 12000));
      expect((await orders.getById(id)).price, 12000);
      expect(await orders.paidFor(id), 6000);
      final log = await db.select(db.auditLogs).get();
      expect(log.any((e) => e.action == 'update_order' && (e.details ?? '').contains('→')),
          isTrue);
    });

    test('التأخر: بعد موعد التسليم وغير المسلَّم فقط', () async {
      final cu = await newCustomer();
      final id = await orders.create(actor, input(cu));
      final o = await orders.getById(id);
      expect(OrderStatus.isLate(o, DateTime(2026, 3, 10)), isFalse);
      expect(OrderStatus.isLate(o, DateTime(2026, 3, 11)), isTrue);
      await orders.changeStatus(actor, id, OrderStatus.delivered, null);
      final d = await orders.getById(id);
      expect(OrderStatus.isLate(d, DateTime(2026, 4, 1)), isFalse);
    });

    test('الفلترة والبحث', () async {
      final cu = await newCustomer(phone: '0501112222');
      final a = await orders.create(actor, input(cu));
      await orders.create(actor, input(cu));
      await orders.changeStatus(actor, a, OrderStatus.delivered, null);
      expect((await orders.watch(activeOnly: true).first).length, 1);
      expect((await orders.watch(status: OrderStatus.delivered).first).length, 1);
      expect((await orders.watch(query: 'M-2026-0002').first).length, 1);
      expect((await orders.watch(query: '0501112222').first).length, 2);
      expect((await orders.watch(shopId: womenShop).first), isEmpty);
    });
  });
}
