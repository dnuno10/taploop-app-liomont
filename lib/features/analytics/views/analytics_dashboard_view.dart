import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/liomont_report_pdf.dart';
import '../../../core/utils/liomont_xlsx.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/data/repositories/analytics_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../core/widgets/empty_data_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../analytics/models/analytics_summary_model.dart';
import '../../analytics/models/team_member_model.dart';
import '../../analytics/widgets/visit_event_tile.dart';
import '../../analytics/widgets/link_stats_bar.dart';
import '../../analytics/widgets/team_member_filter_dropdown.dart';
import '../../analytics/widgets/weekly_visits_chart.dart';

Color _analyticsPanelSurfaceColor(BuildContext context) => context.bgCard;

Color _analyticsPanelBorderColor(BuildContext context) =>
    context.borderStrongSoft;

bool _hasAnalyticsRecords(AnalyticsSummaryModel analytics) {
  return analytics.totalInteractions > 0 ||
      analytics.totalQrScans > 0 ||
      analytics.linkStats.isNotEmpty ||
      analytics.recentEvents.isNotEmpty ||
      analytics.visitsByDay.any((value) => value > 0);
}

class AnalyticsDashboardView extends StatefulWidget {
  const AnalyticsDashboardView({super.key});

  @override
  State<AnalyticsDashboardView> createState() => _AnalyticsDashboardViewState();
}

class _AnalyticsDashboardViewState extends State<AnalyticsDashboardView> {
  AnalyticsSummaryModel? _analytics;
  List<TeamMemberModel> _members = [];
  bool _loading = true;
  late DateTimeRange _range;
  int _loadVersion = 0;
  String? _loadedCardId;
  String? _loadedOrgId;
  String? _selectedMemberId;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeMetricsKey;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 6)),
      end: now,
    );
    _bindRealtime();
    _load();
  }

  void _onAppStateChanged() {
    final orgId = appState.currentUser?.orgId;
    final cardId = appState.currentCard?.id;
    _bindRealtime();
    if (orgId == _loadedOrgId && cardId == _loadedCardId) return;
    if (!mounted) return;
    setState(() => _loading = true);
    _load();
  }

  void _bindRealtime() {
    final orgId = appState.currentUser?.orgId;
    final cardId = appState.currentCard?.id;
    final key = orgId != null && orgId.isNotEmpty
        ? 'org:$orgId'
        : 'card:$cardId';
    if (key == _realtimeMetricsKey) return;
    _metricsRealtime?.close();
    _realtimeMetricsKey = key;
    if (orgId != null && orgId.isNotEmpty) {
      _metricsRealtime = MetricsRealtimeSubscription.forOrganization(
        orgId: orgId,
        onRefresh: () {
          if (!mounted) return;
          _load();
        },
      );
    } else if (cardId != null && cardId.isNotEmpty) {
      _metricsRealtime = MetricsRealtimeSubscription.forCard(
        cardId: cardId,
        onRefresh: () {
          if (!mounted) return;
          _load();
        },
      );
    }
  }

  Future<void> _load() async {
    final cardId = appState.currentCard?.id;
    final orgId = appState.currentUser?.orgId;
    final range = _range;
    final loadVersion = ++_loadVersion;
    if (cardId == null && orgId == null) {
      _loadedCardId = null;
      _loadedOrgId = null;
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // Only admins can see (and filter by) other collaborators; everyone
      // else only ever loads their own card's data.
      final isAdmin = appState.currentUser?.isAdmin == true;
      final members = orgId == null || !isAdmin
          ? <TeamMemberModel>[]
          : await AdminRepository.fetchTeamMembers(orgId);
      final selectedMemberId = _resolveSelectedMemberId(
        members: members,
        currentSelectedId: _selectedMemberId,
      );
      final cardIds = _cardIdsForSelection(
        members: members,
        selectedMemberId: selectedMemberId,
        fallbackCardId: cardId,
      );
      final data = await AnalyticsRepository.fetchSummaryForCards(
        cardIds,
        from: range.start,
        to: range.end,
      );
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _loadedCardId = cardId;
        _loadedOrgId = orgId;
        _members = members;
        _selectedMemberId = selectedMemberId;
        _analytics = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _loadedCardId = cardId;
        _loadedOrgId = orgId;
        _analytics = null;
        _loading = false;
      });
    }
  }

  String? _resolveSelectedMemberId({
    required List<TeamMemberModel> members,
    required String? currentSelectedId,
  }) {
    if (currentSelectedId == null || members.isEmpty) return null;
    return members.any((member) => member.id == currentSelectedId)
        ? currentSelectedId
        : null;
  }

  List<String> _cardIdsForSelection({
    required List<TeamMemberModel> members,
    required String? selectedMemberId,
    required String? fallbackCardId,
  }) {
    final selectedMembers = selectedMemberId == null
        ? members
        : members.where((member) => member.id == selectedMemberId).toList();
    final cardIds = selectedMembers
        .expand((member) => member.cardIds)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    if (cardIds.isNotEmpty) return cardIds;
    return fallbackCardId == null ? const [] : [fallbackCardId];
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _analytics = null;
      _loading = true;
    });
    _load();
  }

  /// Who the exported report covers: the selected collaborator, the whole
  /// team (admin, no filter) or the user's own card.
  String _reportScopeLabel() {
    final selectedId = _selectedMemberId;
    if (selectedId != null) {
      final member = _members.cast<TeamMemberModel?>().firstWhere(
        (m) => m?.id == selectedId,
        orElse: () => null,
      );
      if (member != null) return 'Colaborador: ${member.name}';
    }
    if (_members.isNotEmpty) return 'Todo el equipo';
    final ownName = appState.currentCard?.name.trim().isNotEmpty == true
        ? appState.currentCard!.name.trim()
        : appState.currentUser?.name.trim() ?? '';
    return ownName.isEmpty ? 'Mi tarjeta' : ownName;
  }

  String get _reportRangeLabel =>
      'Periodo: ${formatReportDate(_range.start)} - ${formatReportDate(_range.end)}';

  /// Report tables shared by the PDF and Excel downloads.
  List<XlsxSection> _reportSections(AnalyticsSummaryModel analytics) {
    return [
      XlsxSection(
        title: 'Indicadores',
        headers: const ['Indicador', 'Valor'],
        rows: [
          ['Visitas', analytics.totalVisits],
          ['Taps NFC', analytics.totalTaps],
          ['Escaneos QR', analytics.totalQrScans],
          ['Clicks', analytics.totalClicks],
          ['Interacciones totales', analytics.totalInteractions],
          ['Visitas en el periodo', analytics.visitsThisWeek],
          ['Visitas periodo anterior', analytics.visitsLastWeek],
          [
            'Crecimiento de interacciones',
            '${analytics.interactionsGrowthPercent.toStringAsFixed(1)}%',
          ],
        ],
      ),
      XlsxSection(
        title: 'Visitas por día',
        headers: const ['Fecha', 'Visitas'],
        rows: [
          for (var i = 0; i < analytics.visitsByDay.length; i++)
            [
              formatReportDate(
                _range.end.subtract(
                  Duration(days: analytics.visitsByDay.length - 1 - i),
                ),
              ),
              analytics.visitsByDay[i],
            ],
        ],
      ),
      if (analytics.linkStats.isNotEmpty)
        XlsxSection(
          title: 'Enlaces más usados',
          headers: const ['Enlace', 'Plataforma', 'Clicks', '% del total'],
          rows: [
            for (final link in analytics.linkStats)
              [
                link.label,
                link.platform,
                link.clicks,
                '${(link.percentage * 100).toStringAsFixed(1)}%',
              ],
          ],
        ),
    ];
  }

  String get _reportFileName {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'analiticas_liomont_$stamp';
  }

  Future<void> _exportExcel() async {
    final analytics = _analytics;
    if (analytics == null) return;

    try {
      final bytes = await buildLiomontXlsx(
        sheetName: 'Analíticas',
        title: 'Reporte de analíticas · ${_reportScopeLabel()}',
        subtitle:
            '$_reportRangeLabel · Generado el ${formatReportDate(DateTime.now())}',
        sections: _reportSections(analytics),
        columnWidths: const [34, 22, 14, 14],
      );
      await FileSaver.instance.saveFile(
        name: _reportFileName,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      if (!mounted) return;
      TapLoopToast.show(
        context,
        'Excel exportado correctamente.',
        TapLoopToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'Error al exportar Excel. Intenta nuevamente.',
        TapLoopToastType.error,
      );
    }
  }

  Future<void> _exportPdf() async {
    final analytics = _analytics;
    if (analytics == null) return;

    try {
      final logo = await loadLiomontLogo();
      final generatedAt = DateTime.now();
      final sections = _reportSections(analytics);
      final pdf = pw.Document(
        title: 'Reporte de analíticas',
        author: 'Liomont',
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
          header: (context) => liomontReportHeader(
            logo: logo,
            title: 'Reporte de analíticas',
            subtitle: '${_reportScopeLabel()} · $_reportRangeLabel',
          ),
          footer: (context) => liomontReportFooter(context, generatedAt),
          build: (context) => [
            pw.Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                liomontSummaryChip('Visitas', '${analytics.totalVisits}'),
                liomontSummaryChip('Taps NFC', '${analytics.totalTaps}'),
                liomontSummaryChip('Escaneos QR', '${analytics.totalQrScans}'),
                liomontSummaryChip('Clicks', '${analytics.totalClicks}'),
                liomontSummaryChip(
                  'Interacciones',
                  '${analytics.totalInteractions}',
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            for (final section in sections) ...[
              liomontSectionTitle(section.title),
              liomontTable(
                fontSize: 9,
                headers: section.headers,
                data: [
                  for (final row in section.rows)
                    [for (final value in row) '${value ?? ''}'],
                ],
              ),
              pw.SizedBox(height: 12),
            ],
          ],
        ),
      );

      final bytes = await pdf.save();
      await FileSaver.instance.saveFile(
        name: _reportFileName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (!mounted) return;
      TapLoopToast.show(
        context,
        'PDF exportado correctamente.',
        TapLoopToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'Error al exportar PDF. Intenta nuevamente.',
        TapLoopToastType.error,
      );
    }
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    final isDesktop = Responsive.isDesktop(context);
    final isMobile = Responsive.isMobile(context);
    final hasLinkedCard =
        appState.currentCard != null ||
        _members.any((member) => member.cardIds.isNotEmpty);
    final titleBlock = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: isDesktop ? 320 : 240,
        maxWidth: isDesktop ? 560 : double.infinity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: 'Analíticas',
            helpText:
                'Panel general para medir visitas, clics, leads y rendimiento del equipo.',
            style: GoogleFonts.outfit(
              fontSize: isDesktop ? 42 : 30,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Mide el rendimiento general de tu tarjeta digital y tu equipo.',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
    final actionsBlock = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        if (appState.currentUser?.isAdmin == true)
          TeamMemberFilterDropdown(
            members: _members,
            selectedMemberId: _selectedMemberId,
            onChanged: (memberId) {
              setState(() {
                _selectedMemberId = memberId;
                _analytics = null;
                _loading = true;
              });
              _load();
            },
          ),
        _PeriodChip(label: 'Todo', onTap: _pickRange),
        _ExportActionButton(
          label: 'Excel',
          icon: Icons.table_chart_outlined,
          onTap: _loading || _analytics == null ? null : _exportExcel,
        ),
        _ExportActionButton(
          label: 'PDF',
          icon: Icons.picture_as_pdf_outlined,
          onTap: _loading || _analytics == null ? null : _exportPdf,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: titleBlock),
                        if (hasLinkedCard) actionsBlock,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleBlock,
                        if (hasLinkedCard) ...[
                          const SizedBox(height: 14),
                          actionsBlock,
                        ],
                      ],
                    ),
            ),
            Expanded(
              child: Container(
                color: context.bgPage,
                child: hasLinkedCard
                    ? SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 36 : 18,
                          isDesktop ? 28 : 18,
                          isDesktop ? 36 : 18,
                          36,
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 300,
                                child: Center(
                                  child: TapLoopProgressIndicator(),
                                ),
                              )
                            : analytics == null ||
                                  !_hasAnalyticsRecords(analytics)
                            ? const SizedBox(
                                height: 300,
                                child: EmptyDataState(
                                  centered: true,
                                  hint:
                                      'No hay registros en el rango seleccionado.',
                                ),
                              )
                            : isDesktop
                            ? _DesktopLayout(
                                analytics: analytics,
                                rangeEnd: _range.end,
                              )
                            : _MobileLayout(
                                analytics: analytics,
                                isMobile: isMobile,
                                rangeEnd: _range.end,
                              ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                        child: CardInitialSetupState(
                          onLinked: () => setState(() {}),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Layouts ─────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  final bool isMobile;
  final DateTime rangeEnd;
  const _MobileLayout({
    required this.analytics,
    required this.isMobile,
    required this.rangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final px = isMobile ? 20.0 : 40.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: px, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TotalBlock(analytics: analytics),
          const SizedBox(height: 32),
          _MetricRow(analytics: analytics),
          const SizedBox(height: 40),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 36),
          _ChartBlock(analytics: analytics, rangeEnd: rangeEnd),
          const SizedBox(height: 40),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 36),
          _LinksBlock(analytics: analytics),
          const SizedBox(height: 40),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 36),
          _ActivityBlock(analytics: analytics),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  final DateTime rangeEnd;
  const _DesktopLayout({required this.analytics, required this.rangeEnd});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TotalBlock(analytics: analytics),
              const SizedBox(height: 22),
              _MetricRow(analytics: analytics),
              const SizedBox(height: 22),
              _ChartBlock(analytics: analytics, rangeEnd: rangeEnd),
              const SizedBox(height: 22),
              _LinksBlock(analytics: analytics),
            ],
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(width: 420, child: _ActivityBlock(analytics: analytics)),
      ],
    );
  }
}

String _formatTrendValue(double value) {
  final prefix = value >= 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}%';
}

// ─── Total Block ─────────────────────────────────────────────────────────────

class _TotalBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _TotalBlock({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final total = analytics.totalInteractions;
    final trendColor = analytics.interactionsGrowing
        ? AppColors.success
        : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      decoration: BoxDecoration(
        color: _analyticsPanelSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _analyticsPanelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Interacciones totales',
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 36),
          Text(
            '$total',
            style: GoogleFonts.outfit(
              fontSize: 58,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      analytics.interactionsGrowing
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 11,
                      color: trendColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatTrendValue(analytics.interactionsGrowthPercent),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'vs período anterior',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Metric Row ───────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _MetricRow({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final items = [
      _MetricItem(
        label: 'Visitas',
        value: '${analytics.totalVisits}',
        icon: Icons.visibility_outlined,
        trend: _formatTrendValue(analytics.visitsGrowthPercent),
        positive: analytics.visitsGrowthPercent >= 0,
      ),
      _MetricItem(
        label: 'Taps NFC',
        value: '${analytics.totalTaps}',
        icon: Icons.nfc_outlined,
        trend: _formatTrendValue(analytics.tapsGrowthPercent),
        positive: analytics.tapsGrowthPercent >= 0,
      ),
      _MetricItem(
        label: 'Clicks',
        value: '${analytics.totalClicks}',
        icon: Icons.ads_click_outlined,
        trend: _formatTrendValue(analytics.clicksGrowthPercent),
        positive: analytics.clicksGrowthPercent >= 0,
      ),
    ];

    if (isMobile) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final gap = 10.0;
          final colWidth = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              SizedBox(
                width: colWidth,
                child: _MetricCompactCard(item: items[0]),
              ),
              SizedBox(
                width: colWidth,
                child: _MetricCompactCard(item: items[1]),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: _MetricCompactCard(item: items[2]),
              ),
            ],
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        color: _analyticsPanelSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _analyticsPanelBorderColor(context)),
      ),
      child: Row(
        children: items
            .asMap()
            .entries
            .map(
              (e) => Expanded(
                child: Row(
                  children: [
                    Expanded(child: _MetricCell(item: e.value)),
                    if (e.key < items.length - 1)
                      Container(
                        width: 1,
                        height: 52,
                        color: context.borderStrongSoft,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MetricItem {
  final String label, value, trend;
  final IconData icon;
  final bool positive;
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.trend,
    required this.positive,
  });
}

class _MetricCell extends StatelessWidget {
  final _MetricItem item;
  const _MetricCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(item.icon, size: 13, color: context.textMuted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                item.label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: context.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          item.value,
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.trend,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: item.positive ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }
}

class _MetricCompactCard extends StatelessWidget {
  final _MetricItem item;
  const _MetricCompactCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _analyticsPanelSurfaceColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _analyticsPanelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, size: 13, color: context.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: HelpTitle(
                  title: item.label,
                  helpText: 'Métrica de analítica: ${item.label}.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.trend,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: item.positive ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chart Block ─────────────────────────────────────────────────────────────

class _ChartBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  final DateTime rangeEnd;
  const _ChartBlock({required this.analytics, required this.rangeEnd});

  @override
  Widget build(BuildContext context) {
    final trendColor = analytics.visitsGrowthPercent >= 0
        ? AppColors.success
        : AppColors.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: _analyticsPanelSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _analyticsPanelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              HelpTitle(
                title: 'Visitas por día',
                helpText:
                    'Gráfica con el comportamiento diario de visitas en el rango seleccionado.',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${analytics.totalVisits} en el rango',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      analytics.visitsGrowthPercent >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 13,
                      color: trendColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTrendValue(analytics.visitsGrowthPercent),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 320,
            child: WeeklyVisitsChart(
              visitsByDay: analytics.visitsByDay,
              referenceDate: rangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Links Block ─────────────────────────────────────────────────────────────

class _LinksBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _LinksBlock({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: _analyticsPanelSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _analyticsPanelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HelpTitle(
                title: 'Links más clickeados',
                helpText:
                    'Ranking de enlaces con más clics dentro del periodo seleccionado.',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${analytics.totalClicks} clicks totales',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(analytics.linkStats.length, (i) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: i == 0 ? AppColors.primary : context.textMuted,
                        ),
                      ),
                    ),
                    Expanded(child: LinkStatsBar(stat: analytics.linkStats[i])),
                  ],
                ),
                if (i < analytics.linkStats.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: context.borderStrongSoft, height: 1),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─── Activity Block ───────────────────────────────────────────────────────────

class _ActivityBlock extends StatelessWidget {
  final AnalyticsSummaryModel analytics;
  const _ActivityBlock({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      decoration: BoxDecoration(
        color: _analyticsPanelSurfaceColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _analyticsPanelBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: 'Actividad reciente',
            helpText: 'Últimas interacciones registradas con tu tarjeta.',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Últimas interacciones con tu tarjeta',
            style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
          ),
          const SizedBox(height: 20),
          ...List.generate(
            analytics.recentEvents.length > 10
                ? 10
                : analytics.recentEvents.length,
            (i) {
              return Column(
                children: [
                  VisitEventTile(event: analytics.recentEvents[i]),
                  if (i < analytics.recentEvents.length - 1)
                    Divider(color: context.borderStrongSoft, height: 1),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Period Chip ──────────────────────────────────────────────────────────────

class _PeriodChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PeriodChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _analyticsPanelSurfaceColor(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _analyticsPanelBorderColor(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 15,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _ExportActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
