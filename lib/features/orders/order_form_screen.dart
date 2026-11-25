import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/image_store.dart';
import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';
import 'order_repository.dart';

class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key, this.customerId, this.orderId});
  final int? customerId;
  final int? orderId;

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _garment = TextEditingController();
  final _model = TextEditingController();
  final _fabric = TextEditingController();
  final _color = TextEditingController();
  final _details = TextEditingController();
  final _price = TextEditingController();
  final _deposit = TextEditingController();
  final _notes = TextEditingController();

  Customer? _customer;
  DateTime _orderDate = dateOnly(DateTime.now());
  DateTime? _due;
  int? _workerId;
  int? _measurementId;
  bool _measurementTouched = false;
  String? _imagePath;
  String? _sketchPath;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.orderId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_garment, _model, _fabric, _color, _details, _price, _deposit, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final customers = ref.read(customerRepositoryProvider);
    if (_isEdit) {
      final o = await ref.read(orderRepositoryProvider).getById(widget.orderId!);
      _customer = await customers.getById(o.customerId);
      _garment.text = o.garmentType ?? '';
      _model.text = o.model ?? '';
      _fabric.text = o.fabricType ?? '';
      _color.text = o.color ?? '';
      _details.text = o.details ?? '';
      _price.text = formatMoney(o.price).replaceAll(',', '');
      _notes.text = o.notes ?? '';
      _orderDate = o.orderDate;
      _due = o.dueDate;
      _workerId = o.workerId;
      _imagePath = o.imagePath;
      _sketchPath = o.sketchPath;
    } else if (widget.customerId != null) {
      _customer = await customers.getById(widget.customerId!);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _pickCustomer() async {
    final c = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerPicker(shopId: ref.read(sessionProvider).shopId),
    );
    if (c != null && mounted) {
      setState(() {
        _customer = c;
        _workerId = null;
        _measurementId = null;
        _measurementTouched = false;
      });
    }
  }

  Future<void> _pickDue() async {
    final now = dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: _isEdit ? DateTime(2020) : now,
      lastDate: DateTime(now.year + 3),
    );
    if (d != null && mounted) setState(() => _due = d);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (x == null) return;
      final rel = await ImageStore.save(x.path);
      if (mounted) setState(() => _imagePath = rel);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر اختيار الصورة')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final customer = _customer;
    if (customer == null) {
      setState(() => _error = 'اختر الزبون أولاً');
      return;
    }
    if (_due == null) {
      setState(() => _error = 'حدد موعد التسليم');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final actor = ref.read(sessionProvider).user!.id;
    final repo = ref.read(orderRepositoryProvider);
    int? measurementId = _measurementId;
    if (!_measurementTouched && !_isEdit) {
      final list = ref.read(measurementsForCustomerProvider(customer.id)).valueOrNull;
      measurementId = (list == null || list.isEmpty) ? null : list.first.id;
    }
    final input = OrderInput(
      shopId: customer.shopId,
      customerId: customer.id,
      orderDate: _orderDate,
      dueDate: _due,
      garmentType: _garment.text,
      model: _model.text,
      fabricType: _fabric.text,
      color: _color.text,
      details: _details.text,
      imagePath: _imagePath,
      sketchPath: _sketchPath,
      workerId: _workerId,
      price: parseMoney(_price.text) ?? 0,
      deposit: _isEdit ? 0 : (parseMoney(_deposit.text) ?? 0),
      notes: _notes.text,
      measurementId: _isEdit ? null : measurementId,
    );
    try {
      if (_isEdit) {
        await repo.update(actor, widget.orderId!, input);
        if (mounted) context.pop();
      } else {
        final id = await repo.create(actor, input);
        if (mounted) context.pushReplacement('/orders/$id');
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _moneyValidator(String? v, {bool required = false}) {
    if (v == null || v.trim().isEmpty) return required ? 'مطلوب' : null;
    return parseMoney(v) == null ? 'مبلغ غير صحيح' : null;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    final allowed = user != null && (user.role == Roles.admin || user.canCreateOrders);
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('طلب')),
        body: const Center(child: Text('ليست لديك صلاحية إضافة أو تعديل الطلبات')),
      );
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final customer = _customer;
    final workers = customer == null
        ? const <User>[]
        : (ref.watch(shopWorkersProvider(customer.shopId)).valueOrNull ?? const <User>[]);
    final measurements = (!_isEdit && customer != null)
        ? (ref.watch(measurementsForCustomerProvider(customer.id)).valueOrNull ??
            const <Measurement>[])
        : const <Measurement>[];
    final effectiveMeasurement = _measurementTouched
        ? _measurementId
        : (measurements.isEmpty ? null : measurements.first.id);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل الطلب' : 'طلب جديد')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(customer?.name ?? 'اختر الزبون'),
                subtitle: customer == null ? null : Text(customer.phone),
                trailing: _isEdit ? null : const Icon(Icons.chevron_left),
                onTap: _isEdit ? null : _pickCustomer,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_due == null ? 'موعد التسليم (مطلوب)' : 'موعد التسليم: ${fmtDate(_due!)}'),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDue,
            ),
            TextFormField(
              controller: _garment,
              decoration: const InputDecoration(labelText: 'نوع التفصيل (ثوب، عباية...)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'الموديل'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _fabric,
                    decoration: const InputDecoration(labelText: 'نوع القماش'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _color,
                    decoration: const InputDecoration(labelText: 'اللون'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _details,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: customer != null &&
                          ref.watch(shopTypeProvider(customer.shopId)) == ShopTypes.women
                      ? 'تابع التفصيل'
                      : 'تفاصيل الموديل'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: ValueKey('worker-${workers.length}-${customer?.id}'),
              initialValue: _workerId,
              decoration: const InputDecoration(labelText: 'العامل المسؤول'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('غير محدد')),
                for (final w in workers)
                  DropdownMenuItem<int?>(value: w.id, child: Text(w.fullName)),
              ],
              onChanged: (v) => setState(() => _workerId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'السعر'),
                    validator: (v) => _moneyValidator(v, required: true),
                  ),
                ),
                if (!_isEdit) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deposit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'العربون'),
                      validator: _moneyValidator,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (!_isEdit)
              DropdownButtonFormField<int?>(
                key: ValueKey('meas-${customer?.id}-${measurements.length}-$_measurementTouched'),
                initialValue: effectiveMeasurement,
                decoration: const InputDecoration(
                    labelText: 'المقاسات (تُحفظ كنسخة ثابتة مع الطلب)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('بدون مقاسات')),
                  for (final m in measurements)
                    DropdownMenuItem<int?>(
                        value: m.id, child: Text('${m.label} • ${fmtDate(m.createdAt)}')),
                ],
                onChanged: (v) => setState(() {
                  _measurementTouched = true;
                  _measurementId = v;
                }),
              )
            else
              const Text('المقاسات محفوظة كنسخة ثابتة مع الطلب ولا تتغير عند التعديل.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
            ),
            const SizedBox(height: 16),
            Text('صورة الموديل', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_imagePath != null) StoredImage(path: _imagePath!),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('المعرض'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('الكاميرا'),
                ),
                if (_imagePath != null)
                  TextButton(
                    onPressed: () => setState(() => _imagePath = null),
                    child: const Text('إزالة'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('الرسم', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_sketchPath != null) StoredImage(path: _sketchPath!, height: 200),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final rel = await context.push<String>('/drawing');
                    if (rel != null && mounted) setState(() => _sketchPath = rel);
                  },
                  icon: const Icon(Icons.draw_outlined),
                  label: Text(_sketchPath == null ? 'رسم الموديل' : 'رسم جديد'),
                ),
                if (_sketchPath != null)
                  TextButton(
                    onPressed: () => setState(() => _sketchPath = null),
                    child: const Text('إزالة الرسم'),
                  ),
              ],
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
              child: Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({required this.shopId});
  final int? shopId;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  late Stream<List<Customer>> _stream = _build('');

  Stream<List<Customer>> _build(String q) => ref
      .read(customerRepositoryProvider)
      .watch(shopId: widget.shopId, query: q);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'ابحث عن زبون', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _stream = _build(v)),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Customer>>(
                  stream: _stream,
                  builder: (context, snap) {
                    final list = snap.data ?? const <Customer>[];
                    if (list.isEmpty) {
                      return const Center(child: Text('لا يوجد زبائن مطابقون'));
                    }
                    return ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(list[i].name),
                        subtitle: Text(list[i].phone),
                        onTap: () => Navigator.pop(context, list[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
