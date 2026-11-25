import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'features/notifications/notification_providers.dart';

class KhayyatiApp extends ConsumerWidget {
  const KhayyatiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final seed = ref.watch(accentSeedProvider);
    ref.watch(notificationSyncProvider);
    return MaterialApp.router(
      title: 'خياطتي',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: ref.watch(themeModeProvider),
      theme: AppTheme.light(seed),
      darkTheme: AppTheme.dark(seed),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
