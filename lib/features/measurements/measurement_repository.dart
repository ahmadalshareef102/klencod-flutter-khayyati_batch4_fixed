import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';

class MeasurementFields {
  static const men = [
    'طول الثوب',
    'الكتف',
    'الصدر',
    'الخصر',
    'الأرداف',
    'طول الكم',
    'عرض الكم',
    'الرقبة',
    'فتحة اليد',
    'طول الجنب',
  ];

  /// مأخوذة من نموذج المحل الورقي لمركز ملكة الجمال.
  static const women = [
    'الطول',
    'العرض',
    'الخصر',
    'الورك',
    'الكتف',
    'يد الإبط',
    'وسع اليد',
    'فتحة اليد',
    'كلوش',
  ];

  static List<String> defaultsFor(String shopType) =>
      shopType == ShopTypes.women ? women : men;

  static Map<String, String> decode(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }
}

class MeasurementRepository {
  MeasurementRepository(this.db);
  final AppDatabase db;

  static const _extraKey = 'measure_extra_fields';

  Future<List<String>> extraFields(int shopId) async {
    final raw = await db.getSetting(_extraKey, shopId: shopId);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addExtraField(int shopId, String name) async {
    final n = name.trim();
    if (n.isEmpty) throw AppException('اسم الحقل مطلوب');
    final shop =
        await (db.select(db.shops)..where((s) => s.id.equals(shopId))).getSingle();
    final extras = await extraFields(shopId);
    if (MeasurementFields.defaultsFor(shop.type).contains(n) || extras.contains(n)) {
      throw AppException('هذا الحقل موجود مسبقاً');
    }
    await db.setSetting(_extraKey, jsonEncode([...extras, n]), shopId: shopId);
  }

  /// تنظيف القيم: تجاهل الفارغ، تحويل الأرقام العربية، رفض غير الرقمي.
  Map<String, String> _clean(Map<String, String> values) {
    final out = <String, String>{};
    values.forEach((k, v) {
      if (v.trim().isEmpty) return;
      final d = parseDecimal(v);
      if (d == null || d < 0) throw AppException('قيمة غير صحيحة في الحقل: $k');
      out[k] = d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    });
    if (out.isEmpty) throw AppException('أدخل مقاساً واحداً على الأقل');
    return out;
  }

  Stream<List<Measurement>> watchForCustomer(int customerId) {
    return (db.select(db.measurements)
          ..where((m) => m.customerId.equals(customerId))
          ..orderBy([
            (m) => OrderingTerm.desc(m.createdAt),
            (m) => OrderingTerm.desc(m.id),
          ]))
        .watch();
  }

  Future<Measurement> getById(int id) =>
      (db.select(db.measurements)..where((m) => m.id.equals(id))).getSingle();

  Future<int> create({
    required int actorId,
    required int customerId,
    required String label,
    required Map<String, String> values,
  }) async {
    final clean = _clean(values);
    return db.transaction(() async {
      final c = await (db.select(db.customers)..where((x) => x.id.equals(customerId)))
          .getSingle();
      final id = await db.into(db.measurements).insert(MeasurementsCompanion.insert(
            customerId: customerId,
            shopId: c.shopId,
            label: Value(label.trim().isEmpty ? 'سجل مقاسات' : label.trim()),
            valuesJson: jsonEncode(clean),
          ));
      await db.audit(
          userId: actorId,
          shopId: c.shopId,
          action: 'create_measurement',
          entity: 'measurement',
          entityId: id);
      return id;
    });
  }

  /// تعديل السجل لا يغيّر مقاسات الطلبات القديمة (لأنها نسخ ثابتة).
  Future<void> update({
    required int actorId,
    required int id,
    required String label,
    required Map<String, String> values,
  }) async {
    final clean = _clean(values);
    await db.transaction(() async {
      final m = await getById(id);
      await (db.update(db.measurements)..where((x) => x.id.equals(id))).write(
          MeasurementsCompanion(
            label: Value(label.trim().isEmpty ? 'سجل مقاسات' : label.trim()),
            valuesJson: Value(jsonEncode(clean)),
            updatedAt: Value(DateTime.now()),
          ));
      await db.audit(
          userId: actorId,
          shopId: m.shopId,
          action: 'update_measurement',
          entity: 'measurement',
          entityId: id);
    });
  }

  Future<int> duplicate(int actorId, int id) async {
    return db.transaction(() async {
      final m = await getById(id);
      final newId = await db.into(db.measurements).insert(MeasurementsCompanion.insert(
            customerId: m.customerId,
            shopId: m.shopId,
            label: Value('نسخة من ${m.label}'),
            valuesJson: m.valuesJson,
          ));
      await db.audit(
          userId: actorId,
          shopId: m.shopId,
          action: 'duplicate_measurement',
          entity: 'measurement',
          entityId: newId);
      return newId;
    });
  }

  Future<void> delete(int actorId, int id) async {
    await db.transaction(() async {
      final m = await getById(id);
      await (db.delete(db.measurements)..where((x) => x.id.equals(id))).go();
      await db.audit(
          userId: actorId,
          shopId: m.shopId,
          action: 'delete_measurement',
          entity: 'measurement',
          entityId: id);
    });
  }
}
