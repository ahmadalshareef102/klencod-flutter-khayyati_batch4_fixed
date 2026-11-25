import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/security/password_hasher.dart';
import '../../data/db/app_database.dart';

class AuthRepository {
  AuthRepository(this.db, {PasswordHasher? hasher})
      : hasher = hasher ?? PasswordHasher();

  final AppDatabase db;
  final PasswordHasher hasher;

  static String normalize(String username) => username.trim().toLowerCase();

  void _validate(String fullName, String username, String password) {
    if (fullName.trim().isEmpty) throw AppException('الاسم مطلوب');
    if (normalize(username).length < 3) {
      throw AppException('اسم المستخدم يجب أن لا يقل عن 3 أحرف');
    }
    if (normalize(username).contains(' ')) {
      throw AppException('اسم المستخدم لا يجوز أن يحتوي على مسافات');
    }
    validatePassword(password);
  }

  void validatePassword(String password) {
    if (password.length < 8) {
      throw AppException('كلمة المرور يجب أن لا تقل عن 8 أحرف');
    }
  }

  Future<bool> adminExists() async {
    final rows = await (db.select(db.users)
          ..where((u) => u.role.equals(Roles.admin))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Future<User> createAdmin({
    required String fullName,
    required String username,
    required String password,
  }) async {
    _validate(fullName, username, password);
    if (await adminExists()) {
      throw AppException('تم إنشاء حساب المدير مسبقاً');
    }
    final user = await _insertUser(
      fullName: fullName,
      username: username,
      password: password,
      role: Roles.admin,
    );
    await db.audit(
        userId: user.id, action: 'create_admin', entity: 'user', entityId: user.id);
    return user;
  }

  Future<User> createWorker({
    required int actorId,
    required String fullName,
    required String username,
    required String password,
    required int shopId,
    String? phone,
    String? jobTitle,
    bool canCreateOrders = true,
    bool canViewProfits = false,
    bool canAccessOtherShop = false,
  }) async {
    _validate(fullName, username, password);
    final user = await _insertUser(
      fullName: fullName,
      username: username,
      password: password,
      role: Roles.worker,
      shopId: shopId,
      phone: phone,
      jobTitle: jobTitle,
      canCreateOrders: canCreateOrders,
      canViewProfits: canViewProfits,
      canAccessOtherShop: canAccessOtherShop,
    );
    await db.audit(
        userId: actorId,
        shopId: shopId,
        action: 'create_worker',
        entity: 'user',
        entityId: user.id,
        details: user.username);
    return user;
  }

  Future<User> _insertUser({
    required String fullName,
    required String username,
    required String password,
    required String role,
    int? shopId,
    String? phone,
    String? jobTitle,
    bool canCreateOrders = true,
    bool canViewProfits = false,
    bool canAccessOtherShop = false,
  }) async {
    final name = normalize(username);
    final existing = await (db.select(db.users)
          ..where((u) => u.username.equals(name)))
        .getSingleOrNull();
    if (existing != null) throw AppException('اسم المستخدم مستخدم مسبقاً');
    final h = await hasher.hash(password);
    final id = await db.into(db.users).insert(UsersCompanion.insert(
          fullName: fullName.trim(),
          username: name,
          passwordHash: h.hash,
          salt: h.salt,
          iterations: h.iterations,
          role: role,
          shopId: Value(shopId),
          phone: Value(_blankToNull(phone)),
          jobTitle: Value(_blankToNull(jobTitle)),
          canCreateOrders: Value(canCreateOrders),
          canViewProfits: Value(canViewProfits),
          canAccessOtherShop: Value(canAccessOtherShop),
        ));
    return (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();
  }

  String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<User> login(String username, String password) async {
    const bad = 'اسم المستخدم أو كلمة المرور غير صحيحة';
    final user = await (db.select(db.users)
          ..where((u) => u.username.equals(normalize(username))))
        .getSingleOrNull();
    if (user == null) throw AppException(bad);
    final ok = await hasher.verify(password,
        hash: user.passwordHash, salt: user.salt, iterations: user.iterations);
    if (!ok) {
      await db.audit(
          userId: user.id, action: 'login_failed', entity: 'user', entityId: user.id);
      throw AppException(bad);
    }
    if (!user.isActive) {
      throw AppException('هذا الحساب معطّل، راجع المدير');
    }
    await db.audit(
        userId: user.id, action: 'login', entity: 'user', entityId: user.id);
    return user;
  }

  Future<void> changePassword(
      int userId, String oldPassword, String newPassword) async {
    validatePassword(newPassword);
    final user =
        await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingle();
    final ok = await hasher.verify(oldPassword,
        hash: user.passwordHash, salt: user.salt, iterations: user.iterations);
    if (!ok) throw AppException('كلمة المرور الحالية غير صحيحة');
    final h = await hasher.hash(newPassword);
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
            passwordHash: Value(h.hash),
            salt: Value(h.salt),
            iterations: Value(h.iterations)));
    await db.audit(
        userId: userId, action: 'change_password', entity: 'user', entityId: userId);
  }

  Future<void> setActive(int actorId, int userId, bool active) async {
    final user =
        await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingle();
    if (user.role == Roles.admin) {
      throw AppException('لا يمكن تعطيل حساب المدير');
    }
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(isActive: Value(active)));
    await db.audit(
        userId: actorId,
        shopId: user.shopId,
        action: active ? 'activate_user' : 'deactivate_user',
        entity: 'user',
        entityId: userId);
  }

  Future<void> updateShop(
      int actorId, int shopId, String name, String? phone, String? address,
      {String? logoPath}) async {
    if (name.trim().isEmpty) throw AppException('اسم المحل مطلوب');
    await (db.update(db.shops)..where((s) => s.id.equals(shopId))).write(
        ShopsCompanion(
            name: Value(name.trim()),
            phone: Value(_blankToNull(phone)),
            address: Value(_blankToNull(address)),
            logoPath: Value(logoPath)));
    await db.audit(
        userId: actorId,
        shopId: shopId,
        action: 'update_shop',
        entity: 'shop',
        entityId: shopId);
  }
}
