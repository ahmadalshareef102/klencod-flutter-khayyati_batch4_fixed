import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/db/app_database.dart';

class OrderStatus {
  static const newOrder = 'new';
  static const measured = 'measured';
  static const cutting = 'cutting';
  static const sewing = 'sewing';
  static const fitting = 'fitting';
  static const ready = 'ready';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';

  /// ترتيب المراحل. (قابلة للتخصيص لاحقاً من الإعدادات)
  static const all = [
    newOrder,
    measured,
    cutting,
    sewing,
    fitting,
    ready,
    delivered,
    cancelled,
  ];

  static const _labels = {
    newOrder: 'طلب جديد',
    measured: 'تم أخذ المقاسات',
    cutting: 'قيد القص',
    sewing: 'قيد الخياطة',
    fitting: 'قيد التجربة والتعديل',
    ready: 'جاهز للتسليم',
    delivered: 'تم التسليم',
    cancelled: 'ملغي',
  };

  static String label(String key) => _labels[key] ?? key;

  static bool isTerminal(String s) => s == delivered || s == cancelled;

  /// الطلب متأخر إن تجاوز موعد التسليم (قبل اليوم) ولم يُسلَّم أو يُلغَ.
  static bool isLate(Order o, [DateTime? now]) {
    final due = o.dueDate;
    if (due == null || isTerminal(o.status)) return false;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return DateTime(due.year, due.month, due.day).isBefore(today);
  }

  static Color color(String s) {
    switch (s) {
      case newOrder:
        return Colors.blueGrey;
      case measured:
        return Colors.indigo;
      case cutting:
        return Colors.deepPurple;
      case sewing:
        return Colors.teal;
      case fitting:
        return AppColors.warning;
      case ready:
        return AppColors.success;
      case delivered:
        return const Color(0xFF1B5E20);
      case cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = OrderStatus.color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c),
      ),
      child: Text(OrderStatus.label(status),
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
