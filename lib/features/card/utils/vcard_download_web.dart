// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> downloadVCardFile(String fileName, String contents) async {
  final bytes = utf8.encode(contents);
  final blob = html.Blob([bytes], 'text/vcard;charset=utf-8');
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: blobUrl)
    ..download = fileName
    ..style.display = 'none';

  try {
    html.document.body?.append(anchor);
    anchor.click();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return true;
  } finally {
    anchor.remove();
    html.Url.revokeObjectUrl(blobUrl);
  }
}

/// Downloads the profile photo shown on the public card so it can be embedded
/// in the vCard. Returns null on any failure or after [timeout], so saving
/// the contact never hangs on the photo.
Future<Uint8List?> fetchVCardPhotoBytes(
  String url, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final request = await html.HttpRequest.request(
      url,
      responseType: 'arraybuffer',
    ).timeout(timeout);
    final status = request.status ?? 0;
    if (status < 200 || status >= 300) return null;
    final response = request.response;
    if (response is ByteBuffer) return response.asUint8List();
    return null;
  } catch (_) {
    return null;
  }
}
