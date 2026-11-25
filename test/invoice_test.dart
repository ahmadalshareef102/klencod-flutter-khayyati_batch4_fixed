import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khayyati/core/constants.dart';
import 'package:khayyati/core/security/password_hasher.dart';
import 'package:khayyati/data/db/app_database.dart';
import 'package:khayyati/features/auth/auth_repository.dart';
import 'package:khayyati/features/customers/customer_repository.dart';
import 'package:khayyati/features/invoices/invoice_models.dart';
import 'package:khayyati/features/invoices/invoice_pdf.dart';
import 'package:khayyati/features/invoices/invoice_service.dart';
import 'package:khayyati/features/measurements/measurement_repository.dart';
import 'package:khayyati/features/orders/order_repository.dart';
import 'package:khayyati/features/payments/payment_repository.dart';

Future<PdfFonts> _fonts() async {
  ByteData read(String p) => ByteData.sublistView(File(p).readAsBytesSync());
  return PdfFonts(
    read('assets/fonts/pdf/DejaVuSans.ttf'),
    read('assets/fonts/pdf/DejaVuSans-Bold.ttf'),
  );
}

bool _isPdf(Uint8List b) =>
    b.length > 1500 && String.fromCharCodes(b.sublist(0, 5)) == '%PDF-';

void main() {
  late AppDatabase db;
  late InvoiceService svc;
  late OrderRepository orders;
  late PaymentRepository payments;
  late int admin;
  late int womenOrder;

  const womenShop = 2;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final auth = AuthRepository(db, hasher: PasswordHasher(iterations: 1000));
    admin = (await auth.createAdmin(
            fullName: 'المدير', username: 'admin', password: 'password123'))
        .id;
    orders = OrderRepository(db);
    payments = PaymentRepository(db);
    svc = InvoiceService(db, fontLoader: _fonts, imageLoader: (_) async => null);

    final customers = CustomerRepository(db);
    final cust = await customers.create(
        actorId: admin, shopId: womenShop, name: 'فاطمة محمد', phone: '0501234567');
    final mid = await MeasurementRepository(db).create(
        actorId: admin,
        customerId: cust,
        label: 'عباية',
        values: {'الطول': '140', 'الكتف': '38', 'كلوش': '60'});
    womenOrder = await orders.create(
        admin,
        OrderInput(
          shopId: womenShop,
          customerId: cust,
          orderDate: DateTime(2026, 3, 1),
          dueDate: DateTime(2026, 3, 10),
          garmentType: 'عباية',
          model: 'كلوش',
          fabricType: 'كريب',
          color: 'أسود',
          details: 'تطريز على الأكمام',
          price: 45000,
          deposit: 10000,
          measurementId: mid,
        ));
  });
  tearDown(() => db.close());

  test('اسم محل العبايات الافتراضي ومقاساته من نموذج المحل', () async {
    final shop = await (db.select(db.shops)..where((s) => s.id.equals(womenShop))).getSingle();
    expect(shop.name, womenShopDefaultName);
    expect(MeasurementFields.women.length, 9);
    expect(MeasurementFields.women.first, 'الطول');
    expect(MeasurementFields.women, containsAll(['يد الإبط', 'وسع اليد', 'فتحة اليد', 'كلوش']));
  });

  test('نموذج الفاتورة: رقم مشتق والمدفوع بدون الدفعات المُبطلة', () async {
    final p = await payments.add(
        actorId: admin, orderId: womenOrder, amount: 5000, paidAt: DateTime(2026, 3, 2));
    var m = await svc.invoiceModel(womenOrder);
    expect(m.invoiceNo, 'INV-W-2026-0001');
    expect(m.paid, 15000);
    expect(m.remaining, 30000);
    expect(m.isWomen, isTrue);
    expect(m.payments.length, 2);
    await payments.voidPayment(admin, p, 'خطأ');
    m = await svc.invoiceModel(womenOrder);
    expect(m.paid, 10000);
    expect(m.payments.length, 1);
  });

  test('PDF للفاتورة (A4 وحراري) يُولَّد بنجاح بالعربية', () async {
    expect(_isPdf(await svc.invoicePdf(womenOrder)), isTrue);

    final repo = InvoiceSettingsRepository(db);
    await repo.save(
        admin,
        womenShop,
        const InvoiceSettings(
            format: InvoiceFormat.thermal,
            thermalMm: 58,
            currency: 'ر.س',
            thanks: 'شكراً لزيارتكم',
            notes: 'لا يرد المبلغ بعد التفصيل'));
    final s = await repo.load(womenShop);
    expect(s.format, InvoiceFormat.thermal);
    expect(s.thermalMm, 58);
    expect(s.currency, 'ر.س');
    expect(_isPdf(await svc.invoicePdf(womenOrder)), isTrue);
  });

  test('ورقة الطلب: تسعة مقاسات وقيم الطلب، وعدة أوراق', () async {
    final sheet = await svc.sheetModel(womenOrder);
    expect(sheet.measureFields.map((e) => e.key).toList(), MeasurementFields.women);
    final values = {for (final e in sheet.measureFields) e.key: e.value};
    expect(values['الطول'], '140');
    expect(values['كلوش'], '60');
    expect(values['الخصر'], '');
    expect(sheet.orderTitle, 'عباية كلوش');
    expect(sheet.fabric, 'كريب - أسود');
    expect(sheet.remaining, 35000);

    expect(_isPdf(await svc.sheetPdf(womenOrder)), isTrue);
    final five = await buildSheetPdf(List.filled(5, sheet), await _fonts());
    expect(_isPdf(five), isTrue);
  });

  test('إعدادات الفاتورة: للمدير فقط وبحدود صحيحة، ومستقلة لكل محل', () async {
    final repo = InvoiceSettingsRepository(db);
    final worker = (await AuthRepository(db, hasher: PasswordHasher(iterations: 1000))
            .createWorker(
                actorId: admin,
                fullName: 'عامل',
                username: 'w1',
                password: 'workerpass1',
                shopId: womenShop))
        .id;
    await expectLater(
        repo.save(worker, womenShop, const InvoiceSettings()), throwsA(isA<AppException>()));
    await expectLater(
        repo.save(admin, womenShop,
            const InvoiceSettings(format: InvoiceFormat.thermal, thermalMm: 30)),
        throwsA(isA<AppException>()));
    await repo.save(admin, womenShop, const InvoiceSettings(currency: 'ر.ع'));
    expect((await repo.load(womenShop)).currency, 'ر.ع');
    expect((await repo.load(1)).currency, '');
  });
}
