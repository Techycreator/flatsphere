import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _months = ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'];
const _income = [312000.0, 298000.0, 305000.0, 341000.0, 318000.0, 226000.0];
const _expense = [241000.0, 262000.0, 228000.0, 309000.0, 254000.0, 149000.0];

class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, _) =>
                        Text('${(v / 100000).toStringAsFixed(1)}L', style: const TextStyle(fontSize: 11)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_months[v.toInt()], style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < _months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: _income[i],
                        color: scheme.primary,
                        width: 12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: _expense[i],
                        color: const Color(0xFFF59E0B),
                        width: 12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(scheme.primary, 'Income'),
            const SizedBox(width: 16),
            _legend(const Color(0xFFF59E0B), 'Expenditure'),
          ],
        ),
      ],
    );
  }
}

const expenseBreakup = <(String, double, Color)>[
  ('Staff salaries', 98000, Color(0xFF0F766E)),
  ('Common electricity', 18640, Color(0xFF2563EB)),
  ('Security agency', 62000, Color(0xFF7C3AED)),
  ('Lift & DG AMC', 24500, Color(0xFFEA580C)),
  ('STP & motors', 17300, Color(0xFFDB2777)),
  ('Water bill', 9870, Color(0xFF0891B2)),
  ('Cleaning & others', 23690, Color(0xFF64748B)),
];

class ExpensePie extends StatelessWidget {
  const ExpensePie({super.key});

  @override
  Widget build(BuildContext context) {
    final total = expenseBreakup.fold<double>(0, (s, e) => s + e.$2);
    return LayoutBuilder(
      builder: (context, c) {
        final pie = SizedBox(
          height: 180,
          width: 180,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 46,
              sectionsSpace: 2,
              sections: [
                for (final e in expenseBreakup)
                  PieChartSectionData(value: e.$2, color: e.$3, radius: 36, showTitle: false),
              ],
            ),
          ),
        );
        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in expenseBreakup)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dot(e.$3),
                    const SizedBox(width: 6),
                    Text(
                      '${e.$1}  ${inr.format(e.$2)}  (${(e.$2 / total * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text('Total ${inr.format(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        );
        return c.maxWidth < 480
            ? Column(children: [pie, const SizedBox(height: 12), legend])
            : Row(
                children: [
                  pie,
                  const SizedBox(width: 24),
                  Expanded(child: legend),
                ],
              );
      },
    );
  }
}

Widget _dot(Color c) => Container(
  width: 10,
  height: 10,
  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
);

Widget _legend(Color c, String t) => Row(
  children: [
    _dot(c),
    const SizedBox(width: 6),
    Text(t, style: const TextStyle(fontSize: 12)),
  ],
);
