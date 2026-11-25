import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khayyati/core/constants.dart';
import 'package:khayyati/core/security/password_hasher.dart';
import 'package:khayyati/data/db/app_database.dart';
import 'package:khayyati/features/auth/auth_repository.dart';

void main() {
  late AppDatabase db;
  late AuthRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AuthRepository(db, hasher: PasswordHasher(iterations: 1000));
  });
  tearDown(() => db.close());

  test('يُنشئ المحلين عند أول تشغيل', () async {
    final shops = await db.select(db.shops).get();
    expect(shops.map((s) => s.type), [ShopTypes.men, ShopTypes.women]);
  });

  test('إنشاء المدير مرة واحدة فقط وكلمة المرور غير مخزنة كنص', () async {
    expect(await repo.adminExists(), isFalse);
    final admin = await repo.createAdmin(
        fullName: 'المدير', username: 'Admin', password: 'password123');
    expect(admin.username, 'admin');
    expect(admin.passwordHash, isNot(contains('password123')));
    expect(await repo.adminExists(), isTrue);
    await expectLater(
      repo.createAdmin(
          fullName: 'آخر', username: 'other', password: 'password123'),
      throwsA(isA<AppException>()),
    );
  });

  test('تسجيل الدخول: نجاح وفشل وحساب معطّل', () async {
    final admin = await repo.createAdmin(
        fullName: 'المدير', username: 'admin', password: 'password123');
    expect((await repo.login(' ADMIN ', 'password123')).id, admin.id);
    await expectLater(
      repo.login('admin', 'wrong-pass'),
      throwsA(isA<AppException>()),
    );

    final w = await repo.createWorker(
        actorId: admin.id,
        fullName: 'عامل',
        username: 'worker1',
        password: 'workerpass1',
        shopId: 1);
    await repo.setActive(admin.id, w.id, false);
    await expectLater(
      repo.login('worker1', 'workerpass1'),
      throwsA(isA<AppException>()),
    );
    await repo.setActive(admin.id, w.id, true);
    expect((await repo.login('worker1', 'workerpass1')).shopId, 1);
  });

  test('منع اسم مستخدم مكرر وكلمة مرور قصيرة', () async {
    final admin = await repo.createAdmin(
        fullName: 'المدير', username: 'admin', password: 'password123');
    await expectLater(
      repo.createWorker(
          actorId: admin.id,
          fullName: 'x',
          username: 'ADMIN',
          password: 'password123',
          shopId: 1),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      repo.createWorker(
          actorId: admin.id,
          fullName: 'x',
          username: 'short',
          password: '123',
          shopId: 1),
      throwsA(isA<AppException>()),
    );
  });

  test('تغيير كلمة المرور يتطلب القديمة ويُسجَّل في سجل العمليات', () async {
    final admin = await repo.createAdmin(
        fullName: 'المدير', username: 'admin', password: 'password123');
    await expectLater(
      repo.changePassword(admin.id, 'bad', 'newpassword1'),
      throwsA(isA<AppException>()),
    );
    await repo.changePassword(admin.id, 'password123', 'newpassword1');
    expect((await repo.login('admin', 'newpassword1')).id, admin.id);
    final log = await db.select(db.auditLogs).get();
    expect(log.map((e) => e.action), contains('change_password'));
  });

  test('المفاتيح الأجنبية مفعّلة: لا زبون بمحل غير موجود', () async {
    // تحقق أولاً من حالة SQLite الفعلية على اتصال الاختبار.
    final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(pragma.data['foreign_keys'], 1,
        reason: 'يجب تفعيل المفاتيح الأجنبية عند فتح قاعدة البيانات');

    // لا نمرر closure يعيد Future إلى expect؛ ننتظر Future مباشرة.
    await expectLater(
      db.into(db.customers).insert(CustomersCompanion.insert(
        shopId: 999,
        name: 'زبون',
        phone: '0500000000',
      )),
      throwsA(anything),
    );
  });
}
