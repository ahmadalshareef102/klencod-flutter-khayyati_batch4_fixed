import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../data/providers_domain.dart';

/// معاينة الفاتورة أو ورقة الطلب مع الطباعة والمشاركة.
/// الطباعة تمر عبر خدمة الطباعة في Android (USB / Wi-Fi / Bluetooth حسب الطابعة).
class InvoicePreviewScreen extends ConsumerWidget {
  const InvoicePreviewScreen({super.key, required this.orderId, required this.kind});
  final int orderId;

  /// invoice | sheet
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(invoiceServiceProvider);
    final isSheet = kind == 'sheet';
    return Scaffold(
      appBar: AppBar(title: Text(isSheet ? 'ورقة الطلب' : 'الفاتورة')),
      body: PdfPreview(
        build: (format) => isSheet ? svc.sheetPdf(orderId) : svc.invoicePdf(orderId),
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: isSheet ? 'order-sheet-$orderId.pdf' : 'invoice-$orderId.pdf',
      ),
    );
  }
}
