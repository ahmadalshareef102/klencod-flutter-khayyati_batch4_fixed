import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/period_bar.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!canManageFinance(session.user)) {
      return Scaffold(
          appBar: AppBar(title: const Text('الحسابات')),
          body: const Center(child: Text('ليست لديك صلاحية عرض الحسابات')));
    }
    final shop = ref.watch(currentShopProvider);
    final s = ref.watch(accountsSummaryProvider).valueOrNull;

    Widget line(String label, int value, {String? hint, bool bold = false, Color? color, String sign = ''}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null)),
                Text('$sign${formatMoney(value)}',
                    style: TextStyle(
                        fontWeight: bold ? FontWeight.bold : null, color: color)),
              ],
            ),
            if (hint != null)
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    Widget section(String title, List<Widget> children) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Divider(),
                ...children,
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text('الحسابات • ${shop?.name ?? 'الإجمالي'}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const PeriodBar(),
          if (s == null)
            const Padding(
                padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            section('الطلبات والتحصيل', [
              line('قيمة الطلبات الجديدة (${s.newOrdersCount})', s.newOrdersValue,
                  hint: 'طلبات أُنشئت في الفترة وغير ملغاة'),
              line('المحصَّل (الدفعات)', s.collected,
                  color: AppColors.success,
                  hint: 'كل الدفعات المستلمة في الفترة بما فيها العربون'),
              line('الديون المتبقية على الزبائن', s.outstandingDebts,
                  color: AppColors.warning, hint: 'حتى اليوم وليست مرتبطة بالفترة'),
              line('عربونات طلبات لم تُسلَّم بعد', s.advancesOnOpenOrders,
                  hint: 'مبالغ مقبوضة مقدماً؛ ليست ربحاً حتى التسليم'),
            ]),
            section('الأرباح', [
              line('الإيراد (طلبات مُسلَّمة: ${s.deliveredCount})', s.revenue,
                  hint: 'يُعترف بالإيراد عند التسليم وليس عند أخذ العربون'),
              line('تكلفة الأقمشة', s.fabricCost, sign: '−',
                  hint: 'الأقمشة المخصومة على الطلبات المسلَّمة'),
              line('تكاليف مباشرة (أجور وغيرها)', s.directCosts, sign: '−'),
              const Divider(),
              line('إجمالي الربح', s.grossProfit, bold: true),
              line('المصروفات التشغيلية', s.operatingExpenses, sign: '−',
                  hint: 'إيجار وكهرباء وأجور ... خلال الفترة'),
              line('هالك الأقمشة', s.wasteCost, sign: '−'),
              const Divider(),
              line('صافي الربح التقديري', s.netProfit,
                  bold: true,
                  color: s.netProfit >= 0 ? AppColors.success : Theme.of(context).colorScheme.error),
            ]),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'ملاحظة: شراء الأقمشة لا يُعدّ مصروفاً مباشرة، بل يدخل المخزون ثم يُحتسب '
                  'عند استخدامه في طلب (لتفادي احتسابه مرتين). صافي الربح تقديري لأن مصروفات '
                  'الفترة تُخصم كاملة من إيراد الطلبات المُسلَّمة فيها.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ],
      ),
    );
  }
}
