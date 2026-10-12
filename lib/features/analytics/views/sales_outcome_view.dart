import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/lead_model.dart';

class SalesOutcomeView extends StatefulWidget {
  const SalesOutcomeView({super.key});

  @override
  State<SalesOutcomeView> createState() => _SalesOutcomeViewState();
}

class _SalesOutcomeViewState extends State<SalesOutcomeView> {
  final Set<String> _updatingLeads = {};
  List<LeadModel> _allLeads = [];
  bool _loading = true;
  String? _loadedCardId;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeCardId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _loadLeads();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    super.dispose();
  }

  void _onAppStateChanged() {
    final cardId = appState.currentCard?.id;
    _bindRealtime();
    if (cardId == _loadedCardId) return;
    if (!mounted) return;
    setState(() => _loading = true);
    _loadLeads();
  }

  void _bindRealtime() {
    final cardId = appState.currentCard?.id;
    if (cardId == _realtimeCardId) return;
    _metricsRealtime?.close();
    _realtimeCardId = cardId;
    if (cardId == null || cardId.isEmpty) return;
    _metricsRealtime = MetricsRealtimeSubscription.forCard(
      cardId: cardId,
      onRefresh: () {
        if (!mounted) return;
        _loadLeads();
      },
    );
  }

  Future<void> _loadLeads() async {
    final cardId = appState.currentCard?.id;
    if (cardId == null) {
      if (mounted) {
        setState(() {
          _loadedCardId = null;
          _allLeads = [];
          _loading = false;
        });
      }
      return;
    }
    try {
      final data = await LeadRepository.fetchLeadsForCard(cardId);
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _allLeads = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _loading = false;
        });
      }
    }
  }

  List<LeadModel> get _convertedLeads =>
      _allLeads.where((l) => l.isConverted).toList();

  List<LeadModel> get _pendingLeads =>
      _allLeads.where((l) => !l.isConverted).toList();

  double get _conversionRate {
    final total = _allLeads.length;
    if (total == 0) return 0;
    return _convertedLeads.length / total;
  }

  Future<void> _setSaleStatus(LeadModel lead, bool isConverted) async {
    if (_updatingLeads.contains(lead.id)) return;

    setState(() => _updatingLeads.add(lead.id));
    try {
      await LeadRepository.markConverted(lead.id, isConverted);
      if (!mounted) return;
      setState(() {
        _allLeads = _allLeads
            .map(
              (item) => item.id == lead.id
                  ? item.copyWith(isConverted: isConverted)
                  : item,
            )
            .toList();
        _updatingLeads.remove(lead.id);
      });
      TapLoopToast.show(
        context,
        isConverted
            ? 'Venta registrada correctamente.'
            : 'Venta desmarcada correctamente.',
        TapLoopToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingLeads.remove(lead.id));
      TapLoopToast.show(
        context,
        'Error al actualizar la venta: $error',
        TapLoopToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CustomScrollView(
        slivers: [
          SliverFillRemaining(child: Center(child: TapLoopProgressIndicator())),
        ],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HelpTitle(
                  title: 'Ventas',
                  helpText:
                      'Seguimiento de leads convertidos y cierres confirmados.',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_convertedLeads.length} cierres confirmados de ${_allLeads.length} leads totales',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: context.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _MetricBlock(
                        label: 'Total leads',
                        value: '${_allLeads.length}',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 52,
                      color: context.borderColor,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    Expanded(
                      child: _MetricBlock(
                        label: 'Ventas cerradas',
                        value: '${_convertedLeads.length}',
                        accent: true,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 52,
                      color: context.borderColor,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    Expanded(
                      child: _MetricBlock(
                        label: 'Conversión',
                        value: '${(_conversionRate * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Divider(color: context.borderColor, height: 1),
        ),
        if (_convertedLeads.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'CONFIRMADAS',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textMuted,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ConvertedRow(
                lead: _convertedLeads[i],
                isUpdating: _updatingLeads.contains(_convertedLeads[i].id),
                showDivider: i < _convertedLeads.length - 1,
                onToggle: () => _setSaleStatus(_convertedLeads[i], false),
              ),
              childCount: _convertedLeads.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Divider(color: context.borderColor, height: 1),
          ),
        ],
        if (_pendingLeads.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'PENDIENTES',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.textMuted,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PendingRow(
                lead: _pendingLeads[i],
                isUpdating: _updatingLeads.contains(_pendingLeads[i].id),
                showDivider: i < _pendingLeads.length - 1,
                onToggle: () => _setSaleStatus(_pendingLeads[i], true),
              ),
              childCount: _pendingLeads.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

// ─── Metric Block ────────────────────────────────────────────────────────────────

class _MetricBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _MetricBlock({
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: label,
            helpText: 'Indicador de ventas para $label.',
            style: GoogleFonts.dmSans(fontSize: 11, color: context.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: accent ? AppColors.primary : context.textPrimary,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Converted Row ───────────────────────────────────────────────────────────────

class _ConvertedRow extends StatelessWidget {
  final LeadModel lead;
  final bool isUpdating;
  final bool showDivider;
  final VoidCallback onToggle;

  const _ConvertedRow({
    required this.lead,
    required this.isUpdating,
    required this.showDivider,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 10, top: 1),
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.displayName,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    if (lead.company != null)
                      Text(
                        lead.company!,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    Text(
                      'Venta confirmada',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SaleToggleButton(
                isUpdating: isUpdating,
                label: 'Desmarcar',
                icon: Icons.remove_circle_outline_rounded,
                color: const Color(0xFFB45309),
                backgroundColor: context.isDark
                    ? const Color(0xFFB45309).withValues(alpha: 0.14)
                    : const Color(0xFFB45309).withValues(alpha: 0.08),
                onTap: onToggle,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            color: context.borderColor,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
      ],
    );
  }
}

// ─── Pending Row ────────────────────────────────────────────────────────────────

class _PendingRow extends StatelessWidget {
  final LeadModel lead;
  final bool isUpdating;
  final bool showDivider;
  final VoidCallback onToggle;

  const _PendingRow({
    required this.lead,
    required this.isUpdating,
    required this.showDivider,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 10, top: 1),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.displayName,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Última actividad: ${_timeAgo(lead.lastSeen)}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SaleToggleButton(
                isUpdating: isUpdating,
                label: 'Marcar venta',
                icon: Icons.attach_money_rounded,
                color: const Color(0xFF15803D),
                backgroundColor: context.isDark
                    ? const Color(0xFF15803D).withValues(alpha: 0.1)
                    : const Color(0xFF15803D).withValues(alpha: 0.04),
                onTap: onToggle,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            color: context.borderColor,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
      ],
    );
  }
}

class _SaleToggleButton extends StatelessWidget {
  final bool isUpdating;
  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _SaleToggleButton({
    required this.isUpdating,
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isUpdating ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isUpdating ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: 118,
            child: Center(
              child: isUpdating
                  ? TapLoopProgressIndicator(color: color)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
