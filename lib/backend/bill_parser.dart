/// Best-effort guess of expense details from the text read off a bill photo. Every field may be null.
class BillGuess {
  const BillGuess({this.vendor, this.amount, this.date, this.invoiceNo, this.gstin});

  final String? vendor;
  final int? amount;
  final DateTime? date;
  final String? invoiceNo;
  final String? gstin;

  bool get isEmpty => vendor == null && amount == null && date == null && invoiceNo == null && gstin == null;
}

final _num = RegExp(r'(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+\.\d{1,2}|\d+)');
final _totalWord = RegExp(
  r'grand\s*total|net\s*(amount|payable|total)|amount\s*payable|total\s*amount|bill\s*amount|\btotal\b',
  caseSensitive: false,
);
final _finalTotalWord = RegExp(
  r'\b(?:grand\s*total|net\s*(?:amount|payable|total)|amount\s*payable|payable\s*amount)\b',
  caseSensitive: false,
);
final _numericDate = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})\b');
final _textDate = RegExp(
  r'\b(\d{1,2})[\s-]*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s,-]*(\d{2,4})\b',
  caseSensitive: false,
);
final _gstin = RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b');
final _invoice = RegExp(
  r'(?:invoice|bill|receipt)\s*(?:no|number|#)\.?\s*[:\-]?\s*([A-Z0-9][A-Z0-9/\-]{1,20})',
  caseSensitive: false,
);
const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

double? _value(String s) => double.tryParse(s.replaceAll(',', ''));

BillGuess parseBill(String text, {DateTime? today}) {
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  final now = today ?? DateTime.now();

  int? amount;
  double best = 0;
  final nonSubtotalLines = lines.where((l) => !RegExp('sub\\s*total', caseSensitive: false).hasMatch(l));
  for (final l in nonSubtotalLines.where(_finalTotalWord.hasMatch)) {
    for (final m in _num.allMatches(l)) {
      final v = _value(m.group(1)!) ?? 0;
      if (v > best && v < 10000000) best = v;
    }
  }
  if (best == 0) {
    for (final l in nonSubtotalLines.where(_totalWord.hasMatch)) {
      for (final m in _num.allMatches(l)) {
        final v = _value(m.group(1)!) ?? 0;
        if (v > best && v < 10000000) best = v;
      }
    }
  }
  if (best == 0) {
    final withoutDates = text.replaceAll(_numericDate, ' ').replaceAll(_textDate, ' ');
    for (final m in _num.allMatches(withoutDates)) {
      final raw = m.group(1)!;
      if (!raw.contains('.') && !raw.contains(',')) continue;
      final v = _value(raw) ?? 0;
      if (v > best && v < 10000000) best = v;
    }
  }
  if (best > 0) amount = best.round();

  DateTime? date;
  DateTime? valid(int y, int mo, int d) {
    if (y < 100) y += 2000;
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) return null;
    return dt.isAfter(now.add(const Duration(days: 1))) || dt.year < now.year - 2 ? null : dt;
  }

  for (final m in _numericDate.allMatches(text)) {
    date = valid(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    if (date != null) break;
  }
  if (date == null) {
    for (final m in _textDate.allMatches(text)) {
      date = valid(
        int.parse(m.group(3)!),
        _months.indexOf(m.group(2)!.toLowerCase().substring(0, 3)) + 1,
        int.parse(m.group(1)!),
      );
      if (date != null) break;
    }
  }

  String? vendor;
  for (final l in lines.take(6)) {
    final letters = RegExp('[A-Za-z]').allMatches(l).length;
    if (letters < 3 ||
        RegExp(r'invoice|bill|receipt|gst|tax|phone|ph:|mob|date|www|@', caseSensitive: false).hasMatch(l)) {
      continue;
    }
    vendor = l.replaceAll(RegExp(r'[^A-Za-z0-9&.,\- ]'), '').trim();
    if (vendor.length > 60) vendor = vendor.substring(0, 60);
    if (vendor.isNotEmpty) break;
    vendor = null;
  }

  return BillGuess(
    vendor: vendor,
    amount: amount,
    date: date,
    invoiceNo: _invoice.firstMatch(text)?.group(1),
    gstin: _gstin.firstMatch(text.toUpperCase())?.group(0),
  );
}
