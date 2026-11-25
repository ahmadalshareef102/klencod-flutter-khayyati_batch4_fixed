import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';

enum InvoiceFormat { a4, thermal }

class InvoiceSettings {
  const InvoiceSettings({
    this.format = InvoiceFormat.a4,
    this.thermalMm = 80,
    this.thanks = 'شكراً لثقتكم بنا',
    this.notes,
    this.currency = '',
  });

  final InvoiceFormat format;

  /// عرض الورق الحراري بالمليمتر (58 أو 80 أو مقاس مخصص).
  final int thermalMm;
  final String thanks;
  final String? notes;
  final String currency;
}

/// إعدادات الفاتورة لكل محل (مستقلة بين المحلين).
class InvoiceSettingsRepository {
  InvoiceSettingsRepository(this.db);
  final AppDatabase db;

  Future<InvoiceSettings> load(int shopId) async {
    final format = await db.getSetting('invoice_format', shopId: shopId);
    final mm = int.tryParse(await db.getSetting('invoice_thermal_mm', shopId: shopId) ?? '');
    final thanks = await db.getSetting('invoice_thanks', shopId: shopId);
    final notes = await db.getSetting('invoice_notes', shopId: shopId);
    final currency = await db.getSetting('currency', shopId: shopId);
    return InvoiceSettings(
      format: format == 'thermal' ? InvoiceFormat.thermal : InvoiceFormat.a4,
      thermalMm: (mm != null && mm >= 40 && mm <= 120) ? mm : 80,
      thanks: (thanks == null || thanks.trim().isEmpty) ? 'شكراً لثقتكم بنا' : thanks,
      notes: blankToNull(notes),
      currency: currency ?? '',
    );
  }

  Future<void> save(int actorId, int shopId, InvoiceSettings s) async {
    if (s.format == InvoiceFormat.thermal && (s.thermalMm < 40 || s.thermalMm > 120)) {
      throw AppException('عرض الورق الحراري يجب أن يكون بين 40 و120 مم');
    }
    await requireAdmin(db, actorId);
    await db.transaction(() async {
      await db.setSetting(
          'invoice_format', s.format == InvoiceFormat.thermal ? 'thermal' : 'a4',
          shopId: shopId);
      await db.setSetting('invoice_thermal_mm', '${s.thermalMm}', shopId: shopId);
      await db.setSetting('invoice_thanks', s.thanks.trim(), shopId: shopId);
      await db.setSetting('invoice_notes', s.notes ?? '', shopId: shopId);
      await db.setSetting('currency', s.currency.trim(), shopId: shopId);
      await db.audit(
          userId: actorId,
          shopId: shopId,
          action: 'update_invoice_settings',
          entity: 'setting');
    });
  }
}

class InvoicePayment {
  const InvoicePayment(this.date, this.method, this.amount);
  final DateTime date;
  final String method;
  final int amount;
}

class InvoiceModel {
  const InvoiceModel({
    required this.shopName,
    this.shopPhone,
    this.shopAddress,
    this.logo,
    required this.invoiceNo,
    required this.orderNo,
    required this.orderDate,
    this.dueDate,
    required this.customerName,
    required this.customerPhone,
    this.garmentType,
    this.model,
    this.fabricType,
    this.color,
    this.details,
    this.notes,
    required this.price,
    required this.paid,
    this.payments = const [],
    required this.settings,
    this.isWomen = false,
  });

  final String shopName;
  final String? shopPhone;
  final String? shopAddress;
  final Uint8List? logo;
  final String invoiceNo;
  final String orderNo;
  final DateTime orderDate;
  final DateTime? dueDate;
  final String customerName;
  final String customerPhone;
  final String? garmentType;
  final String? model;
  final String? fabricType;
  final String? color;
  final String? details;
  final String? notes;
  final int price;
  final int paid;
  final List<InvoicePayment> payments;
  final InvoiceSettings settings;
  final bool isWomen;

  int get remaining => price - paid;
}

/// بيانات ورقة الطلب (بتصميم نموذج المحل الورقي).
class SheetModel {
  const SheetModel({
    required this.shopName,
    this.logo,
    required this.orderNo,
    required this.customerName,
    required this.customerPhone,
    this.orderTitle,
    this.fabric,
    this.details,
    required this.price,
    required this.paid,
    required this.orderDate,
    this.dueDate,
    required this.measureFields,
    this.sketch,
    required this.settings,
  });

  final String shopName;
  final Uint8List? logo;
  final String orderNo;
  final String customerName;
  final String customerPhone;
  final String? orderTitle;
  final String? fabric;
  final String? details;
  final int price;
  final int paid;
  final DateTime orderDate;
  final DateTime? dueDate;

  /// (اسم الحقل ← القيمة أو فارغ) بترتيب العرض.
  final List<MapEntry<String, String>> measureFields;
  final Uint8List? sketch;
  final InvoiceSettings settings;

  int get remaining => price - paid;
}
