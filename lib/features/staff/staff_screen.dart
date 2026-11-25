import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/providers.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    final admin = ref.watch(sessionProvider).user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
            context: context, builder: (_) => const _AddWorkerDialog()),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة عامل'),
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('تعذّر تحميل العاملين')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('لا يوجد عاملون بعد'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final u = list[i];
              final shopName = shops
                  .where((s) => s.id == u.shopId)
                  .map((s) => s.name)
                  .join();
              return Card(
                child: SwitchListTile(
                  title: Text(u.fullName),
                  subtitle: Text([
                    if (u.jobTitle != null) u.jobTitle!,
                    shopName,
                    '@${u.username}',
                  ].where((e) => e.isNotEmpty).join(' • ')),
                  value: u.isActive,
                  onChanged: (v) async {
                    try {
                      await ref
                          .read(authRepositoryProvider)
                          .setActive(admin!.id, u.id, v);
                    } on AppException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddWorkerDialog extends ConsumerStatefulWidget {
  const _AddWorkerDialog();

  @override
  ConsumerState<_AddWorkerDialog> createState() => _AddWorkerDialogState();
}

class _AddWorkerDialogState extends ConsumerState<_AddWorkerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _job = TextEditingController();
  int? _shopId;
  bool _canCreate = true;
  bool _canProfits = false;
  bool _canOtherShop = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _username, _password, _phone, _job]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).createWorker(
            actorId: ref.read(sessionProvider).user!.id,
            fullName: _name.text,
            username: _username.text,
            password: _password.text,
            shopId: _shopId!,
            phone: _phone.text,
            jobTitle: _job.text,
            canCreateOrders: _canCreate,
            canViewProfits: _canProfits,
            canAccessOtherShop: _canOtherShop,
          );
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
    return AlertDialog(
      title: const Text('إضافة عامل'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                validator: (v) =>
                    (v == null || v.trim().length < 3) ? 'لا يقل عن 3 أحرف' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
                validator: (v) =>
                    (v == null || v.length < 8) ? 'لا تقل عن 8 أحرف' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _job,
                decoration: const InputDecoration(labelText: 'الوظيفة (اختياري)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _shopId,
                decoration: const InputDecoration(labelText: 'المحل'),
                items: [
                  for (final s in shops)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _shopId = v),
                validator: (v) => v == null ? 'اختر المحل' : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('يستطيع إضافة الطلبات'),
                value: _canCreate,
                onChanged: (v) => setState(() => _canCreate = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('يرى الأرباح'),
                value: _canProfits,
                onChanged: (v) => setState(() => _canProfits = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('يصل لبيانات المحل الآخر'),
                value: _canOtherShop,
                onChanged: (v) => setState(() => _canOtherShop = v ?? false),
              ),
              if (_error != null)
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          onPressed: _busy ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
