import 'dart:typed_data';

import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/models.dart';
import '../../widgets/common.dart';

/// Builds a one-page receipt from the stored payment record.
Future<Uint8List> _buildReceipt(PaymentRecord p, String association) async {
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
  return doc.save();
}

/// Downloads/shares the receipt as a PDF.
Future<void> downloadReceipt(PaymentRecord p, String association) async =>
    Printing.sharePdf(bytes: await _buildReceipt(p, association), filename: '${p.receiptNo}.pdf');

/// Shows the receipt on screen without downloading; the dialog still offers Download and Print.
Future<void> viewReceipt(m.BuildContext context, PaymentRecord p, String association) async {
  final bytes = await _buildReceipt(p, association);
  if (!context.mounted) return;
  await m.showDialog<void>(
    context: context,
    builder: (ctx) => m.Dialog(
      insetPadding: const m.EdgeInsets.all(12),
      child: m.ConstrainedBox(
        constraints: const m.BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: m.Column(
          children: [
            m.Padding(
              padding: const m.EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: m.Row(
                children: [
                  m.Expanded(child: m.Text(p.receiptNo, style: const m.TextStyle(fontWeight: m.FontWeight.w600))),
                  m.IconButton(
                    tooltip: 'Download PDF',
                    icon: const m.Icon(m.Icons.download_outlined),
                    onPressed: () => Printing.sharePdf(bytes: bytes, filename: '${p.receiptNo}.pdf'),
                  ),
                  m.IconButton(tooltip: 'Close', icon: const m.Icon(m.Icons.close), onPressed: () => m.Navigator.pop(ctx)),
                ],
              ),
            ),
            m.Expanded(
              child: PdfPreview(
                build: (_) async => bytes,
                useActions: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                allowSharing: false,
                allowPrinting: false,
                pdfFileName: '${p.receiptNo}.pdf',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
