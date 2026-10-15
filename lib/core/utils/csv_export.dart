import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';

/// Saves [rows] as a CSV download that Excel opens with accents intact
/// (UTF-8 with BOM). [baseName] gets a yyyymmdd stamp appended.
Future<void> saveCsvFile(String baseName, List<List<Object?>> rows) async {
  final csv = const ListToCsvConverter().convert(rows);
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  final now = DateTime.now();
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  await FileSaver.instance.saveFile(
    name: '${baseName}_$stamp',
    bytes: bytes,
    fileExtension: 'csv',
    mimeType: MimeType.csv,
  );
}
