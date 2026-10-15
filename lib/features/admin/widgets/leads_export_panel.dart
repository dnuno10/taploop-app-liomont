import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/csv_export.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../analytics/models/team_member_model.dart';
import '../../analytics/widgets/team_member_filter_dropdown.dart';
import '../utils/leads_directory_pdf.dart';

/// Admin-only download of the leads directory (PDF with the Liomont logo),
/// for one collaborator or for every collaborator (Liomont + Promofarma for
/// admins of those orgs). Renders nothing for non-admins.
class LeadsExportPanel extends StatefulWidget {
  final String orgId;

  const LeadsExportPanel({super.key, required this.orgId});

  @override
  State<LeadsExportPanel> createState() => _LeadsExportPanelState();
}

class _LeadsExportPanelState extends State<LeadsExportPanel> {
  List<TeamMemberModel> _members = const [];
  String? _selectedMemberId;
  _ExportFormat? _exporting;

  bool get _isAdmin => appState.currentUser?.isAdmin == true;

  bool get _linked => AdminRepository.usesLinkedDirectory(widget.orgId);

  String get _allLabel =>
      _linked ? 'Todos (Liomont y Promofarma)' : 'Todos los colaboradores';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void didUpdateWidget(covariant LeadsExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orgId != widget.orgId) _loadMembers();
  }

  /// Own team plus, for Liomont/Promofarma admins, the linked org's members
  /// so a single collaborator of either org can be exported.
  Future<void> _loadMembers() async {
    if (!_isAdmin) return;
    try {
      final results = await Future.wait<Object>([
        AdminRepository.fetchTeamMembers(widget.orgId),
        _linked
            ? AdminRepository.fetchLinkedDirectory()
            : Future.value(const <LinkedDirectoryEntry>[]),
      ]);
      final own = results[0] as List<TeamMemberModel>;
      final linked = results[1] as List<LinkedDirectoryEntry>;
      final byId = <String, TeamMemberModel>{
        for (final m in own) m.id: m,
        for (final e in linked)
          if (!own.any((m) => m.id == e.member.id)) e.member.id: e.member,
      };
      if (!mounted) return;
      setState(() => _members = byId.values.toList());
    } catch (_) {
      // The picker still offers "Todos" without the member list.
    }
  }

  Future<void> _export(_ExportFormat format) async {
    if (_exporting != null || !_isAdmin) return;
    setState(() => _exporting = format);
    try {
      final selectedId = _selectedMemberId;
      final selected = selectedId == null
          ? null
          : _members.cast<TeamMemberModel?>().firstWhere(
              (m) => m?.id == selectedId,
              orElse: () => null,
            );
      final leads = await AdminRepository.fetchLeadsDirectory(
        widget.orgId,
        userId: selectedId,
      );
      final slug = selected == null
          ? 'todos'
          : selected.name
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
                .replaceAll(RegExp(r'^-+|-+$'), '');
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final baseName = 'leads_${slug.isEmpty ? 'colaborador' : slug}';
      if (format == _ExportFormat.csv) {
        await saveCsvFile(baseName, [
          [...leadsDirectoryHeaders, ...leadsDirectoryCsvExtraHeaders],
          for (final lead in leads)
            [...leadsDirectoryRow(lead), ...leadsDirectoryCsvExtras(lead)],
        ]);
      } else {
        final bytes = await buildLeadsDirectoryPdf(
          leads: leads,
          scopeLabel: selected == null
              ? _allLabel
              : 'Colaborador: ${selected.name}',
        );
        await FileSaver.instance.saveFile(
          name: '${baseName}_$stamp',
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      }
      if (!mounted) return;
      TapLoopToast.show(
        context,
        leads.isEmpty
            ? 'Se descargó el directorio (sin leads registrados).'
            : 'Directorio de leads descargado (${leads.length}).',
        TapLoopToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo generar el directorio de leads. Intenta de nuevo.',
        TapLoopToastType.error,
      );
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) return const SizedBox.shrink();

    final controls = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TeamMemberFilterDropdown(
          members: _members,
          selectedMemberId: _selectedMemberId,
          allLabel: _allLabel,
          onChanged: (id) => setState(() => _selectedMemberId = id),
        ),
        _ExportButton(
          label: 'Descargar PDF',
          icon: Icons.picture_as_pdf_outlined,
          filled: true,
          busy: _exporting == _ExportFormat.pdf,
          onPressed: _exporting == null
              ? () => _export(_ExportFormat.pdf)
              : null,
        ),
        _ExportButton(
          label: 'Descargar CSV',
          icon: Icons.table_view_outlined,
          filled: false,
          busy: _exporting == _ExportFormat.csv,
          onPressed: _exporting == null
              ? () => _export(_ExportFormat.csv)
              : null,
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Directorio de leads',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _linked
                    ? 'Descarga en PDF los leads de un colaborador o de todos los colaboradores de Liomont y Promofarma.'
                    : 'Descarga en PDF los leads de un colaborador o de todo el equipo.',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  color: context.textSecondary,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 18), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              controls,
            ],
          );
        },
      ),
    );
  }
}

enum _ExportFormat { pdf, csv }

class _ExportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onPressed;

  const _ExportButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final iconWidget = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: TapLoopProgressIndicator(
              color: filled ? Colors.white : AppColors.primary,
            ),
          )
        : Icon(icon, size: 20);
    final text = Text(
      busy ? 'Generando…' : label,
      style: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
    );
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: shape,
        ),
        icon: iconWidget,
        label: text,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.textPrimary,
        side: BorderSide(color: context.borderStrongSoft, width: 1.2),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: shape,
      ),
      icon: iconWidget,
      label: text,
    );
  }
}
