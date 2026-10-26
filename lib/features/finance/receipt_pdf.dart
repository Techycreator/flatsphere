import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/models.dart';
import '../../widgets/common.dart';

/// Builds a one-page receipt from the stored payment record and downloads/shares it.
Future<void> downloadReceipt(PaymentRecord p, String association) async {
  final doc = pw.Document();
  // The built-in PDF font has no ₹ glyph.
  final amount = 'Rs. ${NumberFormat.decimalPattern('en_IN').format(p.amount)}';
  final rows = [
    ('Receipt no.', p.receiptNo),
    ('Date', dateFmt.format(p.paidOn)),
    ('Flat', p.flatNumber),
    ('Towards', p.head ?? 'Advance / other'),
    ('Amount', amount),
    ('Mode', paymentModes[p.mode] ?? p.mode),
    if (p.reference != null) ('Reference', p.reference!),
  ];
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(association, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Payment receipt'),
          pw.Divider(),
          for (final (k, v) in rows)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.SizedBox(width: 90, child: pw.Text(k)),
                  pw.Expanded(
                    child: pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
            ),
          pw.Spacer(),
          pw.Text(
            'Computer-generated receipt from FlatSphere. No signature required.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    ),
  );
  await Printing.sharePdf(bytes: await doc.save(), filename: '${p.receiptNo}.pdf');
}
