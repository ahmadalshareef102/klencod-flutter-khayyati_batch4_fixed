import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 بطول مخرجات 32 بايت (كتلة واحدة).
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  final block = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);
  block[salt.length + 3] = 1;
  var u = hmac.convert(block).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return Uint8List.fromList(t);
}

class HashedPassword {
  const HashedPassword(this.hash, this.salt, this.iterations);
  final String hash;
  final String salt;
  final int iterations;
}

class PasswordHasher {
  PasswordHasher({this.iterations = defaultIterations});

  static const defaultIterations = 60000;
  final int iterations;

  Future<HashedPassword> hash(String password) async {
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    final pw = utf8.encode(password);
    final iters = iterations;
    final out = await Isolate.run(() => pbkdf2Sha256(pw, salt, iters));
    return HashedPassword(base64Encode(out), base64Encode(salt), iters);
  }

  Future<bool> verify(
    String password, {
    required String hash,
    required String salt,
    required int iterations,
  }) async {
    final pw = utf8.encode(password);
    final saltBytes = base64Decode(salt);
    final out = await Isolate.run(() => pbkdf2Sha256(pw, saltBytes, iterations));
    final expected = base64Decode(hash);
    if (expected.length != out.length) return false;
    var diff = 0; // مقارنة بزمن ثابت
    for (var i = 0; i < out.length; i++) {
      diff |= out[i] ^ expected[i];
    }
    return diff == 0;
  }
}
