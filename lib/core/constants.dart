class ShopTypes {
  static const men = 'men';
  static const women = 'women';
}

class Roles {
  static const admin = 'admin';
  static const worker = 'worker';
}

/// رسالة خطأ مفهومة للمستخدم (بالعربية).
class AppException implements Exception {
  AppException(this.message);
  final String message;
  @override
  String toString() => message;
}
