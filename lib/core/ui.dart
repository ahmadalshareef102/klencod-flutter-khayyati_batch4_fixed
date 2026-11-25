import 'package:flutter/material.dart';

import 'constants.dart';
import 'money.dart';
import 'dates.dart';

void showMsg(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmDialog(BuildContext context, String title, String content,
    {String ok = 'تأكيد'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// ينفّذ عملية ويعرض رسالة الخطأ العربية إن فشلت.
Future<bool> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on AppException catch (e) {
    if (context.mounted) showMsg(context, e.message);
  } catch (_) {
    if (context.mounted) showMsg(context, 'حدث خطأ غير متوقع');
  }
  return false;
}

// ---------- حوار نماذج عام ----------
sealed class FormItem {
  const FormItem(this.label);
  final String label;
}

class TextItem extends FormItem {
  const TextItem(super.label,
      {this.initial = '', this.required = false, this.maxLines = 1, this.number = false});
  final String initial;
  final bool required;
  final int maxLines;
  final bool number;
}

class MoneyItem extends FormItem {
  const MoneyItem(super.label, {this.initial = '', this.required = true});
  final String initial;
  final bool required;
}

class DropItem extends FormItem {
  const DropItem(super.label, this.options, {this.initial, this.required = false});
  final Map<String, String> options;
  final String? initial;
  final bool required;
}

class DateItem extends FormItem {
  const DateItem(super.label, {this.initial});
  final DateTime? initial;
}

/// قيم النتيجة: TextItem → String، MoneyItem → int (أصغر وحدة)، DropItem → String?، DateItem → DateTime.
Future<void> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FormItem> items,
  required Future<void> Function(List<Object?> values) onSubmit,
  String okLabel = 'حفظ',
  String? note,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FormDialog(
        title: title, items: items, onSubmit: onSubmit, okLabel: okLabel, note: note),
  );
}

class _FormDialog extends StatefulWidget {
  const _FormDialog(
      {required this.title,
      required this.items,
      required this.onSubmit,
      required this.okLabel,
      this.note});
  final String title;
  final List<FormItem> items;
  final Future<void> Function(List<Object?>) onSubmit;
  final String okLabel;
  final String? note;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController?> _ctrls = [
    for (final i in widget.items)
      switch (i) {
        TextItem t => TextEditingController(text: t.initial),
        MoneyItem m => TextEditingController(text: m.initial),
        _ => null,
      }
  ];
  late final List<Object?> _vals = [
    for (final i in widget.items)
      switch (i) {
        DropItem d => d.initial,
        DateItem d => d.initial ?? dateOnly(DateTime.now()),
        _ => null,
      }
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrls) {
      c?.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final out = <Object?>[];
    for (var k = 0; k < widget.items.length; k++) {
      final it = widget.items[k];
      switch (it) {
        case TextItem():
          out.add(_ctrls[k]!.text.trim());
        case MoneyItem():
          out.add(parseMoney(_ctrls[k]!.text) ?? 0);
        case DropItem():
          out.add(_vals[k]);
        case DateItem():
          out.add(_vals[k]);
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(out);
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(int k) {
    final item = widget.items[k];
    switch (item) {
      case TextItem t:
        return TextFormField(
          controller: _ctrls[k],
          maxLines: t.maxLines,
          keyboardType:
              t.number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: t.label),
          validator: (v) =>
              t.required && (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
        );
      case MoneyItem m:
        return TextFormField(
          controller: _ctrls[k],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: m.label),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return m.required ? 'مطلوب' : null;
            return parseMoney(v) == null ? 'مبلغ غير صحيح' : null;
          },
        );
      case DropItem d:
        return DropdownButtonFormField<String>(
          initialValue: _vals[k] as String?,
          decoration: InputDecoration(labelText: d.label),
          items: [
            for (final e in d.options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => _vals[k] = v,
          validator: (v) => d.required && v == null ? 'مطلوب' : null,
        );
      case DateItem di:
        final cur = _vals[k] as DateTime;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${di.label}: ${fmtDate(cur)}'),
          trailing: const Icon(Icons.calendar_month_outlined),
          onTap: () async {
            final now = DateTime.now();
            final p = await showDatePicker(
              context: context,
              initialDate: cur,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 3),
            );
            if (p != null && mounted) setState(() => _vals[k] = p);
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(widget.note!, style: Theme.of(context).textTheme.bodySmall),
                ),
              for (var k = 0; k < widget.items.length; k++)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _field(k)),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
          onPressed: _busy ? null : _submit,
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}
