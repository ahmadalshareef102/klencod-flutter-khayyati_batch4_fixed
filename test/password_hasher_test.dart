import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:khayyati/core/security/password_hasher.dart';

String hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2-HMAC-SHA256 يطابق متجهات الاختبار القياسية', () {
    final pw = utf8.encode('password');
    final salt = utf8.encode('salt');
    expect(hex(pbkdf2Sha256(pw, salt, 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(pbkdf2Sha256(pw, salt, 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  });

  test('hash ثم verify، وملح مختلف لكل تجزئة', () async {
    final h = PasswordHasher(iterations: 1000);
    final a = await h.hash('كلمة-سر-قوية-123');
    final b = await h.hash('كلمة-سر-قوية-123');
    expect(a.hash, isNot(b.hash));
    expect(a.salt, isNot(b.salt));
    expect(
        await h.verify('كلمة-سر-قوية-123',
            hash: a.hash, salt: a.salt, iterations: a.iterations),
        isTrue);
    expect(
        await h.verify('خطأ',
            hash: a.hash, salt: a.salt, iterations: a.iterations),
        isFalse);
  });
}
