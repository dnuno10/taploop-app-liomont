import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared look for every downloadable report (leads directory, analytics):
/// Liomont logo, brand colors, header/footer, summary chips and tables.

const liomontLogoAsset = 'assets/images/liomont.png';

/// Brand cyan of the Liomont logo.
const liomontBlue = PdfColor.fromInt(0xFF0094D3);

/// Brand near-black of the Liomont wordmark.
const liomontInk = PdfColor.fromInt(0xFF1A1A1A);

/// Light tint of [liomontBlue] for chips and alternate rows.
const liomontBlueTint = PdfColor.fromInt(0xFFE6F4FB);

Future<pw.MemoryImage> loadLiomontLogo() async {
  final data = await rootBundle.load(liomontLogoAsset);
  return pw.MemoryImage(data.buffer.asUint8List());
}

String formatReportDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

pw.Widget liomontReportHeader({
  required pw.MemoryImage logo,
  required String title,
  required String subtitle,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 12),
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: liomontBlue, width: 1.4)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 34, child: pw.Image(logo)),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: liomontInk,
              ),
            ),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget liomontReportFooter(pw.Context context, DateTime generatedAt) {
  return pw.Row(
    children: [
      pw.Text(
        'Generado el ${formatReportDate(generatedAt)}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.Spacer(),
      pw.Text(
        'Página ${context.pageNumber} de ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    ],
  );
}

pw.Widget liomontSummaryChip(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: pw.BoxDecoration(
      color: liomontBlueTint,
      borderRadius: pw.BorderRadius.circular(12),
    ),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: liomontBlue,
          ),
        ),
        pw.SizedBox(width: 5),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
      ],
    ),
  );
}

pw.Widget liomontSectionTitle(String title) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: liomontInk,
      ),
    ),
  );
}

pw.Widget liomontTable({
  required List<String> headers,
  required List<List<String>> data,
  Map<int, pw.TableColumnWidth>? columnWidths,
  double fontSize = 8,
}) {
  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(
      fontSize: fontSize + 0.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: liomontBlue),
    cellStyle: pw.TextStyle(fontSize: fontSize, color: liomontInk),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    oddRowDecoration: const pw.BoxDecoration(color: liomontBlueTint),
    border: null,
    columnWidths: columnWidths,
    headers: headers,
    data: data,
  );
}
