import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';

class CustomerFormDialog extends ConsumerStatefulWidget {
  const CustomerFormDialog({super.key, required this.shopId, this.customer});
  final int shopId;
  final Customer? customer;

  @override
  ConsumerState<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _address = TextEditingController(text: widget.customer?.address ?? '');
  late final _notes = TextEditingController(text: widget.customer?.notes ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(customerRepositoryProvider);
    final actor = ref.read(sessionProvider).user!.id;
    try {
      final dup = await repo.findByPhone(widget.shopId, _phone.text,
          excludeId: widget.customer?.id);
      if (dup != null) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('رقم هاتف مكرر'),
            content: Text(
                'هذا الرقم مسجل للزبون «${dup.name}». هل تريد المتابعة والحفظ رغم ذلك؟'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('متابعة')),
            ],
          ),
        );
        if (go != true) return;
      }
      if (widget.customer == null) {
        await repo.create(
            actorId: actor,
            shopId: widget.shopId,
            name: _name.text,
            phone: _phone.text,
            address: _address.text,
            notes: _notes.text);
      } else {
        await repo.update(
            actorId: actor,
            id: widget.customer!.id,
            name: _name.text,
            phone: _phone.text,
            address: _address.text,
            notes: _notes.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'إضافة زبون' : 'تعديل الزبون'),
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
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'العنوان (اختياري)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
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
