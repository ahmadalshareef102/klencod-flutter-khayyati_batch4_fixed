import 'package:flutter/material.dart';

import '../constants.dart';
import '../../data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppColors {
  static const navy = Color(0xFF1A2B4C); // الإدارة والرجالي
  static const plum = Color(0xFF7B2D5B); // العبايات النسائية
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFEF6C00);
}

/// لون التطبيق يتغير حسب المحل المحدد: كحلي للإدارة/الرجالي، عنابي للنسائي.
final accentSeedProvider = Provider<Color>((ref) {
  final shop = ref.watch(currentShopProvider);
  return shop?.type == ShopTypes.women ? AppColors.plum : AppColors.navy;
});

class AppTheme {
  static ThemeData light(Color seed) => _build(seed, Brightness.light);
  static ThemeData dark(Color seed) => _build(seed, Brightness.dark);

  static ThemeData _build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Cairo', // يرجع للخط الافتراضي إن لم يُضَف الخط للمشروع
      scaffoldBackgroundColor:
          brightness == Brightness.light ? const Color(0xFFF7F8FB) : null,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
