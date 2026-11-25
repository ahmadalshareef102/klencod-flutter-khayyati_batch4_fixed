import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates.dart';
import '../../core/money.dart';
import '../payments/payment_repository.dart';
import 'invoice_models.dart';

/// خطوط PDF (يجب أن تدعم العربية). تأتي من assets/fonts/pdf.
class PdfFonts {
  const PdfFonts(this.regular, this.bold);
  final ByteData regular;
  final ByteData bold;
}

const _navy = PdfColor.fromInt(0xFF1A2B4C);
const _blue = PdfColor.fromInt(0xFF2F6DB5);
const _light = PdfColor.fromInt(0xFFDCEBFA);
const _grey = PdfColor.fromInt(0xFF666666);
const _rtl = pw.TextDirection.rtl;

pw.Widget _t(
  String s, {
  double size = 10,
  bool bold = false,
  PdfColor? color,
  pw.TextAlign align = pw.TextAlign.right,
}) {
  return pw.Text(
    s,
    textDirection: _rtl,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    ),
  );
}

String _money(int v, String currency) =>
    currency.isEmpty ? formatMoney(v) : '${formatMoney(v)} $currency';

pw.Widget _kv(String label, String value, {double size = 10}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _t('$label:', size: size, bold: true),
        pw.SizedBox(width: 4),
        pw.Expanded(child: _t(value, size: size)),
      ],
    ),
  );
}

pw.Document _document(PdfFonts fonts) {
  return pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(fonts.regular),
      bold: pw.Font.ttf(fonts.bold),
    ),
  );
}

PdfPageFormat _a4Format() => PdfPageFormat.a4;

PdfPageFormat _formatFor(InvoiceSettings s) {
  if (s.format == InvoiceFormat.thermal) {
    return PdfPageFormat(s.thermalMm * PdfPageFormat.mm, double.infinity,
        marginAll: 3 * PdfPageFormat.mm);
  }
  return _a4Format();
}

// ======================= الفاتورة =======================

Future<Uint8List> buildInvoicePdf(InvoiceModel m, PdfFonts fonts) async {
  final doc = _document(fonts);
  final thermal = m.settings.format == InvoiceFormat.thermal;
  final format = _formatFor(m.settings);
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: thermal ? const pw.EdgeInsets.all(8) : const pw.EdgeInsets.all(28),
        textDirection: _rtl,
      ),
      build: (ctx) => pw.Directionality(
        textDirection: _rtl,
        child: thermal ? _thermalInvoice(m) : _a4Invoice(m),
      ),
    ),
  );
  return doc.save();
}

pw.Widget _box(String title, List<pw.Widget> children) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _navy, width: 0.8),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: _navy,
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: _t(title, size: 11, bold: true, color: PdfColors.white),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _a4Invoice(InvoiceModel m) {
  final cur = m.settings.currency;
  final logo = m.logo == null ? null : pw.MemoryImage(m.logo!);
  final detailRows = <MapEntry<String, String?>>[
    MapEntry('نوع التفصيل', m.garmentType),
    MapEntry('الموديل', m.model),
    MapEntry('نوع القماش', m.fabricType),
    MapEntry('اللون', m.color),
    MapEntry(m.isWomen ? 'تابع التفصيل' : 'تفاصيل الموديل', m.details),
  ].where((e) => e.value != null && e.value!.isNotEmpty).toList();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: _navy,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null)
              pw.Container(
                width: 56,
                height: 56,
                margin: const pw.EdgeInsets.only(left: 12),
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _t(m.shopName, size: 20, bold: true, color: PdfColors.white),
                  if (m.shopPhone != null && m.shopPhone!.isNotEmpty)
                    _t('هاتف: ${m.shopPhone}', color: PdfColors.white),
                  if (m.shopAddress != null && m.shopAddress!.isNotEmpty)
                    _t(m.shopAddress!, color: PdfColors.white),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _t('فاتورة', size: 20, bold: true, color: PdfColors.white),
                _t(m.invoiceNo, color: PdfColors.white),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _box('بيانات الزبون', [
              _kv('الاسم', m.customerName),
              _kv('الهاتف', m.customerPhone),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _box('بيانات الطلب', [
              _kv('رقم الطلب', m.orderNo),
              _kv('تاريخ الطلب', fmtDate(m.orderDate)),
              _kv('موعد التسليم', m.dueDate == null ? '-' : fmtDate(m.dueDate!)),
            ]),
          ),
        ],
      ),
      pw.SizedBox(height: 12),
      if (detailRows.isNotEmpty)
        _box('تفاصيل الطلب', [for (final e in detailRows) _kv(e.key, e.value!)]),
      pw.SizedBox(height: 12),
      _box('الحساب', [
        _kv('السعر', _money(m.price, cur), size: 11),
        _kv(m.isWomen ? 'الواصل' : 'المدفوع', _money(m.paid, cur), size: 11),
        pw.Divider(color: _navy, thickness: 0.6),
        pw.Row(
          children: [
            _t('المتبقي:', size: 13, bold: true, color: _navy),
            pw.SizedBox(width: 6),
            _t(_money(m.remaining, cur), size: 13, bold: true, color: _navy),
          ],
        ),
      ]),
      if (m.payments.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _box('الدفعات', [
          for (final p in m.payments)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.Expanded(child: _t(fmtDate(p.date))),
                  pw.Expanded(child: _t(PaymentRepository.methodLabel(p.method))),
                  pw.Expanded(child: _t(_money(p.amount, cur), bold: true)),
                ],
              ),
            ),
        ]),
      ],
      if (m.settings.notes != null) ...[
        pw.SizedBox(height: 12),
        _t(m.settings.notes!, size: 9, color: _grey),
      ],
      pw.Spacer(),
      pw.Divider(color: _light, thickness: 1),
      pw.Center(
        child: _t(m.settings.thanks,
            size: 14, bold: true, color: _blue, align: pw.TextAlign.center),
      ),
    ],
  );
}

pw.Widget _thermalInvoice(InvoiceModel m) {
  final cur = m.settings.currency;
  final logo = m.logo == null ? null : pw.MemoryImage(m.logo!);
  pw.Widget line(String a, String b, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          children: [
            pw.Expanded(child: _t(a, size: 9, bold: bold)),
            _t(b, size: 9, bold: bold),
          ],
        ),
      );
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (logo != null)
        pw.Center(
          child: pw.SizedBox(width: 40, height: 40, child: pw.Image(logo, fit: pw.BoxFit.contain)),
        ),
      _t(m.shopName, size: 13, bold: true, align: pw.TextAlign.center),
      if (m.shopPhone != null && m.shopPhone!.isNotEmpty)
        _t(m.shopPhone!, size: 9, align: pw.TextAlign.center),
      if (m.shopAddress != null && m.shopAddress!.isNotEmpty)
        _t(m.shopAddress!, size: 8, align: pw.TextAlign.center),
      pw.Divider(thickness: 0.6),
      _t('فاتورة ${m.invoiceNo}', size: 10, bold: true, align: pw.TextAlign.center),
      line('التاريخ', fmtDate(m.orderDate)),
      line('الزبون', m.customerName),
      line('الهاتف', m.customerPhone),
      line('رقم الطلب', m.orderNo),
      if (m.dueDate != null) line('التسليم', fmtDate(m.dueDate!)),
      pw.Divider(thickness: 0.6),
      if (m.garmentType != null && m.garmentType!.isNotEmpty) line('التفصيل', m.garmentType!),
      if (m.model != null && m.model!.isNotEmpty) line('الموديل', m.model!),
      if (m.fabricType != null && m.fabricType!.isNotEmpty) line('القماش', m.fabricType!),
      if (m.color != null && m.color!.isNotEmpty) line('اللون', m.color!),
      pw.Divider(thickness: 0.6),
      line('السعر', _money(m.price, cur)),
      line(m.isWomen ? 'الواصل' : 'المدفوع', _money(m.paid, cur)),
      line('المتبقي', _money(m.remaining, cur), bold: true),
      pw.Divider(thickness: 0.6),
      _t(m.settings.thanks, size: 10, bold: true, align: pw.TextAlign.center),
      if (m.settings.notes != null)
        _t(m.settings.notes!, size: 7, align: pw.TextAlign.center),
    ],
  );
}

// ======================= ورقة الطلب (نموذج المحل) =======================

Future<Uint8List> buildSheetPdf(List<SheetModel> sheets, PdfFonts fonts) async {
  final doc = _document(fonts);
  final pageFormat = _a4Format();
  for (var i = 0; i < sheets.length; i += 4) {
    final chunk = sheets.sublist(i, i + 4 > sheets.length ? sheets.length : i + 4);
    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          textDirection: _rtl,
        ),
        build: (ctx) => pw.Directionality(
          textDirection: _rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _sheetHeader(chunk.first),
              pw.SizedBox(height: 3 * PdfPageFormat.mm),
              for (final s in chunk) ...[
                _sheetBlock(s),
                pw.SizedBox(height: 3 * PdfPageFormat.mm),
              ],
            ],
          ),
        ),
      ),
    );
  }
  return doc.save();
}

pw.Widget _sheetHeader(SheetModel s) {
  final logo = s.logo == null ? null : pw.MemoryImage(s.logo!);
  return pw.Container(
    height: 14 * PdfPageFormat.mm,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12),
    decoration: pw.BoxDecoration(
      color: _navy,
      borderRadius: pw.BorderRadius.circular(18),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        if (logo != null)
          pw.Container(
            width: 30,
            height: 30,
            margin: const pw.EdgeInsets.only(left: 8),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        _t(s.shopName, size: 17, bold: true, color: PdfColors.white, align: pw.TextAlign.center),
      ],
    ),
  );
}

pw.Widget _bar(String title) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 6),
    decoration: pw.BoxDecoration(
      color: _navy,
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: _t(title, size: 9, bold: true, color: PdfColors.white),
  );
}

pw.Widget _line(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 0.4)),
    ),
    child: pw.Row(
      children: [
        _t('$label:', size: 8, bold: true),
        pw.SizedBox(width: 3),
        pw.Expanded(child: _t(value, size: 8)),
      ],
    ),
  );
}

String _clip(String? s, int max) {
  if (s == null) return '';
  return s.length <= max ? s : '${s.substring(0, max)}…';
}

pw.Widget _sheetBlock(SheetModel s) {
  final sketch = s.sketch == null ? null : pw.MemoryImage(s.sketch!);
  final cur = s.settings.currency;
  final fields = s.measureFields.take(12).toList();

  return pw.Container(
    height: 60 * PdfPageFormat.mm,
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _navy, width: 1.2),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          children: [
            for (var i = 0; i < fields.length; i++)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 1.5),
                  child: pw.Column(
                    children: [
                      _t('${i + 1}. ${fields[i].key}',
                          size: 6.5, bold: true, color: _navy, align: pw.TextAlign.center),
                      pw.Container(
                        height: 13,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          color: _light,
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(color: _blue, width: 0.5),
                        ),
                        child: _t(fields[i].value, size: 9, align: pw.TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // بيانات العميل (يمين)
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _bar('بيانات العميل'),
                    pw.SizedBox(height: 2),
                    _line('الاسم', _clip(s.customerName, 28)),
                    _line('رقم الهاتف', s.customerPhone),
                    _line('الطلب', _clip('${s.orderTitle ?? ''} ${s.orderNo}', 30)),
                    _line('السعر', _money(s.price, cur)),
                    _line('الواصل', _money(s.paid, cur)),
                    _line('الباقي', _money(s.remaining, cur)),
                    pw.Spacer(),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(3),
                      color: _light,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _t('تاريخ التفصيل: ${fmtDate(s.orderDate)}', size: 8, bold: true),
                          _t('تاريخ الاستلام: ${s.dueDate == null ? '     /     /' : fmtDate(s.dueDate!)}',
                              size: 8, bold: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 4),
              // القماش وتابع التفصيل (وسط)
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _bar('نوع القماش'),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      height: 30,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _blue, width: 0.6),
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: _t(_clip(s.fabric, 60), size: 8),
                    ),
                    pw.SizedBox(height: 3),
                    _bar('تابع التفصيل'),
                    pw.SizedBox(height: 2),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _blue, width: 0.6),
                          borderRadius: pw.BorderRadius.circular(5),
                        ),
                        child: _t(_clip(s.details, 140), size: 8),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 4),
              // الرسم (يسار)
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _bar('الرسم'),
                    pw.SizedBox(height: 2),
                    pw.Expanded(
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _navy, width: 0.8),
                          borderRadius: pw.BorderRadius.circular(5),
                        ),
                        child: sketch == null
                            ? pw.SizedBox()
                            : pw.Padding(
                                padding: const pw.EdgeInsets.all(2),
                                child: pw.Image(sketch, fit: pw.BoxFit.contain),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
