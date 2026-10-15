import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/liomont_report_pdf.dart';

const _formTitles = {
  'cotizacion': 'Solicitar cotización',
  'demo': 'Agendar demo',
  'catalogo': 'Descargar catálogo',
  'contacto': 'Formulario de contacto',
};

/// Builds the leads directory PDF (landscape, Liomont logo on every page).
///
/// [leads] are rows from `AdminRepository.fetchLeadsDirectory`; [scopeLabel]
/// describes what was exported (a collaborator or "Todos los colaboradores").
Future<Uint8List> buildLeadsDirectoryPdf({
  required List<Map<String, dynamic>> leads,
  required String scopeLabel,
}) async {
  final logo = await loadLiomontLogo();
  final generatedAt = DateTime.now();
  final converted = leads.where((l) => l['is_converted'] == true).length;

  final doc = pw.Document(title: 'Directorio de leads', author: 'Liomont');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
      header: (context) => liomontReportHeader(
        logo: logo,
        title: 'Directorio de leads',
        subtitle: scopeLabel,
      ),
      footer: (context) => liomontReportFooter(context, generatedAt),
      build: (context) => [
        pw.Row(
          children: [
            liomontSummaryChip('Leads', '${leads.length}'),
            pw.SizedBox(width: 10),
            liomontSummaryChip('Nuevos', '${leads.length - converted}'),
            pw.SizedBox(width: 10),
            liomontSummaryChip('Contactados', '$converted'),
          ],
        ),
        pw.SizedBox(height: 14),
        if (leads.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 40),
            child: pw.Center(
              child: pw.Text(
                'No hay leads registrados para esta selección.',
                style: const pw.TextStyle(color: PdfColors.grey700),
              ),
            ),
          )
        else
          liomontTable(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(1.3),
              2: pw.FlexColumnWidth(1.8),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1.3),
              5: pw.FlexColumnWidth(0.9),
              6: pw.FlexColumnWidth(1.6),
              7: pw.FlexColumnWidth(1.1),
              8: pw.FlexColumnWidth(1.0),
            },
            headers: leadsDirectoryHeaders,
            data: [for (final lead in leads) leadsDirectoryRow(lead)],
          ),
      ],
    ),
  );

  return doc.save();
}

/// Column headers shared by the PDF and CSV leads directory.
const leadsDirectoryHeaders = [
  'Lead',
  'Empresa',
  'Correo',
  'Teléfono',
  'Formulario',
  'Estado',
  'Colaborador',
  'Organización',
  'Último contacto',
];

/// CSV-only extra columns, appended after [leadsDirectoryHeaders].
const leadsDirectoryCsvExtraHeaders = [
  'Correo del colaborador',
  'Ubicación',
  'Primera visita',
  'Datos del formulario',
];

/// One leads-directory row matching [leadsDirectoryHeaders].
List<String> leadsDirectoryRow(Map<String, dynamic> lead) {
  final formData = lead['form_data'] is Map
      ? Map<String, dynamic>.from(lead['form_data'] as Map)
      : const <String, dynamic>{};
  final formType = (lead['form_type'] as String?)?.trim() ?? '';
  final lastSeen = DateTime.tryParse(lead['last_seen'] as String? ?? '');
  return [
    _orDash(lead['name'] as String?, fallback: 'Visitante anónimo'),
    _orDash(lead['company'] as String?),
    _orDash(_formValue(formData, const ['correo', 'email', 'mail'])),
    _orDash(
      _formValue(formData, const ['tel', 'whats', 'celular', 'phone', 'móvil']),
    ),
    _orDash(_formTitles[formType] ?? formType),
    lead['is_converted'] == true ? 'Contactado' : 'Nuevo',
    _orDash(lead['collaborator_name'] as String?),
    _orDash(lead['org_name'] as String?),
    lastSeen == null ? '-' : formatReportDate(lastSeen.toLocal()),
  ];
}

/// First non-empty form value whose field label contains one of [hints].
String? _formValue(Map<String, dynamic> formData, List<String> hints) {
  for (final entry in formData.entries) {
    if (entry.key.startsWith('_')) continue;
    final key = entry.key.toLowerCase();
    if (!hints.any(key.contains)) continue;
    final value = entry.value?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

// Plain '-' (not an em dash): the PDF's built-in Helvetica can't draw '—'.
String _orDash(String? value, {String fallback = '-'}) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

/// Extra CSV values matching [leadsDirectoryCsvExtraHeaders].
List<String> leadsDirectoryCsvExtras(Map<String, dynamic> lead) {
  final formData = lead['form_data'] is Map
      ? Map<String, dynamic>.from(lead['form_data'] as Map)
      : const <String, dynamic>{};
  final firstSeen = DateTime.tryParse(lead['first_seen'] as String? ?? '');
  return [
    (lead['collaborator_email'] as String?)?.trim() ?? '',
    (lead['location'] as String?)?.trim() ?? '',
    firstSeen == null ? '' : formatReportDate(firstSeen.toLocal()),
    [
      for (final entry in formData.entries)
        if (!entry.key.startsWith('_') &&
            (entry.value?.toString().trim().isNotEmpty ?? false))
          '${entry.key}: ${entry.value.toString().trim()}',
    ].join(' | '),
  ];
}
