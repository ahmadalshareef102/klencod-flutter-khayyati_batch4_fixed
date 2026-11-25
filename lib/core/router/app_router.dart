import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/setup_screen.dart';
import '../../features/accounts/accounts_screen.dart';
import '../../features/customers/customer_detail_screen.dart';
import '../../features/customers/statement_screen.dart';
import '../../features/debts/debts_screen.dart';
import '../../features/drawing/drawing_pad_screen.dart';
import '../../features/expenses/expenses_screen.dart';
import '../../features/inventory/fabric_detail_screen.dart';
import '../../features/invoices/invoice_preview_screen.dart';
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/staff/staff_screen.dart';
import '../../features/suppliers/supplier_detail_screen.dart';
import '../../features/suppliers/suppliers_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/measurements/measurement_form_screen.dart';
import '../../features/orders/order_detail_screen.dart';
import '../../features/orders/order_form_screen.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(sessionProvider, (_, __) => notifyListeners());
    _ref.listen(adminExistsProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    final admin = _ref.read(adminExistsProvider);
    if (admin.isLoading) return loc == '/splash' ? null : '/splash';
    final hasAdmin = admin.valueOrNull ?? false;
    final loggedIn = _ref.read(sessionProvider).isLoggedIn;
    if (!hasAdmin) return loc == '/setup' ? null : '/setup';
    if (!loggedIn) return loc == '/login' ? null : '/login';
    if (loc == '/login' || loc == '/setup' || loc == '/splash') return '/home';
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/customers/:id/statement',
        builder: (_, s) =>
            StatementScreen(customerId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: '/drawing', builder: (_, __) => const DrawingPadScreen()),
      GoRoute(
        path: '/invoice/:id',
        builder: (_, s) => InvoicePreviewScreen(
          orderId: int.parse(s.pathParameters['id']!),
          kind: s.uri.queryParameters['kind'] ?? 'invoice',
        ),
      ),
      GoRoute(
        path: '/settings/notifications',
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(path: '/debts', builder: (_, __) => const DebtsScreen()),
      GoRoute(path: '/accounts', builder: (_, __) => const AccountsScreen()),
      GoRoute(path: '/expenses', builder: (_, __) => const ExpensesScreen()),
      GoRoute(path: '/inventory', builder: (_, __) => const InventoryScreen()),
      GoRoute(
        path: '/inventory/:id',
        builder: (_, s) =>
            FabricDetailScreen(fabricId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: '/suppliers', builder: (_, __) => const SuppliersScreen()),
      GoRoute(
        path: '/suppliers/:id',
        builder: (_, s) =>
            SupplierDetailScreen(supplierId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/staff',
        builder: (_, __) => Scaffold(
          appBar: AppBar(title: const Text('العاملون')),
          body: const StaffScreen(),
        ),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (_, s) =>
            CustomerDetailScreen(customerId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/measurements/edit',
        builder: (_, s) => MeasurementFormScreen(
          customerId: int.parse(s.uri.queryParameters['customerId']!),
          measurementId: int.tryParse(s.uri.queryParameters['measurementId'] ?? ''),
        ),
      ),
      // ملاحظة: /orders/new يجب أن يسبق /orders/:id
      GoRoute(
        path: '/orders/new',
        builder: (_, s) => OrderFormScreen(
            customerId: int.tryParse(s.uri.queryParameters['customerId'] ?? '')),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, s) =>
            OrderDetailScreen(orderId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/orders/:id/edit',
        builder: (_, s) =>
            OrderFormScreen(orderId: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
});
