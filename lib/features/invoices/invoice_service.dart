import 'package:drift/drift.dart' show OrderingTerm;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants.dart';
import '../../core/image_store.dart';
import '../../data/db/app_database.dart';
import '../measurements/measurement_repository.dart';
import '../orders/order_repository.dart';
import 'invoice_models.dart';
import 'invoice_pdf.dart';

/// تحميل خطوط PDF المضمّنة في التطبيق (تعمل بدون إنترنت).
Future<PdfFonts> loadAssetFonts() async {
  final regular = await rootBundle.load('assets/fonts/pdf/DejaVuSans.ttf');
  final bold = await rootBundle.load('assets/fonts/pdf/DejaVuSans-Bold.ttf');
  return PdfFonts(regular, bold);
}

/// تحميل صورة محفوظة محلياً (شعار أو رسم). يرجع null عند عدم وجودها.
Future<Uint8List?> loadStoredImage(String relativePath) async {
  try {
    final File f = await ImageStore.resolve(relativePath);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

class InvoiceService {
  InvoiceService(
    this.db, {
    this.fontLoader = loadAssetFonts,
    this.imageLoader = loadStoredImage,
  });

  final AppDatabase db;
  final Future<PdfFonts> Function() fontLoader;
  final Future<Uint8List?> Function(String relativePath) imageLoader;

  late final _settings = InvoiceSettingsRepository(db);
  late final _orders = OrderRepository(db);
  late final _measurements = MeasurementRepository(db);

  /// رقم الفاتورة مشتق من رقم الطلب: ثابت وفريد.
  static String invoiceNoFor(String orderNo) => 'INV-$orderNo';

  Future<InvoiceModel> invoiceModel(int orderId) async {
    final order = await _orders.getById(orderId);
    final customer = await (db.select(db.customers)
          ..where((c) => c.id.equals(order.customerId)))
        .getSingle();
    final shop =
        await (db.select(db.shops)..where((s) => s.id.equals(order.shopId))).getSingle();
    final settings = await _settings.load(shop.id);
    final pays = await (db.select(db.payments)
          ..where((p) => p.orderId.equals(orderId))
          ..where((p) => p.voidedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.paidAt), (p) => OrderingTerm.asc(p.id)]))
        .get();
    final paid = pays.fold<int>(0, (s, p) => s + p.amount);
    final logo = shop.logoPath == null ? null : await imageLoader(shop.logoPath!);
    return InvoiceModel(
      shopName: shop.name,
      shopPhone: shop.phone,
      shopAddress: shop.address,
      logo: logo,
      invoiceNo: invoiceNoFor(order.orderNo),
      orderNo: order.orderNo,
      orderDate: order.orderDate,
      dueDate: order.dueDate,
      customerName: customer.name,
      customerPhone: customer.phone,
      garmentType: order.garmentType,
      model: order.model,
      fabricType: order.fabricType,
      color: order.color,
      details: order.details,
      notes: order.notes,
      price: order.price,
      paid: paid,
      payments: [for (final p in pays) InvoicePayment(p.paidAt, p.method, p.amount)],
      settings: settings,
      isWomen: shop.type == ShopTypes.women,
    );
  }

  Future<SheetModel> sheetModel(int orderId) async {
    final order = await _orders.getById(orderId);
    final customer = await (db.select(db.customers)
          ..where((c) => c.id.equals(order.customerId)))
        .getSingle();
    final shop =
        await (db.select(db.shops)..where((s) => s.id.equals(order.shopId))).getSingle();
    final settings = await _settings.load(shop.id);
    final paid = await _orders.paidFor(orderId);

    final snapshot = MeasurementFields.decode(await _orders.measurementSnapshot(orderId) ?? '{}');
    final defaults = MeasurementFields.defaultsFor(shop.type);
    final extras = await _measurements.extraFields(shop.id);
    final names = <String>[
      ...defaults,
      ...extras,
      ...snapshot.keys.where((k) => !defaults.contains(k) && !extras.contains(k)),
    ];
    // نُبقي الحقول الافتراضية دائماً، والإضافية فقط إن كانت لها قيمة.
    final shown = names.where((n) => defaults.contains(n) || (snapshot[n] ?? '').isNotEmpty);

    final logo = shop.logoPath == null ? null : await imageLoader(shop.logoPath!);
    final sketch = order.sketchPath == null ? null : await imageLoader(order.sketchPath!);
    final fabric = [order.fabricType, order.color]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(' - ');
    final title = [order.garmentType, order.model]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(' ');

    return SheetModel(
      shopName: shop.name,
      logo: logo,
      orderNo: order.orderNo,
      customerName: customer.name,
      customerPhone: customer.phone,
      orderTitle: title.isEmpty ? null : title,
      fabric: fabric.isEmpty ? null : fabric,
      details: order.details,
      price: order.price,
      paid: paid,
      orderDate: order.orderDate,
      dueDate: order.dueDate,
      measureFields: [for (final n in shown) MapEntry(n, snapshot[n] ?? '')],
      sketch: sketch,
      settings: settings,
    );
  }

  Future<Uint8List> invoicePdf(int orderId) async =>
      buildInvoicePdf(await invoiceModel(orderId), await fontLoader());

  Future<Uint8List> sheetPdf(int orderId) async =>
      buildSheetPdf([await sheetModel(orderId)], await fontLoader());
}
