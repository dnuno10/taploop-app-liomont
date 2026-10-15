// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../card/widgets/qr_code_widget.dart';

/// Shows a collaborator's public-profile QR with a PNG download, same QR
/// (`?via=qr`, so scans are tracked as QR) as the Compartir screen.
Future<void> showMemberQrDialog(
  BuildContext context, {
  required String memberName,
  required String publicUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: ctx.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: _MemberQrContent(memberName: memberName, publicUrl: publicUrl),
      ),
    ),
  );
}

class _MemberQrContent extends StatefulWidget {
  final String memberName;
  final String publicUrl;

  const _MemberQrContent({required this.memberName, required this.publicUrl});

  @override
  State<_MemberQrContent> createState() => _MemberQrContentState();
}

class _MemberQrContentState extends State<_MemberQrContent> {
  bool _downloading = false;

  String get _qrData => '${widget.publicUrl}?via=qr';

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final painter = QrPainter(
        data: _qrData,
        version: QrVersions.auto,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: AppColors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: AppColors.black,
        ),
      );
      final imageData = await painter.toImageData(600);
      if (imageData == null) return;
      final blob = html.Blob([imageData.buffer.asUint8List()], 'image/png');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      final slug = widget.memberName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      html.AnchorElement(href: blobUrl)
        ..download = 'qr_${slug.isEmpty ? 'colaborador' : slug}.png'
        ..click();
      html.Url.revokeObjectUrl(blobUrl);
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo descargar el QR.',
          TapLoopToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.memberName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.publicUrl.replaceFirst('https://', ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          QrCodeWidget(data: _qrData, size: 240),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloading ? null : _download,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(
                _downloading ? 'Generando…' : 'Descargar QR (PNG)',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
