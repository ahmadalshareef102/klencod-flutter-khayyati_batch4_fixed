import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'customer_form_dialog.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final customers = ref.watch(customersProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final shopId = session.shopId;
          if (shopId == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('اختر محلاً من الصفحة الرئيسية أولاً')));
            return;
          }
          showDialog<bool>(
              context: context,
              builder: (_) => CustomerFormDialog(shopId: shopId));
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('زبون جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو رقم الهاتف',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => ref.read(customerSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: customers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Center(child: Text('تعذّر تحميل الزبائن')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('لا يوجد زبائن'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final shopName = session.shopId == null
                        ? shops.where((s) => s.id == c.shopId).map((s) => s.name).join()
                        : '';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                            child: Text(c.name.isEmpty ? '?' : c.name.substring(0, 1))),
                        title: Text(c.name),
                        subtitle: Text(
                            [c.phone, if (shopName.isNotEmpty) shopName].join(' • ')),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => context.push('/customers/${c.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
