import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers_domain.dart';
import 'period.dart';

/// شريط اختيار الفترة (اليوم / الأسبوع / الشهر / مخصصة).
class PeriodBar extends ConsumerWidget {
  const PeriodBar({super.key});

  static const _labels = {
    PeriodKind.today: 'اليوم',
    PeriodKind.week: 'الأسبوع',
    PeriodKind.month: 'الشهر',
    PeriodKind.custom: 'فترة مخصصة',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(periodProvider);
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in _labels.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: p.kind == e.key,
                    onSelected: (_) async {
                      if (e.key != PeriodKind.custom) {
                        ref.read(periodProvider.notifier).state = Period.of(e.key);
                        return;
                      }
                      final now = DateTime.now();
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (r != null) {
                        ref.read(periodProvider.notifier).state = Period.of(
                            PeriodKind.custom,
                            customFrom: r.start,
                            customTo: r.end);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        Text(p.label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
