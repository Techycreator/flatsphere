import 'package:flatsphere/backend/bill_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads vendor, total, date, invoice and GSTIN from bill text', () {
    const text =
        'Sree Electricals\nKakkanad, Kochi\nGSTIN: 32ABCDE1234F1Z5\nInvoice No: INV-2041\n'
        'Date: 12/10/2026\nWire 2.5mm  1,200.00\nSub Total 1,200.00\nGST 216.00\nGrand Total 1,416.00\n';
    final g = parseBill(text, today: DateTime(2026, 10, 20));
    expect(g.vendor, 'Sree Electricals');
    expect(g.amount, 1416);
    expect(g.date, DateTime(2026, 10, 12));
    expect(g.invoiceNo, 'INV-2041');
    expect(g.gstin, '32ABCDE1234F1Z5');
  });

  test('empty text gives nothing', () => expect(parseBill('').isEmpty, isTrue));
}
