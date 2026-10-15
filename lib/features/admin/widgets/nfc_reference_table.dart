import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/csv_export.dart';
import '../../../core/utils/search_text.dart';
import '../../../core/widgets/empty_data_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/sortable_header_label.dart';
import '../../../core/widgets/taploop_text_field.dart';
import '../../../core/widgets/taploop_toast.dart';

/// Reference table relating each NFC card serial to its collaborator
/// (name, company, email, organization). Shown in Administración and
/// Equipo; loads its own data for [orgId].
class NfcReferenceTable extends StatefulWidget {
  final String orgId;

  const NfcReferenceTable({super.key, required this.orgId});

  @override
  State<NfcReferenceTable> createState() => _NfcReferenceTableState();
}

const _liomontOrgId = '293f05a3-9115-4b72-a4ac-2c4d3a8af83e';
const _promofarmaOrgId = '4a7357d3-5222-4555-aaa9-f5cbe7b1d81d';

enum _OrgFilter { both, liomont, promofarma }

enum _NfcSort { serial, name, company, email, organization }

/// Natural order for serials: digit runs compare numerically, so "2" comes
/// before "10" and "LIO-9" before "LIO-10".
int _compareSerials(String a, String b) {
  final chunk = RegExp(r'\d+|\D+');
  final aParts = chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final bParts = chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < aParts.length && i < bParts.length; i++) {
    final x = aParts[i];
    final y = bParts[i];
    final xNum = BigInt.tryParse(x);
    final yNum = BigInt.tryParse(y);
    final result = xNum != null && yNum != null
        ? xNum.compareTo(yNum)
        : x.compareTo(y);
    if (result != 0) return result;
  }
  return aParts.length.compareTo(bParts.length);
}

class _NfcReferenceTableState extends State<NfcReferenceTable> {
  static const _pageSize = 25;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<({NfcReferenceRow row, String key})> _rows = const [];
  bool _loading = true;
  bool _failed = false;
  String _query = '';
  _OrgFilter _orgFilter = _OrgFilter.both;
  _NfcSort _sort = _NfcSort.serial;
  bool _ascending = true;
  bool _exporting = false;
  int _visibleCount = _pageSize;

  void _toggleSort(_NfcSort sort) {
    setState(() {
      if (_sort == sort) {
        _ascending = !_ascending;
      } else {
        _sort = sort;
        _ascending = true;
      }
      _visibleCount = _pageSize;
    });
  }

  List<NfcReferenceRow> _sorted(List<NfcReferenceRow> rows) {
    String text(NfcReferenceRow r) => switch (_sort) {
      _NfcSort.serial => r.serial,
      _NfcSort.name => r.userName,
      _NfcSort.company => r.company,
      _NfcSort.email => r.userEmail,
      _NfcSort.organization => r.orgName,
    };
    int compare(NfcReferenceRow a, NfcReferenceRow b) {
      final result = _sort == _NfcSort.serial
          ? _compareSerials(a.serial, b.serial)
          : text(a).toLowerCase().compareTo(text(b).toLowerCase());
      if (result != 0) return _ascending ? result : -result;
      return _compareSerials(a.serial, b.serial);
    }

    return [...rows]..sort(compare);
  }

  Future<void> _exportCsv(List<NfcReferenceRow> rows) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await saveCsvFile('referencia_tarjetas_nfc', [
        ['#', 'Serial NFC', 'Nombre', 'Empresa', 'Correo', 'Organización'],
        for (var i = 0; i < rows.length; i++)
          [
            i + 1,
            rows[i].serial,
            rows[i].userName,
            rows[i].company,
            rows[i].userEmail,
            rows[i].orgName,
          ],
      ]);
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'Referencia NFC exportada (${rows.length} seriales).',
        TapLoopToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo exportar la referencia NFC.',
        TapLoopToastType.error,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// The Liomont/Promofarma buttons only make sense when rows of both orgs
  /// are present.
  bool get _showOrgFilter {
    final orgIds = _rows.map((e) => e.row.orgId).toSet();
    return orgIds.contains(_liomontOrgId) && orgIds.contains(_promofarmaOrgId);
  }

  bool _matchesOrg(NfcReferenceRow row) => switch (_orgFilter) {
    _OrgFilter.both => true,
    _OrgFilter.liomont => row.orgId == _liomontOrgId,
    _OrgFilter.promofarma => row.orgId == _promofarmaOrgId,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NfcReferenceTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orgId != widget.orgId) _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await AdminRepository.fetchNfcReference(widget.orgId)
        ..sort((a, b) => _compareSerials(a.serial, b.serial));
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final row in rows)
            (
              row: row,
              key: normalizeSearchText(
                '${row.serial} ${row.userName} ${row.userEmail} '
                '${row.company} ${row.orgName}',
              ),
            ),
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _query = normalizeSearchText(value);
        _visibleCount = _pageSize;
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _visibleCount = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _sorted([
      for (final entry in _rows)
        if ((_query.isEmpty || entry.key.contains(_query)) &&
            _matchesOrg(entry.row))
          entry.row,
    ]);
    final visible = filtered.take(_visibleCount).toList();
    final remaining = filtered.length - visible.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(34, 34, 34, 34),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referencia de tarjetas NFC',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Relación entre el serial de cada tarjeta NFC y su colaborador.',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_loading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.nfc_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${filtered.length}',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Seriales',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_loading && !_failed) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exporting || filtered.isEmpty
                      ? null
                      : () => _exportCsv(filtered),
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: TapLoopProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.table_view_outlined, size: 19),
                  label: Text(_exporting ? 'Exportando…' : 'Exportar CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(
                      color: context.borderStrongSoft,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    minimumSize: const Size(0, 50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    textStyle: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TapLoopTextField(
              label: 'Buscar',
              hint: 'Serial, nombre, empresa, correo u organización',
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          if (!_loading && _showOrgFilter) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (filter, label) in const [
                  (_OrgFilter.both, 'Ambas'),
                  (_OrgFilter.liomont, 'Liomont'),
                  (_OrgFilter.promofarma, 'Promofarma'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _orgFilter == filter,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _orgFilter = filter;
                      _visibleCount = _pageSize;
                    }),
                    labelStyle: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _orgFilter == filter
                          ? Colors.white
                          : context.textPrimary,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: context.bgCard,
                    side: BorderSide(
                      color: _orgFilter == filter
                          ? AppColors.primary
                          : context.borderStrongSoft,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Divider(color: context.borderStrongSoft, height: 1),
          const SizedBox(height: 18),
          if (_loading)
            const SizedBox(
              height: 160,
              child: Center(child: TapLoopProgressIndicator()),
            )
          else if (_failed)
            Center(
              child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('No se pudo cargar. Reintentar'),
              ),
            )
          else if (filtered.isEmpty)
            EmptyDataState(
              hint: _query.isEmpty
                  ? 'Aún no hay tarjetas NFC vinculadas.'
                  : 'No hay seriales que coincidan con los filtros.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 1184),
                child: Column(
                  children: [
                    _NfcReferenceHeader(
                      sort: _sort,
                      ascending: _ascending,
                      onSort: _toggleSort,
                    ),
                    Divider(color: context.borderStrongSoft, height: 28),
                    for (var i = 0; i < visible.length; i++)
                      _NfcReferenceRowView(position: i + 1, row: visible[i]),
                  ],
                ),
              ),
            ),
          if (remaining > 0) ...[
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _visibleCount += _pageSize),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(
                  'Mostrar más ($remaining restantes)',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _positionWidth = 64.0;
const _serialWidth = 220.0;
const _nameWidth = 260.0;
const _companyWidth = 200.0;
const _emailWidth = 280.0;
const _orgWidth = 160.0;

class _NfcReferenceHeader extends StatelessWidget {
  final _NfcSort sort;
  final bool ascending;
  final ValueChanged<_NfcSort> onSort;

  const _NfcReferenceHeader({
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.dmSans(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: context.textSecondary,
    );
    Widget sortable(String title, _NfcSort value) => Align(
      alignment: Alignment.centerLeft,
      child: SortableHeaderLabel(
        title: title,
        active: sort == value,
        ascending: ascending,
        onTap: () => onSort(value),
        style: style,
      ),
    );
    return Row(
      children: [
        SizedBox(
          width: _positionWidth,
          child: HelpTitle(title: '#', style: style),
        ),
        SizedBox(
          width: _serialWidth,
          child: sortable('Serial NFC', _NfcSort.serial),
        ),
        SizedBox(width: _nameWidth, child: sortable('Nombre', _NfcSort.name)),
        SizedBox(
          width: _companyWidth,
          child: sortable('Empresa', _NfcSort.company),
        ),
        SizedBox(width: _emailWidth, child: sortable('Correo', _NfcSort.email)),
        SizedBox(
          width: _orgWidth,
          child: sortable('Organización', _NfcSort.organization),
        ),
      ],
    );
  }
}

class _NfcReferenceRowView extends StatelessWidget {
  final int position;
  final NfcReferenceRow row;

  const _NfcReferenceRowView({required this.position, required this.row});

  @override
  Widget build(BuildContext context) {
    final strong = GoogleFonts.dmSans(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: context.textPrimary,
    );
    final regular = GoogleFonts.dmSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: context.textSecondary,
    );
    Widget cell(double width, String text, TextStyle style) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Text(
          text.trim().isEmpty ? '—' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderStrongSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _positionWidth,
            child: Text(
              '$position',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: _serialWidth,
            child: Row(
              children: [
                const Icon(
                  Icons.nfc_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    row.serial,
                    maxLines: 1,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          cell(_nameWidth, row.userName, strong),
          cell(_companyWidth, row.company, regular),
          cell(_emailWidth, row.userEmail, regular),
          cell(_orgWidth, row.orgName, regular),
        ],
      ),
    );
  }
}
