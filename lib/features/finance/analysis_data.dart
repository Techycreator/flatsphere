/// Demo monthly figures (₹) for the financial analysis tab.
/// FY runs April–March; index 0 = April.
const fyMonths = ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar'];
const currentFy = 'FY 2026-27';
const previousFy = 'FY 2025-26';

/// Months of the current FY with closed books (Apr–Sep).
const closedMonths = 6;
const flatCount = 120;

class CategorySeries {
  const CategorySeries(this.name, this.previous, this.current);
  final String name;
  final List<double> previous;
  final List<double> current;

  double prevToDate([int months = closedMonths]) => previous.take(months).fold(0.0, (a, b) => a + b);
  double currToDate([int months = closedMonths]) => current.take(months).fold(0.0, (a, b) => a + b);
}

List<double> _series(double base, List<double> season, double growth, int seed, {Map<int, double> spikes = const {}}) =>
    [
      for (var i = 0; i < 12; i++)
        (base * season[i] * growth * (1 + (((i * 37 + seed * 11) % 13) - 6) / 100) * (spikes[i] ?? 1)).roundToDouble(),
    ];

const _flat = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
const _summer = [1.25, 1.3, 1.0, 0.9, 0.9, 0.95, 1.0, 1.0, 1.0, 1.05, 1.1, 1.2];
const _monsoon = [0.7, 0.8, 1.5, 1.6, 1.4, 1.0, 1.1, 0.9, 0.8, 0.8, 0.8, 0.8];

final expenseSeries = <CategorySeries>[
  CategorySeries('Staff salaries', _series(92000, _flat, 1.0, 1), _series(92000, _flat, 1.07, 1)),
  CategorySeries('Security agency', _series(59000, _flat, 1.0, 2), _series(59000, _flat, 1.05, 2)),
  CategorySeries('Common electricity', _series(17500, _summer, 1.0, 3), _series(17500, _summer, 1.04, 3)),
  CategorySeries('Water bill', _series(9400, _summer, 1.0, 4), _series(9400, _summer, 1.03, 4)),
  CategorySeries(
    'Generator diesel',
    _series(7800, _monsoon, 1.0, 5),
    _series(7800, _monsoon, 1.06, 5, spikes: {5: 1.55}),
  ),
  CategorySeries(
    'STP maintenance',
    _series(6200, _flat, 1.0, 6),
    _series(6200, _flat, 1.05, 6, spikes: {2: 1.9, 5: 2.1}),
  ),
  CategorySeries('Lift & DG AMC', _series(23500, _flat, 1.0, 7), _series(23500, _flat, 1.04, 7)),
  CategorySeries('Cleaning supplies', _series(6100, _flat, 1.0, 8), _series(6100, _flat, 0.96, 8)),
  CategorySeries('Repairs & maintenance', _series(11000, _flat, 1.0, 9), _series(11000, _flat, 1.12, 9)),
];

final incomeSeries = <CategorySeries>[
  CategorySeries('Maintenance collected', _series(301000, _flat, 1.0, 10), _series(301000, _flat, 1.06, 10)),
  CategorySeries('Party hall & common area rent', _series(4200, _summer, 1.0, 11), _series(4200, _summer, 1.15, 11)),
  CategorySeries(
    'Advertisement & sponsorship',
    _series(5000, _flat, 1.0, 12),
    _series(5000, _flat, 1.2, 12, spikes: {4: 4.0}),
  ),
];

CategorySeries _sum(String name, List<CategorySeries> xs) => CategorySeries(
  name,
  [for (var i = 0; i < 12; i++) xs.fold(0.0, (a, s) => a + s.previous[i])],
  [for (var i = 0; i < 12; i++) xs.fold(0.0, (a, s) => a + s.current[i])],
);

final totalExpense = _sum('All expenses', expenseSeries);
final totalIncome = _sum('Total income', incomeSeries);

/// Monthly collection efficiency (% of dues collected by month end).
const collectionPrev = [88.0, 90.0, 86.0, 87.0, 91.0, 89.0, 90.0, 92.0, 88.0, 89.0, 90.0, 93.0];
const collectionCurr = [91.0, 92.0, 90.0, 89.0, 93.0, 90.0];
