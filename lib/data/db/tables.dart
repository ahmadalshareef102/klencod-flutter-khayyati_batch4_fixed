import 'package:drift/drift.dart';

// ملاحظة: جميع المبالغ تُخزَّن كأعداد صحيحة (أصغر وحدة للعملة) لتفادي أخطاء الكسور.

class Shops extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // men | women
  TextColumn get logoPath => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  // null = المدير (يصل لكل المحلات)
  IntColumn get shopId => integer().nullable().references(Shops, #id)();
  TextColumn get fullName => text()();
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get salt => text()();
  IntColumn get iterations => integer()();
  TextColumn get phone => text().nullable()();
  TextColumn get jobTitle => text().nullable()();
  TextColumn get role => text()(); // admin | worker
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get canCreateOrders => boolean().withDefault(const Constant(true))();
  BoolColumn get canViewProfits => boolean().withDefault(const Constant(false))();
  BoolColumn get canAccessOtherShop => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shopId => integer().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Measurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get shopId => integer().references(Shops, #id)();
  TextColumn get label => text().withDefault(const Constant('سجل مقاسات'))();
  TextColumn get valuesJson => text()(); // {"اسم الحقل": قيمة}
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderNo => text().unique()();
  IntColumn get shopId => integer().references(Shops, #id)();
  IntColumn get customerId => integer().references(Customers, #id)();
  DateTimeColumn get orderDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get garmentType => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get fabricType => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get details => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get sketchPath => text().nullable()(); // رسم الموديل باليد
  IntColumn get workerId => integer().nullable().references(Users, #id)();
  IntColumn get price => integer().withDefault(const Constant(0))();
  IntColumn get deposit => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('new'))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class OrderMeasurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().unique().references(Orders, #id)();
  TextColumn get valuesJson => text()(); // نسخة ثابتة وقت إنشاء الطلب
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class OrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(Orders, #id)();
  TextColumn get description => text()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  IntColumn get unitPrice => integer().withDefault(const Constant(0))();
}

@DataClassName('OrderStatusChange')
class OrderStatusHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(Orders, #id)();
  TextColumn get oldStatus => text().nullable()();
  TextColumn get newStatus => text()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get note => text().nullable()();
}

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get paymentNo => text().unique()();
  IntColumn get orderId => integer().references(Orders, #id)();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get shopId => integer().references(Shops, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  // لا حذف للدفعات: الإلغاء بتاريخ إبطال وسبب موثّق
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
}

class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shopId => integer().references(Shops, #id)();
  TextColumn get category => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get attachmentPath => text().nullable()();
  DateTimeColumn get voidedAt => dateTime().nullable()();
}

class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shopId => integer().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

class SupplierPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
}

class Fabrics extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shopId => integer().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get type => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get code => text().nullable()();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();
  TextColumn get unit => text().withDefault(const Constant('متر'))();
  RealColumn get quantity => real().withDefault(const Constant(0))();
  IntColumn get unitCost => integer().withDefault(const Constant(0))();
  RealColumn get alertLevel => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

class InventoryTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fabricId => integer().references(Fabrics, #id)();
  IntColumn get shopId => integer().references(Shops, #id)();
  // purchase | receive | deduct | usage | waste | transfer_in | transfer_out | usage_reversal
  TextColumn get type => text()();
  RealColumn get quantity => real()();
  IntColumn get unitCost => integer().withDefault(const Constant(0))();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();
  IntColumn get orderId => integer().nullable().references(Orders, #id)();
  IntColumn get reversesTxnId => integer().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class OrderCosts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(Orders, #id)();
  TextColumn get kind => text()(); // fabric | labor | other
  TextColumn get description => text().nullable()();
  IntColumn get amount => integer()();
  IntColumn get inventoryTxnId =>
      integer().nullable().references(InventoryTransactions, #id)();
  IntColumn get workerId => integer().nullable().references(Users, #id)();
  IntColumn get reversesCostId => integer().nullable()(); // قيد عكسي لتكلفة سابقة
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Settings extends Table {
  IntColumn get shopId => integer().withDefault(const Constant(0))(); // 0 = عام
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column> get primaryKey => {shopId, settingKey};
}

@DataClassName('BackupLogEntry')
class BackupsLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get checksum => text().nullable()();
  TextColumn get kind => text().withDefault(const Constant('backup'))(); // backup | restore
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('AuditEntry')
class AuditLogs extends Table {
  @override
  String get tableName => 'audit_log';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable()();
  IntColumn get shopId => integer().nullable()();
  TextColumn get action => text()();
  TextColumn get entity => text()();
  IntColumn get entityId => integer().nullable()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
