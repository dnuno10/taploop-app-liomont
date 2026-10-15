import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'liomont_report_pdf.dart' show liomontLogoAsset;

/// One table in a [buildLiomontXlsx] report.
class XlsxSection {
  final String title;
  final List<String> headers;

  /// Cell values: `num` is written as a number, anything else as text.
  final List<List<Object?>> rows;

  const XlsxSection({
    required this.title,
    required this.headers,
    required this.rows,
  });
}

// Cell style indexes in styles.xml (cellXfs).
const _sDefault = 0;
const _sTitle = 1;
const _sSubtitle = 2;
const _sHeader = 3;
const _sCell = 4;
const _sCellAlt = 5;
const _sSection = 6;

// Brand colors (ARGB), same as the PDF reports.
const _blue = 'FF0094D3';
const _ink = 'FF1A1A1A';
const _tint = 'FFE6F4FB';

/// Builds a real Excel workbook (.xlsx) styled like the PDF reports: the
/// Liomont logo at the top, title/subtitle, and each [sections] table with a
/// brand-blue header row and alternating tinted rows.
Future<Uint8List> buildLiomontXlsx({
  required String sheetName,
  required String title,
  required String subtitle,
  required List<XlsxSection> sections,
  List<double>? columnWidths,
}) async {
  final logo = (await rootBundle.load(liomontLogoAsset)).buffer.asUint8List();

  final columnCount = sections.fold<int>(
    1,
    (max, s) => s.headers.length > max ? s.headers.length : max,
  );

  final rows = StringBuffer();
  var rowIndex = 0;

  void addRow(List<_Cell> cells, {double? height}) {
    rowIndex++;
    final attrs = height == null ? '' : ' ht="$height" customHeight="1"';
    rows.write('<row r="$rowIndex"$attrs>');
    for (var i = 0; i < cells.length; i++) {
      rows.write(cells[i].toXml('${_columnName(i)}$rowIndex'));
    }
    rows.write('</row>');
  }

  // Rows 1-3 hold the logo image.
  for (var i = 0; i < 3; i++) {
    addRow(const [], height: 20);
  }
  addRow([_Cell.text(title, _sTitle)], height: 26);
  addRow([_Cell.text(subtitle, _sSubtitle)]);

  for (final section in sections) {
    addRow(const []);
    addRow([_Cell.text(section.title, _sSection)], height: 20);
    addRow([for (final h in section.headers) _Cell.text(h, _sHeader)]);
    for (var r = 0; r < section.rows.length; r++) {
      final style = r.isOdd ? _sCellAlt : _sCell;
      final values = section.rows[r];
      addRow([
        for (var c = 0; c < section.headers.length; c++)
          _Cell.value(c < values.length ? values[c] : null, style),
      ]);
    }
  }

  final cols = StringBuffer('<cols>');
  for (var i = 0; i < columnCount; i++) {
    final width = columnWidths != null && i < columnWidths.length
        ? columnWidths[i]
        : 22;
    cols.write(
      '<col min="${i + 1}" max="${i + 1}" width="$width" customWidth="1"/>',
    );
  }
  cols.write('</cols>');

  final sheet =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews>'
      '<sheetFormatPr defaultRowHeight="16"/>'
      '$cols<sheetData>$rows</sheetData>'
      '<drawing r:id="rId1"/></worksheet>';

  // Logo: 40px tall, keeping the asset's aspect ratio (EMU = px * 9525).
  const logoHeightPx = 40;
  const logoWidthPx = logoHeightPx * 3422 ~/ 666;
  const emu = 9525;
  const drawing =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff>'
      '<xdr:row>0</xdr:row><xdr:rowOff>60000</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="${logoWidthPx * emu}" cy="${logoHeightPx * emu}"/>'
      '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="2" name="Liomont"/>'
      '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
      '<xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
      '<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${logoWidthPx * emu}" cy="${logoHeightPx * emu}"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
      '<xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>';

  final files = <String, Object>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${_xml(_sheetName(sheetName))}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml': _stylesXml,
    'xl/worksheets/sheet1.xml': sheet,
    'xl/worksheets/_rels/sheet1.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'
        '</Relationships>',
    'xl/drawings/drawing1.xml': drawing,
    'xl/drawings/_rels/drawing1.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>'
        '</Relationships>',
    'xl/media/image1.png': logo,
  };

  final archive = Archive();
  files.forEach((name, content) {
    archive.addFile(
      content is String
          ? ArchiveFile.string(name, content)
          : ArchiveFile.bytes(name, content as Uint8List),
    );
  });
  return ZipEncoder().encodeBytes(archive);
}

const _stylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="6">'
    '<font><sz val="11"/><color rgb="$_ink"/><name val="Calibri"/></font>'
    '<font><b/><sz val="16"/><color rgb="$_ink"/><name val="Calibri"/></font>'
    '<font><sz val="10"/><color rgb="FF6B6B6B"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
    '<font><sz val="11"/><color rgb="$_ink"/><name val="Calibri"/></font>'
    '<font><b/><sz val="12"/><color rgb="$_blue"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="$_blue"/><bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="$_tint"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"><color rgb="FFD6E6F0"/></left><right style="thin"><color rgb="FFD6E6F0"/></right>'
    '<top style="thin"><color rgb="FFD6E6F0"/></top><bottom style="thin"><color rgb="FFD6E6F0"/></bottom><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="7">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
    '<xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
    '<xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

class _Cell {
  final Object? value;
  final int style;

  const _Cell._(this.value, this.style);

  const _Cell.text(String text, int style) : this._(text, style);

  const _Cell.value(Object? value, int style) : this._(value, style);

  String toXml(String ref) {
    final v = value;
    if (v is num) return '<c r="$ref" s="$style"><v>$v</v></c>';
    final text = v?.toString() ?? '';
    if (text.isEmpty) {
      return style == _sDefault ? '' : '<c r="$ref" s="$style"/>';
    }
    return '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_xml(text)}</t></is></c>';
  }
}

String _columnName(int index) {
  var n = index + 1;
  final buffer = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    buffer.write(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return buffer.toString().split('').reversed.join();
}

/// Excel sheet names: max 31 chars, no []:*?/\ .
String _sheetName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final safe = cleaned.isEmpty ? 'Reporte' : cleaned;
  return safe.length > 31 ? safe.substring(0, 31) : safe;
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Strip control chars that are invalid in XML 1.0.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
