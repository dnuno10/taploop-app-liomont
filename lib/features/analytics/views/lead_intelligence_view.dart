import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/data/repositories/lead_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/lead_model.dart';
import '../models/team_member_model.dart';
import '../widgets/team_member_filter_dropdown.dart';

// ─── Simulated timeline events ────────────────────────────────────────────────

class _TimelineEvent {
  final DateTime timestamp;
  final String time;
  final String date;
  final String label;
  final IconData icon;
  final bool isFormEvent;
  const _TimelineEvent({
    required this.timestamp,
    required this.time,
    required this.date,
    required this.label,
    required this.icon,
    this.isFormEvent = false,
  });
}

String _formTitle(String? formType) {
  switch (formType) {
    case 'cotizacion':
      return 'Solicitar cotización';
    case 'demo':
      return 'Agendar demo';
    case 'catalogo':
      return 'Descargar catálogo';
    case 'contacto':
      return 'Formulario de contacto';
    case 'propuesta':
      return 'Solicitar propuesta';
    default:
      return 'Formulario';
  }
}

String _verboseEventLabel(LeadActionEvent action, LeadModel lead) {
  if (action.action == LeadAction.filledForm) {
    return 'Hizo el llenado de ${_formTitle(lead.formType)}';
  }

  if (action.customLabel != null && action.customLabel!.trim().isNotEmpty) {
    final raw = action.customLabel!.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('email') || lower.contains('correo')) {
      return 'Hizo click en Email';
    }
    if (lower.startsWith('hizo ') ||
        lower.startsWith('visit') ||
        lower.startsWith('descarg')) {
      return raw;
    }
    return 'Hizo click en $raw';
  }

  switch (action.action) {
    case LeadAction.visitedProfile:
      return 'Visitó el perfil digital';
    case LeadAction.clickedLinkedIn:
      return 'Hizo click en LinkedIn';
    case LeadAction.clickedWebsite:
      return 'Hizo click en Sitio web';
    case LeadAction.clickedWhatsApp:
      return 'Hizo click en WhatsApp';
    case LeadAction.downloadedContact:
      return 'Descargó el contacto';
    case LeadAction.filledForm:
      return 'Hizo el llenado de ${_formTitle(lead.formType)}';
  }
}

List<_TimelineEvent> _buildTimeline(LeadModel lead) {
  final fromActions = lead.actions.map((a) {
    IconData icon;
    final label = a.label.toLowerCase();
    if (label.contains('nfc')) {
      icon = Icons.nfc_outlined;
    } else if (label.contains('perfil')) {
      icon = Icons.person_outline_rounded;
    } else {
      switch (a.action) {
        case LeadAction.clickedLinkedIn:
          icon = Icons.work_outline_rounded;
          break;
        case LeadAction.clickedWhatsApp:
          icon = Icons.chat_bubble_outline_rounded;
          break;
        case LeadAction.clickedWebsite:
          icon = Icons.language_rounded;
          break;
        case LeadAction.downloadedContact:
          icon = Icons.download_outlined;
          break;
        case LeadAction.filledForm:
          icon = Icons.assignment_outlined;
          break;
        default:
          icon = Icons.touch_app_outlined;
      }
    }
    return _TimelineEvent(
      timestamp: a.timestamp,
      time: _fmt(a.timestamp),
      date: _fmtDay(a.timestamp),
      label: _verboseEventLabel(a, lead),
      icon: icon,
      isFormEvent: a.action == LeadAction.filledForm,
    );
  }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final deduped = <_TimelineEvent>[];
  const dedupWindow = Duration(seconds: 8);
  for (final ev in fromActions) {
    final hasNearbySameLabel = deduped.any((prev) {
      if (prev.label.trim().toLowerCase() != ev.label.trim().toLowerCase()) {
        return false;
      }
      final diff = ev.timestamp.difference(prev.timestamp).inSeconds.abs();
      return diff <= dedupWindow.inSeconds;
    });
    if (!hasNearbySameLabel) {
      deduped.add(ev);
    }
  }

  if (deduped.isNotEmpty) return deduped;

  final base = lead.firstSeen;
  return [
    _TimelineEvent(
      timestamp: base,
      time: _fmt(base),
      date: _fmtDay(base),
      label: 'Escaneó NFC',
      icon: Icons.nfc_outlined,
    ),
    _TimelineEvent(
      timestamp: base.add(const Duration(minutes: 1)),
      time: _fmt(base.add(const Duration(minutes: 1))),
      date: _fmtDay(base.add(const Duration(minutes: 1))),
      label: 'Abrió perfil',
      icon: Icons.person_outline_rounded,
    ),
  ];
}

String _fmt(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _fmtDay(DateTime dt) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

class LeadIntelligenceView extends StatefulWidget {
  const LeadIntelligenceView({super.key});

  @override
  State<LeadIntelligenceView> createState() => _LeadIntelligenceViewState();
}

class _LeadIntelligenceViewState extends State<LeadIntelligenceView> {
  List<LeadModel> _allLeads = [];
  List<TeamMemberModel> _members = [];
  bool _loading = true;
  String? _loadedCardId;
  String? _loadedOrgId;
  String? _selectedMemberId;
  String? _selectedLeadId;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeOrgId;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _load();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    _searchCtrl.dispose();
    super.dispose();
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
    if (orgId == _realtimeOrgId) return;
    _metricsRealtime?.close();
    _realtimeOrgId = orgId;
    if (orgId == null || orgId.isEmpty) return;
    _metricsRealtime = MetricsRealtimeSubscription.forOrganization(
      orgId: orgId,
      onRefresh: () {
        if (!mounted) return;
        _load();
      },
    );
  }

  Future<void> _load() async {
    final cardId = appState.currentCard?.id;
    final orgId = appState.currentUser?.orgId;
    if (cardId == null && orgId == null) {
      _loadedCardId = null;
      _loadedOrgId = null;
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final members = orgId == null
          ? <TeamMemberModel>[]
          : await AdminRepository.fetchTeamMembers(orgId);
      final selectedMemberId = _resolveSelectedMemberId(
        members: members,
        currentSelectedId: _selectedMemberId,
      );
      final selectedCardIds = _cardIdsForSelection(
        members: members,
        selectedMemberId: selectedMemberId,
        fallbackCardId: cardId,
      );
      final leadsByCard = await LeadRepository.fetchLeadsForCards(
        selectedCardIds,
      );
      final data = leadsByCard.values.expand((leads) => leads).toList()
        ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      final selectedLeadStillVisible = data.any(
        (lead) => lead.id == _selectedLeadId,
      );
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _loadedOrgId = orgId;
          _members = members;
          _selectedMemberId = selectedMemberId;
          _allLeads = data;
          _selectedLeadId = selectedLeadStillVisible
              ? _selectedLeadId
              : data.isNotEmpty
              ? data.first.id
              : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadedCardId = cardId;
          _loadedOrgId = orgId;
          _loading = false;
        });
      }
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

  List<LeadModel> get _leads {
    var list = [..._allLeads]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    if (_statusFilter == 'new') {
      list = list.where((lead) => !lead.isConverted).toList();
    } else if (_statusFilter == 'contacted') {
      list = list.where((lead) => lead.isConverted).toList();
    }
    if (_search.trim().isEmpty) return list;
    final q = _search.trim().toLowerCase();
    return list.where((lead) {
      final name = lead.displayName.toLowerCase();
      final company = (lead.company ?? '').toLowerCase();
      return name.contains(q) || company.contains(q);
    }).toList();
  }

  Future<void> _markAsConverted(LeadModel lead) async {
    try {
      await LeadRepository.markConverted(lead.id, true);
      if (mounted) {
        TapLoopToast.show(
          context,
          'Lead marcado como contactado.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      final idx = _allLeads.indexWhere((l) => l.id == lead.id);
      if (idx != -1) _allLeads[idx].isConverted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final leads = _leads;
    final convertedCount = _allLeads.where((l) => l.isConverted).length;
    final newCount = _allLeads.length - convertedCount;
    final isDesktop = MediaQuery.of(context).size.width >= 980;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 36 : 20,
          isDesktop ? 34 : 24,
          isDesktop ? 36 : 20,
          44,
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
                      HelpTitle(
                        title: 'Bandeja de leads',
                        helpText:
                            'Administra, filtra y prioriza los leads capturados por tus tarjetas.',
                        style: GoogleFonts.outfit(
                          fontSize: isDesktop ? 42 : 30,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Administra y filtra leads capturados por tu tarjeta.',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDesktop)
                  TeamMemberFilterDropdown(
                    members: _members,
                    selectedMemberId: _selectedMemberId,
                    onChanged: (memberId) {
                      setState(() {
                        _selectedMemberId = memberId;
                        _loading = true;
                      });
                      _load();
                    },
                  ),
              ],
            ),
            if (!isDesktop) ...[
              const SizedBox(height: 16),
              TeamMemberFilterDropdown(
                members: _members,
                selectedMemberId: _selectedMemberId,
                onChanged: (memberId) {
                  setState(() {
                    _selectedMemberId = memberId;
                    _loading = true;
                  });
                  _load();
                },
              ),
            ],
            const SizedBox(height: 24),
            _LeadCommandBar(
              searchCtrl: _searchCtrl,
              search: _search,
              statusFilter: _statusFilter,
              onSearchChanged: (v) => setState(() => _search = v),
              onClearSearch: () {
                _searchCtrl.clear();
                setState(() => _search = '');
              },
              onStatusChanged: (value) => setState(() => _statusFilter = value),
            ),
            const SizedBox(height: 18),
            _LeadMetricStrip(
              total: _allLeads.length,
              newCount: newCount,
              contactedCount: convertedCount,
            ),
            const SizedBox(height: 22),
            if (_loading)
              const SizedBox(
                height: 360,
                child: Center(child: TapLoopProgressIndicator()),
              )
            else if (leads.isEmpty)
              _LeadPanel(
                child: SizedBox(
                  height: 260,
                  child: Center(
                    child: Text(
                      'No hay leads para este filtro todavía.',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: context.textMuted,
                      ),
                    ),
                  ),
                ),
              )
            else
              _LeadWorkspace(
                leads: leads,
                selectedLeadId: _selectedLeadId,
                onSelectLead: (lead) =>
                    setState(() => _selectedLeadId = lead.id),
                onConverted: _markAsConverted,
              ),
          ],
        ),
      ),
    );
  }
}

class _LeadCommandBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String search;
  final String statusFilter;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onStatusChanged;

  const _LeadCommandBar({
    required this.searchCtrl,
    required this.search,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final searchField = SizedBox(
      width: 230,
      height: 38,
      child: TextField(
        controller: searchCtrl,
        onChanged: onSearchChanged,
        inputFormatters: [LengthLimitingTextInputFormatter(200)],
        maxLength: 200,
        style: GoogleFonts.dmSans(fontSize: 13, color: context.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar lead...',
          hintStyle: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
          counterText: '',
          isDense: true,
          prefixIcon: Icon(Icons.search_rounded, color: context.textSecondary),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 38,
          ),
          suffixIcon: search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: onClearSearch,
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          filled: true,
          fillColor: context.bgCard,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: context.borderStrongSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: context.borderStrongSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
          ),
        ),
      ),
    );

    return _LeadPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabs = _LeadStatusTabs(
            value: statusFilter,
            onChanged: onStatusChanged,
          );
          final tools = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              searchField,
              const SizedBox(width: 12),
              const _LeadToolbarButton(
                icon: Icons.calendar_today_outlined,
                label: 'Fechas',
              ),
              const SizedBox(width: 12),
              const _LeadToolbarButton(
                icon: Icons.filter_alt_outlined,
                label: 'Todos los orígenes',
              ),
              const SizedBox(width: 12),
              const _LeadToolbarButton(
                icon: Icons.keyboard_arrow_down_rounded,
                label: 'Ordenar por: Recientes',
              ),
            ],
          );
          if (constraints.maxWidth >= 1120) {
            return Row(children: [tabs, const Spacer(), tools]);
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [tabs, const SizedBox(width: 28), tools]),
          );
        },
      ),
    );
  }
}

class _LeadMetricStrip extends StatelessWidget {
  final int total;
  final int newCount;
  final int contactedCount;

  const _LeadMetricStrip({
    required this.total,
    required this.newCount,
    required this.contactedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 34,
      runSpacing: 14,
      children: [
        _LeadMetricChip(
          icon: Icons.assignment_ind_outlined,
          value: total,
          label: 'leads totales',
          color: context.textSecondary,
        ),
        _LeadMetricChip(
          icon: Icons.circle,
          value: newCount,
          label: 'nuevos',
          color: AppColors.primary,
        ),
        _LeadMetricChip(
          icon: Icons.circle,
          value: contactedCount,
          label: 'contactado',
          color: AppColors.success,
        ),
      ],
    );
  }
}

class _LeadMetricChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;

  const _LeadMetricChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          '$value',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _LeadWorkspace extends StatelessWidget {
  final List<LeadModel> leads;
  final String? selectedLeadId;
  final ValueChanged<LeadModel> onSelectLead;
  final ValueChanged<LeadModel> onConverted;

  const _LeadWorkspace({
    required this.leads,
    required this.selectedLeadId,
    required this.onSelectLead,
    required this.onConverted,
  });

  @override
  Widget build(BuildContext context) {
    final selected = leads.cast<LeadModel?>().firstWhere(
      (lead) => lead?.id == selectedLeadId,
      orElse: () => leads.first,
    )!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 980;
        if (stacked) {
          return Column(
            children: [
              _LeadListPanel(
                leads: leads,
                selectedLeadId: selected.id,
                onSelectLead: onSelectLead,
              ),
              const SizedBox(height: 16),
              _LeadDetailPanel(
                lead: selected,
                onConverted: () => onConverted(selected),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 520,
              child: _LeadListPanel(
                leads: leads,
                selectedLeadId: selected.id,
                onSelectLead: onSelectLead,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _LeadDetailPanel(
                lead: selected,
                onConverted: () => onConverted(selected),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LeadListPanel extends StatelessWidget {
  final List<LeadModel> leads;
  final String selectedLeadId;
  final ValueChanged<LeadModel> onSelectLead;

  const _LeadListPanel({
    required this.leads,
    required this.selectedLeadId,
    required this.onSelectLead,
  });

  @override
  Widget build(BuildContext context) {
    return _LeadPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Text(
              'Leads (${leads.length})',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
          ),
          ...leads.asMap().entries.map((entry) {
            final index = entry.key;
            final lead = entry.value;
            return _LeadListRow(
              lead: lead,
              selected: lead.id == selectedLeadId,
              showDivider: index < leads.length - 1,
              onTap: () => onSelectLead(lead),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: Row(
              children: [
                Expanded(child: Divider(color: context.borderStrongSoft)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'Fin de la lista',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: context.textMuted,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: context.borderStrongSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadListRow extends StatefulWidget {
  final LeadModel lead;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  const _LeadListRow({
    required this.lead,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  @override
  State<_LeadListRow> createState() => _LeadListRowState();
}

class _LeadListRowState extends State<_LeadListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final selected = widget.selected;
    final email = _leadFormValue(lead, 'email');
    final phone = _leadFormValue(lead, 'phone');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.08),
                      AppColors.primaryLight.withValues(alpha: 0.035),
                      AppColors.primary.withValues(alpha: 0.015),
                    ],
                  )
                : null,
            color: selected
                ? null
                : _hovered
                ? context.bgSubtle.withValues(alpha: 0.72)
                : context.bgCard,
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 4,
              ),
              top: selected
                  ? BorderSide(color: AppColors.primary.withValues(alpha: 0.18))
                  : BorderSide.none,
              right: selected
                  ? BorderSide(color: AppColors.primary.withValues(alpha: 0.18))
                  : BorderSide.none,
              bottom: widget.showDivider
                  ? BorderSide(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : context.borderStrongSoft,
                    )
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Row(
            children: [
              _LeadListAvatar(lead: lead),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lead.company?.trim().isNotEmpty == true
                          ? lead.company!
                          : 'Empresa no disponible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (email != null)
                          _LeadMiniFact(icon: Icons.mail_outline, label: email),
                        if (phone != null)
                          _LeadMiniFact(
                            icon: Icons.phone_outlined,
                            label: phone,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _LeadStatusPill(contacted: lead.isConverted),
                  const SizedBox(height: 12),
                  Text(
                    _fmtDay(lead.lastSeen),
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver info',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadDetailPanel extends StatefulWidget {
  final LeadModel lead;
  final VoidCallback onConverted;

  const _LeadDetailPanel({required this.lead, required this.onConverted});

  @override
  State<_LeadDetailPanel> createState() => _LeadDetailPanelState();
}

class _LeadDetailPanelState extends State<_LeadDetailPanel> {
  bool _showAllTimeline = false;

  @override
  void didUpdateWidget(covariant _LeadDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lead.id != widget.lead.id) _showAllTimeline = false;
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final email = _leadFormValue(lead, 'email');
    final phone = _leadFormValue(lead, 'phone');
    final timeline = _buildTimeline(lead);
    final visibleTimeline = _showAllTimeline
        ? timeline
        : timeline.take(6).toList();
    final hasMoreTimeline = timeline.length > 6;

    return _LeadPanel(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeadAvatar(lead: lead),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HelpTitle(
                      title: lead.displayName,
                      helpText:
                          'Resumen del lead seleccionado y sus datos principales.',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lead.company?.trim().isNotEmpty == true
                          ? lead.company!
                          : 'Empresa no disponible',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        if (email != null)
                          _LeadMiniFact(icon: Icons.mail_outline, label: email),
                        if (phone != null)
                          _LeadMiniFact(
                            icon: Icons.phone_outlined,
                            label: phone,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              _LeadDetailActions(lead: lead, onConverted: widget.onConverted),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _LeadDetailFact(
                icon: Icons.schedule_rounded,
                label: 'Estado:',
                value: lead.isConverted ? 'Contactado' : 'Pendiente',
              ),
              _LeadDetailFact(
                icon: Icons.link_rounded,
                label: 'Origen:',
                value: _leadSourceLabel(lead),
              ),
              _LeadDetailFact(
                icon: Icons.calendar_today_outlined,
                label: 'Capturado:',
                value: _fmtDay(lead.firstSeen),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(color: context.borderStrongSoft, height: 1),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 720;
              final timelineColumn = _LeadActivityColumn(
                lead: lead,
                timeline: visibleTimeline,
                showAllTimeline: _showAllTimeline,
                hasMoreTimeline: hasMoreTimeline,
                onToggleTimeline: () =>
                    setState(() => _showAllTimeline = !_showAllTimeline),
              );
              final info = _LeadInfoPanel(lead: lead);
              if (!sideBySide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [timelineColumn, const SizedBox(height: 18), info],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: timelineColumn),
                  const SizedBox(width: 24),
                  SizedBox(width: 270, child: info),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LeadDetailActions extends StatelessWidget {
  final LeadModel lead;
  final VoidCallback onConverted;

  const _LeadDetailActions({required this.lead, required this.onConverted});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lead.formData != null && lead.formData!.isNotEmpty) ...[
            _LeadOutlineAction(
              icon: Icons.open_in_new_rounded,
              label: 'Ver info',
              child: _FormEventButton(
                formData: lead.formData!,
                formType: lead.formType,
                label: 'Ver info',
                primaryStyle: true,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _LeadOutlineAction(
            icon: Icons.check_circle_outline_rounded,
            label: lead.isConverted ? 'Contactado' : 'Marcar contactado',
            onTap: lead.isConverted ? null : onConverted,
          ),
        ],
      ),
    );
  }
}

class _LeadOutlineAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? child;

  const _LeadOutlineAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: context.textSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    if (child != null) return child!;
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}

class _LeadActivityColumn extends StatelessWidget {
  final LeadModel lead;
  final List<_TimelineEvent> timeline;
  final bool showAllTimeline;
  final bool hasMoreTimeline;
  final VoidCallback onToggleTimeline;

  const _LeadActivityColumn({
    required this.lead,
    required this.timeline,
    required this.showAllTimeline,
    required this.hasMoreTimeline,
    required this.onToggleTimeline,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HelpTitle(
          title: 'Actividad reciente',
          helpText: 'Secuencia de eventos e interacciones de este lead.',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 18),
        ...timeline.asMap().entries.map((entry) {
          final i = entry.key;
          return _TimelineEventRow(
            event: entry.value,
            isLast: i == timeline.length - 1,
            formData: lead.formData,
            formType: lead.formType,
          );
        }),
        if (hasMoreTimeline) ...[
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onToggleTimeline,
              child: Text(
                showAllTimeline ? 'Ver menos' : 'Ver todos los eventos',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LeadInfoPanel extends StatelessWidget {
  final LeadModel lead;

  const _LeadInfoPanel({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: 'Información del lead',
            helpText:
                'Datos de contacto, estado y detalles capturados del lead.',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          _LeadInfoRow(
            icon: Icons.schedule_rounded,
            label: 'Estado',
            value: lead.isConverted ? 'Contactado' : 'Pendiente',
            pill: true,
          ),
          _LeadInfoRow(
            icon: Icons.link_rounded,
            label: 'Origen',
            value: _leadSourceLabel(lead),
          ),
          _LeadInfoRow(
            icon: Icons.alarm_rounded,
            label: 'Última actividad',
            value: '${_fmtDay(lead.lastSeen)}, ${_fmt(lead.lastSeen)}',
          ),
          _LeadInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Capturado',
            value: '${_fmtDay(lead.firstSeen)}, ${_fmt(lead.firstSeen)}',
          ),
        ],
      ),
    );
  }
}

class _LeadInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool pill;

  const _LeadInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.pill = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: context.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          pill
              ? _LeadStatusPill(contacted: value == 'Contactado')
              : Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _LeadDetailFact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _LeadDetailFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: context.textSecondary),
        const SizedBox(width: 7),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LeadMiniFact extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LeadMiniFact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: context.textSecondary),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _LeadStatusPill extends StatelessWidget {
  final bool contacted;

  const _LeadStatusPill({required this.contacted});

  @override
  Widget build(BuildContext context) {
    final color = contacted ? AppColors.success : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: contacted ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: contacted
              ? color.withValues(alpha: 0.14)
              : const Color(0xFFD8DEE8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            contacted ? Icons.check_circle_outline : Icons.schedule_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            contacted ? 'Contactado' : 'Pendiente',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadListAvatar extends StatelessWidget {
  final LeadModel lead;

  const _LeadListAvatar({required this.lead});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: context.borderStrongSoft),
      ),
      child: Text(
        _leadInitials(lead),
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: context.textPrimary,
        ),
      ),
    );
  }
}

String _leadSourceLabel(LeadModel lead) {
  final source = lead.formType?.trim();
  if (source != null && source.isNotEmpty) return _formTitle(source);
  return 'link público';
}

class _LeadStatusTabs extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LeadStatusTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LeadStatusTab(
          label: 'Todos',
          value: 'all',
          selected: value == 'all',
          onTap: onChanged,
        ),
        _LeadStatusTab(
          label: 'Nuevo',
          value: 'new',
          selected: value == 'new',
          onTap: onChanged,
        ),
        _LeadStatusTab(
          label: 'Contactado',
          value: 'contacted',
          selected: value == 'contacted',
          onTap: onChanged,
        ),
      ],
    );
  }
}

class _LeadStatusTab extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  const _LeadStatusTab({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(value),
      child: Padding(
        padding: const EdgeInsets.only(right: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.primary : context.textPrimary,
              ),
            ),
            const SizedBox(height: 9),
            Container(
              width: 54,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LeadToolbarButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: context.textSecondary),
        ],
      ),
    );
  }
}

class _LeadPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _LeadPanel({
    required this.child,
    this.padding = const EdgeInsets.all(28),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: child,
    );
  }
}

String _leadInitials(LeadModel lead) {
  final name = lead.displayName.trim();
  if (name.isEmpty) return '?';
  final parts = name.split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name[0].toUpperCase();
}

String? _leadFormValue(LeadModel lead, String kind) {
  final data = lead.formData;
  if (data == null) return null;
  for (final entry in data.entries) {
    final key = entry.key.toLowerCase();
    final value = (entry.value ?? '').toString().trim();
    if (value.isEmpty) continue;
    if (kind == 'email' &&
        (key.contains('email') ||
            key.contains('correo') ||
            value.contains('@'))) {
      return value;
    }
    if (kind == 'phone' &&
        (key.contains('phone') ||
            key.contains('telefono') ||
            key.contains('teléfono') ||
            key.contains('whatsapp') ||
            RegExp(r'\+?\d[\d\s\-\(\)]{7,}').hasMatch(value))) {
      return value;
    }
  }
  return null;
}

class _LeadAvatar extends StatelessWidget {
  final LeadModel lead;

  const _LeadAvatar({required this.lead});

  @override
  Widget build(BuildContext context) {
    final url = lead.avatarUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;
    return Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lead.isConverted ? AppColors.success : AppColors.primary,
        shape: BoxShape.circle,
        image: hasImage
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: hasImage
          ? null
          : Text(
              _leadInitials(lead),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _LeadInlineFact extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LeadInlineFact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _LeadBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool subtle;

  const _LeadBadge({
    required this.label,
    required this.color,
    this.icon,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = subtle
        ? context.textSecondary.withValues(alpha: 0.78)
        : color.withValues(alpha: 0.9);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      ],
    );
  }
}

class _LeadContactButton extends StatelessWidget {
  final bool contacted;
  final VoidCallback onTap;

  const _LeadContactButton({required this.contacted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = contacted ? AppColors.success : const Color(0xFF64748B);
    final bgColor = contacted
        ? AppColors.success.withValues(alpha: 0.1)
        : Colors.transparent;
    final borderColor = contacted
        ? AppColors.success.withValues(alpha: 0.22)
        : const Color(0xFFD8DEE8);

    return MouseRegion(
      cursor: contacted ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: contacted ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                contacted ? Icons.check_circle_rounded : Icons.schedule_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                contacted ? 'Contactado' : 'Pendiente',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Lead Row ─────────────────────────────────────────────────────────────────

class _LeadTimelineCard extends StatefulWidget {
  final LeadModel lead;
  final bool showDivider;
  final VoidCallback onConverted;

  const _LeadTimelineCard({
    required this.lead,
    required this.showDivider,
    required this.onConverted,
  });

  @override
  State<_LeadTimelineCard> createState() => _LeadTimelineCardState();
}

class _LeadTimelineCardState extends State<_LeadTimelineCard> {
  bool _showAllTimeline = false;

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final timeline = _buildTimeline(lead);
    final visibleTimeline = _showAllTimeline
        ? timeline
        : timeline.take(4).toList();
    final hasMoreTimeline = timeline.length > 4;
    final hasFormData = lead.formData != null && lead.formData!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.borderStrongSoft, width: 1.1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LeadAvatar(lead: lead),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    lead.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ),
                                if (hasFormData) ...[
                                  const SizedBox(width: 12),
                                  _FormEventButton(
                                    formData: lead.formData!,
                                    formType: lead.formType,
                                    label: 'Ver info',
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lead.company?.trim().isNotEmpty == true
                                  ? lead.company!
                                  : 'Empresa no disponible',
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                if (_leadFormValue(lead, 'email') != null)
                                  _LeadInlineFact(
                                    icon: Icons.email_outlined,
                                    label: _leadFormValue(lead, 'email')!,
                                  ),
                                if (_leadFormValue(lead, 'phone') != null)
                                  _LeadInlineFact(
                                    icon: Icons.phone_outlined,
                                    label: _leadFormValue(lead, 'phone')!,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _LeadBadge(
                                  label: lead.isConverted
                                      ? 'Contactado'
                                      : 'Pendiente',
                                  color: lead.isConverted
                                      ? AppColors.success
                                      : const Color(0xFF64748B),
                                  icon: lead.isConverted
                                      ? Icons.check_circle_rounded
                                      : Icons.schedule_rounded,
                                  subtle: !lead.isConverted,
                                ),
                                _LeadBadge(
                                  label: 'Origen: link público',
                                  color: context.textSecondary,
                                  subtle: true,
                                ),
                                _LeadBadge(
                                  label: _fmtDay(lead.firstSeen),
                                  color: context.textSecondary,
                                  icon: Icons.schedule_rounded,
                                  subtle: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _fmtDay(lead.lastSeen),
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _LeadContactButton(
                            contacted: lead.isConverted,
                            onTap: widget.onConverted,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ...visibleTimeline.asMap().entries.map((entry) {
                    final i = entry.key;
                    final ev = entry.value;
                    final isLast = i == visibleTimeline.length - 1;
                    return _TimelineEventRow(
                      event: ev,
                      isLast: isLast,
                      formData: lead.formData,
                      formType: lead.formType,
                    );
                  }),
                  if (hasMoreTimeline) ...[
                    const SizedBox(height: 4),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _showAllTimeline = !_showAllTimeline,
                        ),
                        child: Text(
                          _showAllTimeline
                              ? 'Ver menos'
                              : 'Ver todos los eventos',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.showDivider)
              Divider(
                color: context.borderColor,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Timeline Event Row ───────────────────────────────────────────────────────

class _TimelineEventRow extends StatelessWidget {
  final _TimelineEvent event;
  final bool isLast;
  final Map<String, dynamic>? formData;
  final String? formType;

  const _TimelineEventRow({
    required this.event,
    required this.isLast,
    this.formData,
    this.formType,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = context.borderColor.withValues(alpha: 0.9);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 2 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.only(top: 4),
                    color: lineColor,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.time,
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              event.label,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      event.date,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.textMuted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(event.icon, size: 14, color: context.textMuted),
                  ],
                ),
                if (event.isFormEvent &&
                    formData != null &&
                    formData!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _FormEventButton(
                      formData: formData!,
                      formType: formType,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormEventButton extends StatelessWidget {
  final Map<String, dynamic> formData;
  final String? formType;
  final String label;
  final bool primaryStyle;

  const _FormEventButton({
    required this.formData,
    this.formType,
    this.label = 'Ver formulario',
    this.primaryStyle = false,
  });

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible abrir la acción.')),
      );
    }
  }

  Future<void> _saveLeadSummary(BuildContext context) async {
    final buffer = StringBuffer();
    buffer.writeln('Formulario: ${_formTitle(formType)}');
    for (final entry in _visibleFormEntries(formData)) {
      final key = entry.key;
      final value = entry.value;
      buffer.writeln('$key: $value');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Información copiada para guardar contacto.'),
        ),
      );
    }
  }

  bool _isEmailField(String key, String value) {
    final mailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final lowerKey = key.toLowerCase();
    return mailRegex.hasMatch(value) ||
        ((lowerKey.contains('correo') || lowerKey.contains('email')) &&
            value.contains('@'));
  }

  bool _isPhoneField(String key, String value) {
    final phoneRegex = RegExp(r'\+?\d[\d\s\-\(\)]{7,}');
    final lowerKey = key.toLowerCase();
    return phoneRegex.hasMatch(value) ||
        lowerKey.contains('telefono') ||
        lowerKey.contains('teléfono') ||
        lowerKey.contains('phone') ||
        lowerKey.contains('whatsapp');
  }

  Future<void> _copyField(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dato copiado.')));
    }
  }

  String _displayValue(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is Iterable) {
      return raw
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .join(', ');
    }
    if (raw is Map) return raw.values.map((item) => item.toString()).join(', ');
    return raw.toString().trim();
  }

  String _fieldIdentity(String key, String value) {
    final lowerKey = key.toLowerCase();
    if (_isEmailField(key, value)) return 'email';
    if (_isPhoneField(key, value)) return 'phone';
    if (lowerKey.contains('nombre') || lowerKey.contains('name')) return 'name';
    if (lowerKey.contains('mensaje') || lowerKey.contains('message')) {
      return 'message';
    }
    if (lowerKey.contains('empresa') || lowerKey.contains('company')) {
      return 'company';
    }
    if (lowerKey.contains('presupuesto') || lowerKey.contains('budget')) {
      return 'budget';
    }
    if (lowerKey.contains('fecha') || lowerKey.contains('date')) return 'date';
    return lowerKey.trim();
  }

  IconData _fieldIcon(String identity) {
    switch (identity) {
      case 'email':
        return Icons.mail_outline_rounded;
      case 'phone':
        return Icons.phone_outlined;
      case 'name':
        return Icons.person_outline_rounded;
      case 'message':
        return Icons.chat_bubble_outline_rounded;
      case 'company':
        return Icons.business_outlined;
      case 'budget':
        return Icons.payments_outlined;
      case 'date':
        return Icons.calendar_month_outlined;
      default:
        return Icons.short_text_rounded;
    }
  }

  List<MapEntry<String, String>> _visibleFormEntries(
    Map<String, dynamic> data,
  ) {
    final seen = <String>{};
    final entries = <MapEntry<String, String>>[];
    for (final entry in data.entries) {
      if (entry.key.startsWith('_')) continue;
      final value = _displayValue(entry.value);
      if (value.isEmpty) continue;
      final identity = _fieldIdentity(entry.key, value);
      if (!seen.add(identity)) continue;
      entries.add(MapEntry(entry.key, value));
    }
    return entries;
  }

  void _show(BuildContext context) {
    final entries = _visibleFormEntries(formData);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 740),
          child: Container(
            decoration: BoxDecoration(
              color: ctx.bgCard,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 26, 22, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.assignment_ind_outlined,
                        size: 38,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formTitle(formType),
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: ctx.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Información enviada desde el perfil público.',
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                color: ctx.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 28),
                        color: ctx.textPrimary,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 22, 30, 0),
                  child: Divider(color: ctx.borderStrongSoft, height: 1),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(30, 22, 30, 26),
                    shrinkWrap: true,
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Builder(
                            builder: (_) {
                              final key = entry.key;
                              final value = entry.value;
                              final identity = _fieldIdentity(key, value);
                              final isEmail = _isEmailField(key, value);
                              final isPhone = _isPhoneField(key, value);
                              final cleanPhone = value.replaceAll(
                                RegExp(r'[^0-9+]'),
                                '',
                              );

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: ctx.borderStrongSoft,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _fieldIcon(identity),
                                          size: 22,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                key,
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: ctx.textSecondary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                value,
                                                style: GoogleFonts.dmSans(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: ctx.textPrimary,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isEmail)
                                          _FieldCornerAction(
                                            icon: Icons.alternate_email_rounded,
                                            color: AppColors.primary,
                                            onTap: () => _launch(
                                              context,
                                              'mailto:$value',
                                            ),
                                          ),
                                        if (isPhone)
                                          _FieldCornerAction(
                                            icon: Icons.call_outlined,
                                            color: const Color(0xFF16A34A),
                                            onTap: () => _launch(
                                              context,
                                              'tel:$cleanPhone',
                                            ),
                                          ),
                                        if (isPhone)
                                          _FieldCornerAction(
                                            icon: Icons
                                                .chat_bubble_outline_rounded,
                                            color: const Color(0xFF16A34A),
                                            onTap: () => _launch(
                                              context,
                                              'https://wa.me/$cleanPhone',
                                            ),
                                          ),
                                        _FieldCornerAction(
                                          icon: Icons.content_copy_rounded,
                                          color: context.textSecondary,
                                          onTap: () =>
                                              _copyField(context, value),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(color: ctx.borderStrongSoft, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 16, 30, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cerrar',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      _DialogPrimaryAction(
                        icon: Icons.save_alt_rounded,
                        label: 'Guardar contacto',
                        onTap: () => _saveLeadSummary(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (primaryStyle) {
      return _BlueGradientActionButton(
        label: label,
        onTap: () => _show(context),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFF1D4ED8).withValues(alpha: 0.1)
                : const Color(0xFF1D4ED8).withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 13,
                color: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlueGradientActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _BlueGradientActionButton({required this.label, required this.onTap});

  @override
  State<_BlueGradientActionButton> createState() =>
      _BlueGradientActionButtonState();
}

class _BlueGradientActionButtonState extends State<_BlueGradientActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      colors: _hovered
          ? const [Color(0xFF1D4ED8), Color(0xFF3B82F6)]
          : const [Color(0xFF1749D6), Color(0xFF2563EB)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed
              ? 0.985
              : _hovered
              ? 1.002
              : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            height: 42,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(8),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.assignment_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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

class _DialogPrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DialogPrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldCornerAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FieldCornerAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
