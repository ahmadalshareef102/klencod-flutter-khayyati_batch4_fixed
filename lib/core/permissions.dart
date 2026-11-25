import '../data/db/app_database.dart';
import 'constants.dart';

bool isAdmin(User? u) => u?.role == Roles.admin;

/// الأمور المالية: المخزون والمصروفات والحسابات والموردون والتكاليف.
bool canManageFinance(User? u) =>
    u != null && (u.role == Roles.admin || u.canViewProfits);

/// إنشاء الطلبات وتسجيل الدفعات.
bool canTakePayments(User? u) =>
    u != null && (u.role == Roles.admin || u.canCreateOrders);

Future<User> _actor(AppDatabase db, int id) =>
    (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();

/// تحقق على مستوى الطبقة البرمجية (وليس الواجهة فقط).
Future<User> requireFinance(AppDatabase db, int actorId) async {
  final u = await _actor(db, actorId);
  if (!u.isActive || !canManageFinance(u)) {
    throw AppException('ليست لديك صلاحية لهذه العملية');
  }
  return u;
}

Future<User> requireAdmin(AppDatabase db, int actorId) async {
  final u = await _actor(db, actorId);
  if (!u.isActive || u.role != Roles.admin) {
    throw AppException('هذه العملية للمدير فقط');
  }
  return u;
}

Future<User> requirePayments(AppDatabase db, int actorId) async {
  final u = await _actor(db, actorId);
  if (!u.isActive || !canTakePayments(u)) {
    throw AppException('ليست لديك صلاحية لتسجيل الدفعات');
  }
  return u;
}
