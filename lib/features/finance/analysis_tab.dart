import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' hide Text, TextField, DropdownButtonFormField;
import '../../widgets/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'analysis_data.dart';

enum _Mode { yoy, mom }

class AnalysisTab extends ConsumerStatefulWidget {
  const AnalysisTab({super.key});

  @override
  ConsumerState<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends ConsumerState<AnalysisTab> {
  _Mode _mode = _Mode.yoy;
  String _category = 'expense:all';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final l = AppLocalizations.of(context);
    final expenses = ref.watch(expensesProvider).where((e) => e.status == ExpenseStatus.approved).toList();
    final income = ref.watch(incomeProvider).entries;
    final dues = ref.watch(duesProvider);
    final budgets = ref.watch(annualBudgetsProvider);
    final today = DateUtils.dateOnly(DateTime.now());
    final setting = session.user.association?.settings['fiscal_year_start_month'];
    final fiscalMonth = setting is num ? setting.toInt().clamp(1, 12).toInt() : 4;
    final fiscalYear = today.month >= fiscalMonth ? today.year : today.year - 1;
    final currentStart = DateTime(fiscalYear, fiscalMonth, 1);
    final previousStart = DateTime(fiscalYear - 1, fiscalMonth, 1);
    final closedMonths = ((today.year - fiscalYear) * 12 + today.month - fiscalMonth + 1).clamp(1, 12).toInt();
    final currentFyName = 'FY $fiscalYear-${(fiscalYear + 1).toString().substring(2)}';
    final previousFyName = 'FY ${fiscalYear - 1}-${fiscalYear.toString().substring(2)}';
    final expenseCategories = expenses.map((e) => e.category).toSet().toList()..sort();
    final incomeCategories = income.map((e) => e.categoryName).toSet().toList()..sort();
    final dueCategories = dues.payments.map((p) => p.head ?? 'Advance').toSet().toList()..sort();
    final categories = <(String, String)>[
      ('expense:all', 'All expenses'),
      for (final name in expenseCategories) ('expense:$name', 'Expense · $name'),
      ('income:all', 'All income'),
      for (final name in incomeCategories) ('income:$name', 'Income · $name'),
      for (final name in dueCategories) ('dues:$name', 'Dues · $name'),
    ];
    if (!categories.any((item) => item.$1 == _category)) _category = categories.first.$1;
    final series = _liveSeries(_category, expenses, income, dues.payments, currentStart, previousStart, fiscalMonth);
    final currentTotal = series.current.take(closedMonths).fold(0.0, (sum, value) => sum + value);
    final previousTotal = series.previous.take(closedMonths).fold(0.0, (sum, value) => sum + value);
    final theme = Theme.of(context);
    final hasData = currentTotal != 0 || previousTotal != 0;
    return PageBody(
      children: [
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: const ListTile(
            leading: Icon(Icons.visibility_outlined),
            title: Text('Visible to all EC members (interim access)'),
            subtitle: Text(
              'Any change to who can see this goes through W2: Secretary review → EC vote → President approval.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_Mode>(
              segments: [
                ButtonSegment(value: _Mode.yoy, label: Text(l.analysisYearOnYear), icon: Icon(Icons.compare_arrows)),
                ButtonSegment(value: _Mode.mom, label: Text(l.analysisMonthOnMonth), icon: Icon(Icons.calendar_month)),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            SizedBox(
              width: 340,
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                isDense: true,
                decoration: InputDecoration(labelText: l.analysisCategory, isDense: true),
                items: [for (final item in categories) DropdownMenuItem(value: item.$1, child: Text(item.$2))],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
            ),
            TextButton.icon(
              onPressed: () => toast(context, l.analysisExportHint),
              icon: const Icon(Icons.download),
              label: const Text('Export'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (hasData)
          StatGrid(
            children: [
              StatCard(label: '$currentFyName · to date', value: inr.format(currentTotal), icon: Icons.today),
              StatCard(label: '$previousFyName · same period', value: inr.format(previousTotal), icon: Icons.history),
              StatCard(
                label: 'Change',
                value:
                    '${_pct(currentTotal, previousTotal) >= 0 ? '+' : ''}${_pct(currentTotal, previousTotal).toStringAsFixed(1)}%',
                icon: Icons.trending_up,
              ),
            ],
          )
        else
          EmptyState(l.noAnalysisData, icon: Icons.bar_chart_outlined),
        const SizedBox(height: 16),
        SectionCard(
          title: '${series.name} · $currentFyName vs $previousFyName',
          child: !hasData
              ? const Text('Figures appear here as transactions are recorded.')
              : SizedBox(
                  height: 280,
                  child: _mode == _Mode.yoy
                      ? LineChart(
                          LineChartData(
                            gridData: const FlGridData(drawVerticalLine: false),
                            borderData: FlBorderData(show: false),
                            titlesData: _titles((index) => _monthLabel(fiscalMonth, index.toInt())),
                            lineBarsData: [
                              LineChartBarData(
                                spots: [for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), series.previous[i])],
                                color: Colors.blueGrey.shade300,
                                barWidth: 2,
                                dashArray: const [6, 4],
                                dotData: const FlDotData(show: false),
                              ),
                              LineChartBarData(
                                spots: [for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), series.current[i])],
                                color: theme.colorScheme.primary,
                                barWidth: 3,
                                isCurved: true,
                                dotData: const FlDotData(show: true),
                              ),
                            ],
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            gridData: const FlGridData(drawVerticalLine: false),
                            borderData: FlBorderData(show: false),
                            titlesData: _titles((index) => _monthLabel(fiscalMonth, index.toInt())),
                            barGroups: [
                              for (var i = 0; i < 12; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(toY: series.previous[i], color: Colors.blueGrey.shade300, width: 7),
                                    BarChartRodData(toY: series.current[i], color: theme.colorScheme.primary, width: 7),
                                  ],
                                ),
                            ],
                          ),
                        ),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: l.budgetVsActual,
          child: budgets.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('$error'),
            data: (records) {
              final budget = records
                  .where((record) => record.status == 'approved' && record.fiscalYearStart == currentStart)
                  .firstOrNull;
              if (budget == null) return Text(l.noBudgetRecorded);
              return Column(
                children: [
                  for (final entry in budget.categoryAmounts.entries)
                    () {
                      final actual = expenses
                          .where(
                            (expense) =>
                                expense.category == entry.key &&
                                !expense.date.isBefore(currentStart) &&
                                !expense.date.isAfter(today),
                          )
                          .fold(0, (sum, expense) => sum + expense.amount);
                      final ratio = entry.value == 0 ? 0.0 : actual / entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(entry.key)),
                                Text('${inr.format(actual)} / ${inr.format(entry.value)}'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: ratio.clamp(0, 1),
                              color: ratio > 1 ? AppColors.red : Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      );
                    }(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  CategorySeries _liveSeries(
    String key,
    List<Expense> expenses,
    Iterable<IncomeEntry> income,
    List<PaymentRecord> payments,
    DateTime currentStart,
    DateTime previousStart,
    int fiscalMonth,
  ) {
    final isExpense = key.startsWith('expense:');
    final isIncome = key.startsWith('income:');
    final filter = key.substring(key.indexOf(':') + 1);
    final current = List<double>.filled(12, 0);
    final previous = List<double>.filled(12, 0);
    void add(DateTime date, num amount, String category) {
      final start = date.isBefore(currentStart) ? previousStart : currentStart;
      if (date.isBefore(start) || !date.isBefore(DateTime(start.year + 1, fiscalMonth, 1))) return;
      final monthIndex = (date.month - fiscalMonth + 12) % 12;
      final values = start == currentStart ? current : previous;
      values[monthIndex] += amount.toDouble();
    }

    if (isExpense) {
      for (final item in expenses) {
        if (filter == 'all' || filter == item.category) add(item.date, item.amount, item.category);
      }
    } else if (isIncome) {
      for (final item in income) {
        if (filter == 'all' || filter == item.categoryName) add(item.receivedOn, item.amount, item.categoryName);
      }
      if (filter == 'all') {
        for (final item in payments) {
          add(item.paidOn, item.amount, 'Dues');
        }
      }
    } else {
      for (final item in payments) {
        if (filter == item.head || (filter == 'Advance' && item.head == null))
          add(item.paidOn, item.amount, item.head ?? 'Advance');
      }
    }
    return CategorySeries(
      isExpense
          ? (filter == 'all' ? 'All expenses' : filter)
          : isIncome
          ? (filter == 'all' ? 'All income' : filter)
          : filter,
      previous,
      current,
    );
  }

  String _monthLabel(int fiscalMonth, int index) =>
      DateFormat('MMM').format(DateTime(2020, ((fiscalMonth - 1 + index) % 12) + 1, 1));
}

double _pct(double now, double before) => before == 0 ? 0 : (now - before) / before * 100;

class _ChangeChip extends StatelessWidget {
  const _ChangeChip(this.now, this.before, {required this.higherIsBad});
  final double now;
  final double before;
  final bool higherIsBad;

  @override
  Widget build(BuildContext context) {
    final p = _pct(now, before);
    final up = p >= 0;
    final bad = up == higherIsBad && p.abs() >= 0.5;
    return Pill('${up ? '▲' : '▼'} ${p.abs().toStringAsFixed(1)}%', color: bad ? AppColors.red : AppColors.green);
  }
}

bool _isIncome(String name) => name == totalIncome.name || incomeSeries.any((s) => s.name == name);

class _YoY extends StatelessWidget {
  const _YoY({required this.series});
  final CategorySeries series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bad = !_isIncome(series.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(label: '$currentFy (Apr–Sep)', value: inr.format(series.currToDate()), icon: Icons.today),
            StatCard(
              label: '$previousFy (Apr–Sep)',
              value: inr.format(series.prevToDate()),
              icon: Icons.history,
              color: Colors.blueGrey,
            ),
            StatCard(
              label: 'Change',
              value:
                  '${_pct(series.currToDate(), series.prevToDate()) >= 0 ? '+' : ''}${_pct(series.currToDate(), series.prevToDate()).toStringAsFixed(1)}%',
              icon: Icons.trending_up,
              color: (_pct(series.currToDate(), series.prevToDate()) >= 0) == bad ? AppColors.red : AppColors.green,
            ),
            StatCard(
              label: '$previousFy full year',
              value: inr.format(series.previous.fold(0.0, (a, b) => a + b)),
              icon: Icons.calendar_today,
              color: Colors.indigo,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '${series.name}: month by month, $currentFy vs $previousFy',
          child: Column(
            children: [
              SizedBox(
                height: 240,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: _titles((v) => fyMonths[v.toInt()]),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), series.previous[i])],
                        color: Colors.blueGrey.shade300,
                        barWidth: 2,
                        dashArray: [6, 4],
                        dotData: const FlDotData(show: false),
                      ),
                      LineChartBarData(
                        spots: [for (var i = 0; i < closedMonths; i++) FlSpot(i.toDouble(), series.current[i])],
                        color: scheme.primary,
                        barWidth: 3,
                        isCurved: true,
                        preventCurveOverShooting: true,
                        dotData: const FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legend(scheme.primary, currentFy),
                  const SizedBox(width: 16),
                  _legend(Colors.blueGrey.shade300, previousFy),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoM extends StatelessWidget {
  const _MoM({required this.series});
  final CategorySeries series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last12 = [...series.previous.skip(closedMonths), ...series.current.take(closedMonths)];
    final labels = [...fyMonths.skip(closedMonths), ...fyMonths.take(closedMonths)];
    final thisM = last12.last, prevM = last12[last12.length - 2], sameLastYear = series.previous[closedMonths - 1];
    final bad = !_isIncome(series.name);
    Color c(double a, double b) => (a >= b) == bad ? AppColors.red : AppColors.green;
    String p(double a, double b) => '${_pct(a, b) >= 0 ? '+' : ''}${_pct(a, b).toStringAsFixed(1)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(label: 'Sep 2026', value: inr.format(thisM), icon: Icons.today),
            StatCard(label: 'Aug 2026', value: inr.format(prevM), icon: Icons.history, color: Colors.blueGrey),
            StatCard(label: 'vs last month', value: p(thisM, prevM), icon: Icons.swap_vert, color: c(thisM, prevM)),
            StatCard(
              label: 'vs Sep 2025',
              value: p(thisM, sameLastYear),
              icon: Icons.compare_arrows,
              color: c(thisM, sameLastYear),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '${series.name}: last 12 months',
          child: SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: _titles((v) => labels[v.toInt()]),
                barGroups: [
                  for (var i = 0; i < 12; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: last12[i],
                          width: 14,
                          color: i == 11
                              ? scheme.primary
                              : (i == 10 ? scheme.primary.withValues(alpha: 0.55) : Colors.blueGrey.shade200),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

FlTitlesData _titles(String Function(double) bottom) => FlTitlesData(
  topTitles: const AxisTitles(),
  rightTitles: const AxisTitles(),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 48,
      getTitlesWidget: (v, meta) =>
          v == meta.max ? const SizedBox.shrink() : Text(_short(v), style: const TextStyle(fontSize: 10)),
    ),
  ),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: 1,
      getTitlesWidget: (v, _) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(bottom(v), style: const TextStyle(fontSize: 10)),
      ),
    ),
  ),
);

String _short(double v) => v >= 100000
    ? '${(v / 100000).toStringAsFixed(2)}L'
    : (v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0));

Widget _legend(Color c, String t) => Row(
  children: [
    Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    ),
    const SizedBox(width: 6),
    Text(t, style: const TextStyle(fontSize: 12)),
  ],
);

class _Insights extends StatelessWidget {
  const _Insights({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final mom = [...expenseSeries]
      ..sort(
        (a, b) => _pct(
          b.current[closedMonths - 1],
          b.current[closedMonths - 2],
        ).compareTo(_pct(a.current[closedMonths - 1], a.current[closedMonths - 2])),
      );
    final yoy = [...expenseSeries]
      ..sort((a, b) => _pct(b.currToDate(), b.prevToDate()).compareTo(_pct(a.currToDate(), a.prevToDate())));
    final saver = yoy.last;
    final items = <(IconData, Color, String, String)>[
      for (final s in mom.take(2))
        (
          Icons.trending_up,
          AppColors.red,
          '${s.name}: Sep ${inr.format(s.current[closedMonths - 1])} vs Aug ${inr.format(s.current[closedMonths - 2])} (${_pct(s.current[closedMonths - 1], s.current[closedMonths - 2]).toStringAsFixed(0)}% up)',
          s.name,
        ),
      for (final s in yoy.take(2))
        (
          Icons.compare_arrows,
          AppColors.amber,
          '${s.name}: ${_pct(s.currToDate(), s.prevToDate()).toStringAsFixed(0)}% higher than last year (Apr–Sep)',
          s.name,
        ),
      (
        Icons.savings_outlined,
        AppColors.green,
        '${saver.name}: ${_pct(saver.currToDate(), saver.prevToDate()).abs().toStringAsFixed(0)}% lower than last year',
        saver.name,
      ),
      (
        Icons.account_balance_wallet_outlined,
        Colors.indigo,
        'Surplus Apr–Sep: ${inr.format(totalIncome.currToDate() - totalExpense.currToDate())} (last year ${inr.format(totalIncome.prevToDate() - totalExpense.prevToDate())})',
        totalIncome.name,
      ),
    ];
    return Column(
      children: [
        for (final (icon, color, text, cat) in items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: color),
            title: Text(text),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => onPick(cat),
          ),
      ],
    );
  }
}

class _Budget extends StatelessWidget {
  const _Budget();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final s in expenseSeries.take(6))
          () {
            final budget = s.previous.fold(0.0, (a, b) => a + b) * 1.06;
            final pace = budget * closedMonths / 12;
            final ratio = s.currToDate() / pace;
            final color = ratio > 1.05 ? AppColors.red : (ratio > 0.98 ? AppColors.amber : AppColors.green);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.name, style: const TextStyle(fontSize: 13))),
                      Text(
                        '${inr.format(s.currToDate())} / ${inr.format(budget)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (s.currToDate() / budget).clamp(0, 1),
                    color: color,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }(),
        const SizedBox(height: 4),
        const Text(
          'Budget = AGM-approved annual budget. Red = spending ahead of pace.',
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}

class _CategoryTable extends StatelessWidget {
  const _CategoryTable({required this.selected, required this.onPick});
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final rows = [...expenseSeries, totalExpense, ...incomeSeries, totalIncome];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Category')),
          DataColumn(label: Text(currentFy), numeric: true),
          DataColumn(label: Text(previousFy), numeric: true),
          DataColumn(label: Text('Change')),
        ],
        rows: [
          for (final s in rows)
            DataRow(
              selected: s.name == selected,
              onSelectChanged: (_) => onPick(s.name),
              cells: [
                DataCell(
                  Text(
                    s.name,
                    style: TextStyle(fontWeight: s == totalExpense || s == totalIncome ? FontWeight.w700 : null),
                  ),
                ),
                DataCell(Text(inr.format(s.currToDate()))),
                DataCell(Text(inr.format(s.prevToDate()))),
                DataCell(_ChangeChip(s.currToDate(), s.prevToDate(), higherIsBad: !_isIncome(s.name))),
              ],
            ),
        ],
      ),
    );
  }
}

class _CollectionChart extends StatelessWidget {
  const _CollectionChart();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 80,
              maxY: 100,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 5,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, _) => Text(fyMonths[v.toInt()], style: const TextStyle(fontSize: 10)),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), collectionPrev[i])],
                  color: Colors.blueGrey.shade300,
                  dashArray: [6, 4],
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: [for (var i = 0; i < collectionCurr.length; i++) FlSpot(i.toDouble(), collectionCurr[i])],
                  color: scheme.primary,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(scheme.primary, currentFy),
            const SizedBox(width: 16),
            _legend(Colors.blueGrey.shade300, previousFy),
          ],
        ),
      ],
    );
  }
}
