import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../features/auth/auth_repository.dart';
import 'db/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.persistent();
  ref.onDispose(db.close);
  return db;
});

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(databaseProvider)));

final adminExistsProvider = FutureProvider<bool>(
    (ref) => ref.watch(authRepositoryProvider).adminExists());

final shopsProvider = StreamProvider<List<Shop>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.shops)..orderBy([(s) => OrderingTerm.asc(s.id)])).watch();
});

final staffProvider = StreamProvider<List<User>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)
        ..where((u) => u.role.equals(Roles.worker))
        ..orderBy([(u) => OrderingTerm.asc(u.fullName)]))
      .watch();
});

// ---------- الجلسة ----------
class Session {
  const Session({this.user, this.shopId});
  final User? user;

  /// المحل الحالي. null يعني التقرير الموحد (للمدير فقط).
  final int? shopId;

  bool get isLoggedIn => user != null;
  bool get isAdmin => user?.role == Roles.admin;
}

class SessionNotifier extends StateNotifier<Session> {
  SessionNotifier() : super(const Session());

  void login(User user) => state = Session(user: user, shopId: user.shopId);

  void selectShop(int? shopId) {
    final u = state.user;
    if (u == null) return;
    final allowed = u.role == Roles.admin || shopId == u.shopId;
    if (!allowed) return;
    state = Session(user: u, shopId: shopId);
  }

  void logout() => state = const Session();
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, Session>((ref) => SessionNotifier());

/// المحل المحدد حالياً (أو null للتقرير الموحد).
final currentShopProvider = Provider<Shop?>((ref) {
  final id = ref.watch(sessionProvider).shopId;
  final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];
  for (final s in shops) {
    if (s.id == id) return s;
  }
  return null;
});

// ---------- المظهر ----------
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._db) : super(ThemeMode.light) {
    _load();
  }
  final AppDatabase _db;

  Future<void> _load() async {
    final v = await _db.getSetting('theme_mode');
    if (!mounted) return;
    if (v == 'dark') state = ThemeMode.dark;
    if (v == 'system') state = ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _db.setSetting('theme_mode', mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier(ref.watch(databaseProvider)));
