import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/text_utils.dart';
import '../../data/db/app_database.dart';

class ExpenseCategories {
  static const labels = {
    'rent': 'الإيجار',
    'electricity': 'الكهرباء',
    'water': 'الماء',
    'wages': 'الأجور',
    'maintenance': 'الصيانة',
    'transport': 'النقل',
    'materials': 'شراء مواد',
    'other': 'مصروفات أخرى',
  };
  static String label(String k) => labels[k] ?? k;
}

class ExpenseRepository {
  ExpenseRepository(this.db);
  final AppDatabase db;

  Stream<List<Expense>> watch({
    int? shopId,
    required DateTime from,
    required DateTime to,
    String query = '',
    bool includeVoided = false,
  }) {
    final t = query.trim();
    return (db.select(db.expenses)
          ..where((e) {
            Expression<bool> w =
                e.date.isBiggerOrEqualValue(from) & e.date.isSmallerThanValue(to);
            if (shopId != null) w = w & e.shopId.equals(shopId);
            if (!includeVoided) w = w & e.voidedAt.isNull();
            return w;
          })
          ..orderBy([(e) => OrderingTerm.desc(e.date), (e) => OrderingTerm.desc(e.id)]))
        .watch()
        .map((list) => t.isEmpty
            ? list
            : list
                .where((e) =>
                    (e.notes ?? '').contains(t) ||
                    ExpenseCategories.label(e.category).contains(t))
                .toList());
  }

  void _validate(String category, int amount) {
    if (!ExpenseCategories.labels.containsKey(category)) {
      throw AppException('اختر فئة المصروف');
    }
    if (amount <= 0) throw AppException('المبلغ يجب أن يكون أكبر من صفر');
  }

  Future<int> add({
    required int actorId,
    required int shopId,
    required String category,
    required int amount,
    required DateTime date,
    String? notes,
    String? attachmentPath,
  }) async {
    _validate(category, amount);
    await requireFinance(db, actorId);
    return db.transaction(() async {
      final id = await db.into(db.expenses).insert(ExpensesCompanion.insert(
            shopId: shopId,
            category: category,
            amount: amount,
            date: date,
            notes: Value(blankToNull(notes)),
            userId: Value(actorId),
            attachmentPath: Value(attachmentPath),
          ));
      await db.audit(
          userId: actorId,
          shopId: shopId,
          action: 'add_expense',
          entity: 'expense',
          entityId: id,
          details: '${ExpenseCategories.label(category)}: ${formatMoney(amount)}');
      return id;
    });
  }

  Future<void> update({
    required int actorId,
    required int id,
    required String category,
    required int amount,
    required DateTime date,
    String? notes,
  }) async {
    _validate(category, amount);
    await requireAdmin(db, actorId);
    await db.transaction(() async {
      final old =
          await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
      if (old.voidedAt != null) throw AppException('المصروف ملغى ولا يمكن تعديله');
      await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
          ExpensesCompanion(
              category: Value(category),
              amount: Value(amount),
              date: Value(date),
              notes: Value(blankToNull(notes))));
      await db.audit(
          userId: actorId,
          shopId: old.shopId,
          action: 'update_expense',
          entity: 'expense',
          entityId: id,
          details: '${formatMoney(old.amount)} → ${formatMoney(amount)}');
    });
  }

  /// لا حذف نهائي: يُلغى المصروف ويبقى في السجل.
  Future<void> voidExpense(int actorId, int id) async {
    await requireAdmin(db, actorId);
    await db.transaction(() async {
      final old =
          await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
      if (old.voidedAt != null) return;
      await (db.update(db.expenses)..where((e) => e.id.equals(id)))
          .write(ExpensesCompanion(voidedAt: Value(DateTime.now())));
      await db.audit(
          userId: actorId,
          shopId: old.shopId,
          action: 'void_expense',
          entity: 'expense',
          entityId: id,
          details: formatMoney(old.amount));
    });
  }
}
