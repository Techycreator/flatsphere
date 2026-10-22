import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'analysis_data.dart';

enum _Mode { yoy, mom }

class AnalysisTab extends StatefulWidget {
  const AnalysisTab({super.key});

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> {
  _Mode _mode = _Mode.yoy;
  String _category = 'All expenses';

  List<CategorySeries> get _all => [totalExpense, ...expenseSeries, totalIncome, ...incomeSeries];
  CategorySeries get _series => _all.firstWhere((s) => s.name == _category);

  @override
  Widget build(BuildContext context) {
    final s = _series;
    final theme = Theme.of(context);
    return PageBody(children: [
      Card(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        child: const ListTile(
          leading: Icon(Icons.visibility_outlined),
          title: Text('Visible to all EC members (interim access)'),
          subtitle: Text('Any change to who can see this goes through W2: Secretary review → EC vote → President approval.'),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.yoy, label: Text('Year on year'), icon: Icon(Icons.compare_arrows)),
            ButtonSegment(value: _Mode.mom, label: Text('Month on month'), icon: Icon(Icons.calendar_month)),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<String>(
            initialValue: _category,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Category', isDense: true),
            items: [for (final c in _all) DropdownMenuItem(value: c.name, child: Text(c.name))],
            onChanged: (v) => setState(() => _category = v!),
          ),
        ),
        TextButton.icon(onPressed: () => toast(context, 'Analysis exported to Excel and PDF'), icon: const Icon(Icons.download), label: const Text('Export')),
      ]),
      const SizedBox(height: 16),
      _mode == _Mode.yoy ? _YoY(series: s) : _MoM(series: s),
      const SizedBox(height: 16),
      TwoCol(
        left: SectionCard(title: 'Insights', child: _Insights(onPick: (c) => setState(() => _category = c))),
        right: const SectionCard(title: 'Budget vs actual ($currentFy, Apr–Sep)', child: _Budget()),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Category comparison – $currentFy vs $previousFy (Apr–Sep)',
        child: _CategoryTable(selected: _category, onPick: (c) => setState(() => _category = c)),
      ),
      const SizedBox(height: 16),
      TwoCol(
        left: const SectionCard(title: 'Collection efficiency (% collected by month end)', child: _CollectionChart()),
        right: SectionCard(
          title: 'Cost per flat (monthly average)',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inr.format(totalExpense.currToDate() / closedMonths / flatCount), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('$currentFy (Apr–Sep) · last year ${inr.format(totalExpense.prevToDate() / closedMonths / flatCount)}'),
            const SizedBox(height: 8),
            _ChangeChip(totalExpense.currToDate(), totalExpense.prevToDate(), higherIsBad: true),
          ]),
        ),
      ),
    ]);
  }
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StatGrid(children: [
        StatCard(label: '$currentFy (Apr–Sep)', value: inr.format(series.currToDate()), icon: Icons.today),
        StatCard(label: '$previousFy (Apr–Sep)', value: inr.format(series.prevToDate()), icon: Icons.history, color: Colors.blueGrey),
        StatCard(
          label: 'Change',
          value: '${_pct(series.currToDate(), series.prevToDate()) >= 0 ? '+' : ''}${_pct(series.currToDate(), series.prevToDate()).toStringAsFixed(1)}%',
          icon: Icons.trending_up,
          color: (_pct(series.currToDate(), series.prevToDate()) >= 0) == bad ? AppColors.red : AppColors.green,
        ),
        StatCard(label: '$previousFy full year', value: inr.format(series.previous.fold(0.0, (a, b) => a + b)), icon: Icons.calendar_today, color: Colors.indigo),
      ]),
      const SizedBox(height: 16),
      SectionCard(
        title: '${series.name}: month by month, $currentFy vs $previousFy',
        child: Column(children: [
          SizedBox(
            height: 240,
            child: LineChart(LineChartData(
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
            )),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _legend(scheme.primary, currentFy),
            const SizedBox(width: 16),
            _legend(Colors.blueGrey.shade300, previousFy),
          ]),
        ]),
      ),
    ]);
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StatGrid(children: [
        StatCard(label: 'Sep 2026', value: inr.format(thisM), icon: Icons.today),
        StatCard(label: 'Aug 2026', value: inr.format(prevM), icon: Icons.history, color: Colors.blueGrey),
        StatCard(label: 'vs last month', value: p(thisM, prevM), icon: Icons.swap_vert, color: c(thisM, prevM)),
        StatCard(label: 'vs Sep 2025', value: p(thisM, sameLastYear), icon: Icons.compare_arrows, color: c(thisM, sameLastYear)),
      ]),
      const SizedBox(height: 16),
      SectionCard(
        title: '${series.name}: last 12 months',
        child: SizedBox(
          height: 240,
          child: BarChart(BarChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: _titles((v) => labels[v.toInt()]),
            barGroups: [
              for (var i = 0; i < 12; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: last12[i],
                    width: 14,
                    color: i == 11 ? scheme.primary : (i == 10 ? scheme.primary.withValues(alpha: 0.55) : Colors.blueGrey.shade200),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ]),
            ],
          )),
        ),
      ),
    ]);
  }
}

FlTitlesData _titles(String Function(double) bottom) => FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,
          getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(_short(v), style: const TextStyle(fontSize: 10)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          getTitlesWidget: (v, _) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(bottom(v), style: const TextStyle(fontSize: 10))),
        ),
      ),
    );

String _short(double v) => v >= 100000 ? '${(v / 100000).toStringAsFixed(1)}L' : (v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0));

Widget _legend(Color c, String t) => Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(t, style: const TextStyle(fontSize: 12)),
    ]);

class _Insights extends StatelessWidget {
  const _Insights({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final mom = [...expenseSeries]..sort((a, b) => _pct(b.current[closedMonths - 1], b.current[closedMonths - 2]).compareTo(_pct(a.current[closedMonths - 1], a.current[closedMonths - 2])));
    final yoy = [...expenseSeries]..sort((a, b) => _pct(b.currToDate(), b.prevToDate()).compareTo(_pct(a.currToDate(), a.prevToDate())));
    final saver = yoy.last;
    final items = <(IconData, Color, String, String)>[
      for (final s in mom.take(2))
        (Icons.trending_up, AppColors.red, '${s.name}: Sep ${inr.format(s.current[closedMonths - 1])} vs Aug ${inr.format(s.current[closedMonths - 2])} (${_pct(s.current[closedMonths - 1], s.current[closedMonths - 2]).toStringAsFixed(0)}% up)', s.name),
      for (final s in yoy.take(2))
        (Icons.compare_arrows, AppColors.amber, '${s.name}: ${_pct(s.currToDate(), s.prevToDate()).toStringAsFixed(0)}% higher than last year (Apr–Sep)', s.name),
      (Icons.savings_outlined, AppColors.green, '${saver.name}: ${_pct(saver.currToDate(), saver.prevToDate()).abs().toStringAsFixed(0)}% lower than last year', saver.name),
      (Icons.account_balance_wallet_outlined, Colors.indigo, 'Surplus Apr–Sep: ${inr.format(totalIncome.currToDate() - totalExpense.currToDate())} (last year ${inr.format(totalIncome.prevToDate() - totalExpense.prevToDate())})', totalIncome.name),
    ];
    return Column(children: [
      for (final (icon, color, text, cat) in items)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: Text(text),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => onPick(cat),
        ),
    ]);
  }
}

class _Budget extends StatelessWidget {
  const _Budget();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final s in expenseSeries.take(6))
        () {
          final budget = s.previous.fold(0.0, (a, b) => a + b) * 1.06;
          final pace = budget * closedMonths / 12;
          final ratio = s.currToDate() / pace;
          final color = ratio > 1.05 ? AppColors.red : (ratio > 0.98 ? AppColors.amber : AppColors.green);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s.name, style: const TextStyle(fontSize: 13))),
                Text('${inr.format(s.currToDate())} / ${inr.format(budget)}', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: (s.currToDate() / budget).clamp(0, 1), color: color, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            ]),
          );
        }(),
      const SizedBox(height: 4),
      const Text('Budget = AGM-approved annual budget (demo: last year + 6%). Red = spending ahead of pace.', style: TextStyle(fontSize: 11)),
    ]);
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
                DataCell(Text(s.name, style: TextStyle(fontWeight: s == totalExpense || s == totalIncome ? FontWeight.w700 : null))),
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
    return Column(children: [
      SizedBox(
        height: 180,
        child: LineChart(LineChartData(
          minY: 80,
          maxY: 100,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 5, getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, _) => Text(fyMonths[v.toInt()], style: const TextStyle(fontSize: 10)))),
          ),
          lineBarsData: [
            LineChartBarData(spots: [for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), collectionPrev[i])], color: Colors.blueGrey.shade300, dashArray: [6, 4], barWidth: 2, dotData: const FlDotData(show: false)),
            LineChartBarData(spots: [for (var i = 0; i < collectionCurr.length; i++) FlSpot(i.toDouble(), collectionCurr[i])], color: scheme.primary, barWidth: 3, dotData: const FlDotData(show: true)),
          ],
        )),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [_legend(scheme.primary, currentFy), const SizedBox(width: 16), _legend(Colors.blueGrey.shade300, previousFy)]),
    ]);
  }
}
