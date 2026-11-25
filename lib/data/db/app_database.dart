import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants.dart';
import 'tables.dart';

part 'app_database.g.dart';

const womenShopDefaultName = 'مركز ملكة الجمال للعبايات الراقية';

@DriftDatabase(tables: [
  Shops,
  Users,
  Customers,
  Measurements,
  Orders,
  OrderMeasurements,
  OrderItems,
  OrderStatusHistory,
  Payments,
  Expenses,
  Suppliers,
  SupplierPayments,
  Fabrics,
  InventoryTransactions,
  OrderCosts,
  Settings,
  BackupsLog,
  AuditLogs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// قاعدة البيانات الدائمة على الجهاز (SQLite).
  AppDatabase.persistent() : super(driftDatabase(name: 'khayyati'));

  /// رفع الرقم عند أي تغيير في الجداول، وإضافة خطوة في onUpgrade.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await batch((b) {
            b.insertAll(shops, [
              ShopsCompanion.insert(name: 'محل الخياطة الرجالية', type: ShopTypes.men),
              ShopsCompanion.insert(name: womenShopDefaultName, type: ShopTypes.women),
            ]);
          });
        },
        onUpgrade: (m, from, to) async {
          // استراتيجية الترحيل: لكل رقم إصدار جديد أضف هنا خطوة مرتبة.
          if (from < 2) {
            await m.addColumn(orders, orders.sketchPath);
            await m.addColumn(inventoryTransactions, inventoryTransactions.supplierId);
            await m.addColumn(orderCosts, orderCosts.reversesCostId);
            await customStatement(
                "UPDATE shops SET name = '$womenShopDefaultName' "
                "WHERE type = 'women' AND name = 'محل العبايات النسائية'");
          }
        },
        beforeOpen: (details) async {
          // SQLite يعطّل المفاتيح الأجنبية افتراضياً لكل اتصال؛ فعّلها
          // بعد فتح الاتصال ثم تحقق من القيمة الفعلية قبل استخدام القاعدة.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---------- الإعدادات ----------
  Future<String?> getSetting(String key, {int shopId = 0}) async {
    final row = await (select(settings)
          ..where((s) => s.settingKey.equals(key) & s.shopId.equals(shopId)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> setSetting(String key, String value, {int shopId = 0}) {
    return into(settings).insertOnConflictUpdate(SettingsCompanion.insert(
      settingKey: key,
      settingValue: value,
      shopId: Value(shopId),
    ));
  }

  /// عدّاد متسلسل (لأرقام الطلبات والدفعات). يُستدعى داخل transaction.
  Future<int> nextSequence(String key, {int shopId = 0}) async {
    final current = int.tryParse(await getSetting(key, shopId: shopId) ?? '') ?? 0;
    final next = current + 1;
    await setSetting(key, '$next', shopId: shopId);
    return next;
  }

  // ---------- سجل العمليات ----------
  Future<void> audit({
    int? userId,
    int? shopId,
    required String action,
    required String entity,
    int? entityId,
    String? details,
  }) {
    return into(auditLogs).insert(AuditLogsCompanion.insert(
      action: action,
      entity: entity,
      userId: Value(userId),
      shopId: Value(shopId),
      entityId: Value(entityId),
      details: Value(details),
    ));
  }
}
