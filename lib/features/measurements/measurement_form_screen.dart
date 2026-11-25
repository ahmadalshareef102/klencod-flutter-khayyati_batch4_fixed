import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/text_utils.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'measurement_repository.dart';

class MeasurementFormScreen extends ConsumerStatefulWidget {
  const MeasurementFormScreen({super.key, required this.customerId, this.measurementId});
  final int customerId;
  final int? measurementId;

  @override
  ConsumerState<MeasurementFormScreen> createState() => _MeasurementFormScreenState();
}

class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final Map<String, TextEditingController> _controllers = {};
  int? _shopId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final customer =
        await ref.read(customerRepositoryProvider).getById(widget.customerId);
    final shop = (ref.read(shopsProvider).valueOrNull ?? const [])
        .where((s) => s.id == customer.shopId)
        .toList();
    final repo = ref.read(measurementRepositoryProvider);
    final extras = await repo.extraFields(customer.shopId);
    final defaults = MeasurementFields.defaultsFor(
        shop.isEmpty ? ShopTypes.men : shop.first.type);
    Map<String, String> existing = {};
    if (widget.measurementId != null) {
      final m = await repo.getById(widget.measurementId!);
      _label.text = m.label;
      existing = MeasurementFields.decode(m.valuesJson);
    }
    final names = <String>[
      ...defaults,
      ...extras,
      ...existing.keys.where((k) => !defaults.contains(k) && !extras.contains(k)),
    ];
    for (final n in names) {
      _controllers[n] = TextEditingController(text: existing[n] ?? '');
    }
    if (!mounted) return;
    setState(() {
      _shopId = customer.shopId;
      _loading = false;
    });
  }

  Future<void> _addField() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة حقل مقاس'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم الحقل'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('إضافة')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null) return;
    try {
      await ref.read(measurementRepositoryProvider).addExtraField(_shopId!, name);
      if (!mounted) return;
      setState(() => _controllers[name.trim()] = TextEditingController());
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(measurementRepositoryProvider);
    final actor = ref.read(sessionProvider).user!.id;
    final values = {for (final e in _controllers.entries) e.key: e.value.text};
    try {
      if (widget.measurementId == null) {
        await repo.create(
            actorId: actor,
            customerId: widget.customerId,
            label: _label.text,
            values: values);
      } else {
        await repo.update(
            actorId: actor,
            id: widget.measurementId!,
            label: _label.text,
            values: values);
      }
      if (mounted) context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.measurementId == null ? 'سجل مقاسات جديد' : 'تعديل المقاسات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _label,
                    decoration: const InputDecoration(
                        labelText: 'اسم السجل (مثال: ثوب العيد)'),
                  ),
                  const SizedBox(height: 16),
                  const Text('كل المقاسات اختيارية — املأ ما تحتاجه فقط'),
                  const SizedBox(height: 8),
                  for (final e in _controllers.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: e.value,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: e.key),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final d = parseDecimal(v);
                          return (d == null || d < 0) ? 'رقم غير صحيح' : null;
                        },
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addField,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة حقل جديد'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ),
    );
  }
}
