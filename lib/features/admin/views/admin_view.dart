// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, unused_element
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/storage_upload_error.dart';
import '../../../core/utils/web_image_optimizer.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/admin_repository.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/services/metrics_realtime_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/taploop_button.dart';
import '../../../core/widgets/taploop_text_field.dart';
import '../../../core/widgets/empty_data_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../analytics/models/team_member_model.dart';
import '../../card/models/digital_card_model.dart';
import '../../card/models/smart_form_model.dart';
import '../../card/utils/calendar_links.dart';
import '../../card/views/edit_card_view.dart';

// ─── Form & Calendar support ─────────────────────────────────────────────────

enum _AdminFieldType { text, email, phone, textarea, select }

extension _AdminFieldTypeX on _AdminFieldType {
  String get label => switch (this) {
    _AdminFieldType.text => 'Texto',
    _AdminFieldType.email => 'Email',
    _AdminFieldType.phone => 'Teléfono',
    _AdminFieldType.textarea => 'Mensaje',
    _AdminFieldType.select => 'Selección',
  };

  IconData get icon => switch (this) {
    _AdminFieldType.text => Icons.short_text,
    _AdminFieldType.email => Icons.alternate_email,
    _AdminFieldType.phone => Icons.phone_outlined,
    _AdminFieldType.textarea => Icons.notes_outlined,
    _AdminFieldType.select => Icons.arrow_drop_down_circle_outlined,
  };

  Color get color => switch (this) {
    _AdminFieldType.text => const Color(0xFF64748B),
    _AdminFieldType.email => AppColors.primary,
    _AdminFieldType.phone => const Color(0xFF10B981),
    _AdminFieldType.textarea => const Color(0xFFF59E0B),
    _AdminFieldType.select => const Color(0xFF8B5CF6),
  };
}

class _AdminFormField {
  String label;
  _AdminFieldType type;
  bool required;
  _AdminFormField({
    required this.label,
    this.type = _AdminFieldType.text,
    this.required = false,
  });
}

class _AdminSmartForm {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  bool enabled;
  List<_AdminFormField> fields;
  _AdminSmartForm({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.enabled = false,
    required this.fields,
  });
}

enum _AdminCalProvider { googleCalendar, calendly, outlook, custom }

extension _AdminCalProviderX on _AdminCalProvider {
  String get label => switch (this) {
    _AdminCalProvider.googleCalendar => 'Google Calendar',
    _AdminCalProvider.calendly => 'Calendly',
    _AdminCalProvider.outlook => 'Outlook',
    _AdminCalProvider.custom => 'Otro',
  };

  IconData get icon => switch (this) {
    _AdminCalProvider.googleCalendar => Icons.event_outlined,
    _AdminCalProvider.calendly => Icons.calendar_today_outlined,
    _AdminCalProvider.outlook => Icons.mail_outline_rounded,
    _AdminCalProvider.custom => Icons.add_link_rounded,
  };

  String get hint => switch (this) {
    _AdminCalProvider.googleCalendar => 'https://calendar.google.com/...',
    _AdminCalProvider.calendly => 'https://calendly.com/tu-nombre',
    _AdminCalProvider.outlook => 'https://outlook.office365.com/...',
    _AdminCalProvider.custom => 'https://tu-servicio.com/tu-enlace',
  };
}

// ─── Local data model ─────────────────────────────────────────────────────────

class _AdminMember {
  final TeamMemberModel member;
  DigitalCardModel card;
  bool isActive;
  List<_AdminSmartForm> forms;
  _AdminCalProvider? calendarProvider;
  String? calendarioUrl;
  String? customIntegrationLabel;

  _AdminMember({
    required this.member,
    required this.card,
    this.isActive = true,
    List<_AdminSmartForm>? forms,
    this.calendarProvider,
    this.calendarioUrl,
    this.customIntegrationLabel,
  }) : forms = forms ?? _defaultForms();

  bool get isAdmin => member.isAdmin;

  static List<_AdminSmartForm> _defaultForms() => [
    _AdminSmartForm(
      id: 'cotizacion',
      title: 'Solicitar cotización',
      description:
          'El prospecto llena sus datos y recibe una cotización personalizada.',
      icon: Icons.request_quote_outlined,
      enabled: true,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Empresa',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Teléfono',
          type: _AdminFieldType.phone,
          required: true,
        ),
        _AdminFormField(
          label: 'Correo electrónico',
          type: _AdminFieldType.email,
        ),
        _AdminFormField(
          label: 'Descripción del proyecto',
          type: _AdminFieldType.textarea,
          required: true,
        ),
      ],
    ),
    _AdminSmartForm(
      id: 'demo',
      title: 'Agendar demo',
      description: 'El prospecto reserva una demostración en el calendario.',
      icon: Icons.videocam_outlined,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Correo electrónico',
          type: _AdminFieldType.email,
          required: true,
        ),
        _AdminFormField(label: 'Teléfono', type: _AdminFieldType.phone),
        _AdminFormField(label: 'Área de interés', type: _AdminFieldType.text),
      ],
    ),
    _AdminSmartForm(
      id: 'catalogo',
      title: 'Descargar catálogo',
      description: 'El prospecto deja su email para recibir el catálogo.',
      icon: Icons.download_outlined,
      enabled: true,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(
          label: 'Correo corporativo',
          type: _AdminFieldType.email,
          required: true,
        ),
        _AdminFormField(label: 'Empresa', type: _AdminFieldType.text),
      ],
    ),
    _AdminSmartForm(
      id: 'contacto',
      title: 'Formulario de contacto',
      description: 'Formulario rápido ideal para ferias y eventos.',
      icon: Icons.contact_page_outlined,
      fields: [
        _AdminFormField(
          label: 'Nombre completo',
          type: _AdminFieldType.text,
          required: true,
        ),
        _AdminFormField(label: 'Empresa', type: _AdminFieldType.text),
        _AdminFormField(
          label: 'Mensaje',
          type: _AdminFieldType.textarea,
          required: true,
        ),
      ],
    ),
  ];
}

class _TeamConsistencySettings {
  final bool sharedDesign;
  final bool sharedForms;
  final bool sharedIntegrations;
  final bool sharedLinks;
  final String? templateCardId;

  const _TeamConsistencySettings({
    this.sharedDesign = false,
    this.sharedForms = false,
    this.sharedIntegrations = false,
    this.sharedLinks = false,
    this.templateCardId,
  });

  factory _TeamConsistencySettings.fromOrg(Map<String, dynamic>? org) {
    return _TeamConsistencySettings(
      sharedDesign: org?['shared_design_enabled'] as bool? ?? false,
      sharedForms: org?['shared_forms_enabled'] as bool? ?? false,
      sharedIntegrations: org?['shared_integrations_enabled'] as bool? ?? false,
      sharedLinks: org?['shared_links_enabled'] as bool? ?? false,
      templateCardId: (org?['shared_template_card_id'] as String?)?.trim(),
    );
  }

  _TeamConsistencySettings copyWith({
    bool? sharedDesign,
    bool? sharedForms,
    bool? sharedIntegrations,
    bool? sharedLinks,
    String? templateCardId,
  }) {
    return _TeamConsistencySettings(
      sharedDesign: sharedDesign ?? this.sharedDesign,
      sharedForms: sharedForms ?? this.sharedForms,
      sharedIntegrations: sharedIntegrations ?? this.sharedIntegrations,
      sharedLinks: sharedLinks ?? this.sharedLinks,
      templateCardId: templateCardId ?? this.templateCardId,
    );
  }
}

enum _ConsistencyKind { design, forms, integrations, links }

// ─── AdminView ────────────────────────────────────────────────────────────────

class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  List<_AdminMember> _members = [];
  _TeamConsistencySettings _consistency = const _TeamConsistencySettings();
  bool _loading = true;
  bool _syncingConsistency = false;
  _ConsistencyKind? _expandedConsistencyKind;
  MetricsRealtimeSubscription? _metricsRealtime;
  String? _realtimeOrgId;
  final GlobalKey _profilesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _bindRealtime();
    _loadData();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    _metricsRealtime?.close();
    super.dispose();
  }

  void _onAppStateChanged() {
    final orgId = appState.currentUser?.orgId;
    _bindRealtime();
    if (!mounted || orgId == null) return;
    setState(() => _loading = true);
    _loadData();
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
        _loadData();
      },
    );
  }

  Future<void> _loadData() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        AdminRepository.fetchTeamMembers(orgId),
        AdminRepository.fetchOrg(orgId),
      ]);
      final teamMembers = results[0] as List<TeamMemberModel>;
      final orgData = results[1] as Map<String, dynamic>?;
      final hydratedMembers = await _buildMembers(teamMembers);
      if (mounted) {
        setState(() {
          _members = hydratedMembers;
          _consistency = _TeamConsistencySettings.fromOrg(orgData);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<List<_AdminMember>> _buildMembers(
    List<TeamMemberModel> teamMembers,
  ) async {
    final styles = [CardThemeStyle.white, CardThemeStyle.black];
    final colors = [
      const Color(0xFF0D0D0D),
      const Color(0xFF1F2937),
      const Color(0xFF6B7280),
    ];
    final cardsByUserId = await AdminRepository.fetchCardsForUsers(
      teamMembers.map((m) => m.id).toList(),
    );

    return teamMembers.asMap().entries.map((e) {
      final i = e.key;
      final m = e.value;
      final fetchedCard = cardsByUserId[m.id];
      final card =
          fetchedCard ??
          _fallbackCard(member: m, index: i, colors: colors, styles: styles);

      return _AdminMember(
        member: m,
        card: card,
        isActive: card.isActive,
        forms: _formsFromCard(card),
        calendarProvider: _providerFromUrl(card.calendarUrl),
        calendarioUrl: _firstCalendarUrlFromStored(card.calendarUrl),
        customIntegrationLabel: parseCustomCalendarLabel(card.calendarUrl),
      );
    }).toList();
  }

  static DigitalCardModel _fallbackCard({
    required TeamMemberModel member,
    required int index,
    required List<Color> colors,
    required List<CardThemeStyle> styles,
  }) {
    return DigitalCardModel(
      id: member.cardIds.isNotEmpty ? member.cardIds.first : member.id,
      userId: member.id,
      name: member.name,
      jobTitle: member.jobTitle,
      company: '',
      publicSlug: member.name.toLowerCase().replaceAll(' ', '-'),
      themeStyle: styles[index % styles.length],
      primaryColor: colors[index % colors.length],
      contactItems: const [],
      socialLinks: const [],
    );
  }

  static List<_AdminSmartForm> _formsFromCard(DigitalCardModel card) {
    if (card.smartForms.isNotEmpty) {
      return _adminFormsFromSmartForms(card.smartForms);
    }
    final enabledIds = card.enabledForms.toSet();
    return _AdminMember._defaultForms()
        .map(
          (form) => _AdminSmartForm(
            id: form.id,
            title: form.title,
            description: form.description,
            icon: form.icon,
            enabled: enabledIds.contains(form.id),
            fields: form.fields
                .map(
                  (field) => _AdminFormField(
                    label: field.label,
                    type: field.type,
                    required: field.required,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  static List<_AdminSmartForm> _adminFormsFromSmartForms(
    List<SmartFormModel> forms,
  ) {
    return forms
        .map(
          (form) => _AdminSmartForm(
            id: form.id,
            title: form.name,
            description: form.description ?? 'Formulario de captura',
            icon: Icons.description_outlined,
            enabled: form.isActive,
            fields: form.fields
                .map(
                  (field) => _AdminFormField(
                    label: field.label,
                    type: _adminFieldTypeFromSmartField(field.fieldType),
                    required: field.isRequired,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  static _AdminCalProvider? _providerFromUrl(String? url) {
    final value = url?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (!value.startsWith('{') &&
        (value.contains('outlook') || value.contains('office365'))) {
      return _AdminCalProvider.outlook;
    }
    final integrations = parseCalendarIntegrationLinks(url);
    if (integrations.isNotEmpty) {
      return switch (integrations.first.provider) {
        CalendarProviderType.calendly => _AdminCalProvider.calendly,
        CalendarProviderType.googleCalendar => _AdminCalProvider.googleCalendar,
        CalendarProviderType.microsoftTeams => _AdminCalProvider.custom,
        CalendarProviderType.custom => _AdminCalProvider.custom,
      };
    }
    if (value.contains('calendly')) return _AdminCalProvider.calendly;
    if (value.contains('calendar.google')) {
      return _AdminCalProvider.googleCalendar;
    }
    return null;
  }

  static String? _firstCalendarUrlFromStored(String? url) {
    final integrations = parseCalendarIntegrationLinks(url);
    if (integrations.isNotEmpty) return integrations.first.url;
    final value = url?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _encodeAdminCalendarUrl({
    required _AdminCalProvider? provider,
    required String url,
    required String? customLabel,
  }) {
    final cleanUrl = url.trim();
    if (provider == null || cleanUrl.isEmpty) return '';
    if (provider == _AdminCalProvider.custom) {
      return encodeCalendarLinks({
        CalendarProviderType.custom: cleanUrl,
      }, customLabel: customLabel);
    }
    return cleanUrl;
  }

  static _AdminFieldType _adminFieldTypeFromSmartField(
    SmartFormFieldType type,
  ) {
    return switch (type) {
      SmartFormFieldType.email => _AdminFieldType.email,
      SmartFormFieldType.phone => _AdminFieldType.phone,
      SmartFormFieldType.textarea => _AdminFieldType.textarea,
      SmartFormFieldType.number ||
      SmartFormFieldType.text => _AdminFieldType.text,
    };
  }

  void _editMember(_AdminMember member) {
    if (member.isAdmin) {
      _showAdminEditBlockedToast();
      return;
    }
    // Reuse EditCardView itself (in admin override mode) so editing a team
    // member looks and behaves EXACTLY like editing one's own digital
    // profile, instead of a parallel, hand-styled dialog that can drift out
    // of sync over time.
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: ctx.bgCard,
          child: SizedBox(
            width: (MediaQuery.of(ctx).size.width * 0.9)
                .clamp(960.0, 1180.0)
                .toDouble(),
            height: MediaQuery.of(context).size.height * 0.88,
            child: EditCardView(
              overrideCard: member.card,
              onClose: () => Navigator.of(ctx).maybePop(),
            ),
          ),
        ),
      ).then((_) => _loadData());
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (ctx, ctrl) => Container(
            decoration: BoxDecoration(
              color: ctx.bgCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: EditCardView(
              overrideCard: member.card,
              onClose: () => Navigator.of(ctx).maybePop(),
            ),
          ),
        ),
      ).then((_) => _loadData());
    }
  }

  _AdminMember? _sourceMemberForSharedSettings() {
    final currentCardId = appState.currentCard?.id;
    if (currentCardId != null && currentCardId.isNotEmpty) {
      final match = _members.cast<_AdminMember?>().firstWhere(
        (member) => member?.card.id == currentCardId,
        orElse: () => null,
      );
      if (match != null) return match;
    }
    return _members.isEmpty ? null : _members.first;
  }

  Future<void> _toggleConsistency({
    required _ConsistencyKind kind,
    required bool enabled,
  }) async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) return;

    // Every time a shared toggle is turned ON, ask which member's card acts
    // as the template — even if one was already chosen before, so the admin
    // can confirm it again (tap the same member) or pick a different one.
    // Cancelling the picker must leave the toggle untouched.
    String? templateCardId;
    if (enabled) {
      if (_members.isEmpty) return;
      final picked = await _pickTemplateMember();
      if (picked == null || !mounted) return;
      templateCardId = picked.card.id;
    }

    final previous = _consistency;
    setState(() {
      _syncingConsistency = true;
      _expandedConsistencyKind = enabled ? kind : _expandedConsistencyKind;
      _consistency = switch (kind) {
        _ConsistencyKind.design => _consistency.copyWith(sharedDesign: enabled),
        _ConsistencyKind.forms => _consistency.copyWith(sharedForms: enabled),
        _ConsistencyKind.integrations => _consistency.copyWith(
          sharedIntegrations: enabled,
        ),
        _ConsistencyKind.links => _consistency.copyWith(sharedLinks: enabled),
      };
    });
    try {
      await AdminRepository.updateOrgConsistencySettings(
        orgId: orgId,
        sharedDesignEnabled: kind == _ConsistencyKind.design ? enabled : null,
        sharedFormsEnabled: kind == _ConsistencyKind.forms ? enabled : null,
        sharedIntegrationsEnabled: kind == _ConsistencyKind.integrations
            ? enabled
            : null,
        sharedLinksEnabled: kind == _ConsistencyKind.links ? enabled : null,
        templateCardId: templateCardId,
      );
      if (!mounted) return;
      if (!enabled && _expandedConsistencyKind == kind) {
        setState(() => _expandedConsistencyKind = null);
      }
      TapLoopToast.show(
        context,
        enabled
            ? 'Configuración compartida aplicada a la organización.'
            : 'Configuración compartida desactivada.',
        TapLoopToastType.success,
      );
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      setState(() => _consistency = previous);
      TapLoopToast.show(
        context,
        'No se pudo actualizar la consistencia. Ejecuta la migración de BD si aún no existe.',
        TapLoopToastType.error,
      );
    } finally {
      if (mounted) setState(() => _syncingConsistency = false);
    }
  }

  /// The member whose card currently acts as the org's shared template,
  /// falling back to [_sourceMemberForSharedSettings] when no template has
  /// been chosen yet.
  _AdminMember? _currentTemplateMember() {
    final templateId = _consistency.templateCardId;
    if (templateId != null && templateId.isNotEmpty) {
      final match = _members.cast<_AdminMember?>().firstWhere(
        (member) => member?.card.id == templateId,
        orElse: () => null,
      );
      if (match != null) return match;
    }
    return _sourceMemberForSharedSettings();
  }

  void _editTemplateMember() {
    final templateMember = _currentTemplateMember();
    if (templateMember == null) return;
    _editMember(templateMember);
  }

  Future<void> _changeTemplateMember() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty || _members.isEmpty) return;
    final selected = await _pickTemplateMember();
    if (selected == null || !mounted) return;
    try {
      await AdminRepository.updateOrgConsistencySettings(
        orgId: orgId,
        templateCardId: selected.card.id,
      );
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'Miembro plantilla actualizado.',
        TapLoopToastType.success,
      );
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo actualizar el miembro plantilla.',
        TapLoopToastType.error,
      );
    }
  }

  /// Shows the template-member picker dialog (used both when manually
  /// changing the template member and whenever a shared toggle is turned
  /// on) and returns the chosen member, or `null` if cancelled. The current
  /// template member (if any) is marked with a checkmark and can simply be
  /// tapped again to keep it.
  Future<_AdminMember?> _pickTemplateMember() {
    return showDialog<_AdminMember>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: ctx.bgCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Elegir miembro plantilla',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ctx.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Este miembro definirá lo que ven todos los demás mientras el toggle esté activo.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: ctx.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _members.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: ctx.borderColor),
                    itemBuilder: (_, i) {
                      final m = _members[i];
                      final isCurrent =
                          m.card.id == _consistency.templateCardId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          m.card.name,
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            color: ctx.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          m.card.jobTitle,
                          style: GoogleFonts.dmSans(color: ctx.textSecondary),
                        ),
                        trailing: isCurrent
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, m),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<_AdminSmartForm> _cloneAdminForms(List<_AdminSmartForm> forms) {
    return forms
        .map(
          (form) => _AdminSmartForm(
            id: form.id,
            title: form.title,
            description: form.description,
            icon: form.icon,
            enabled: form.enabled,
            fields: form.fields
                .map(
                  (field) => _AdminFormField(
                    label: field.label,
                    type: field.type,
                    required: field.required,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  void _scrollToProfiles() {
    final context = _profilesKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _shareAccess() async {
    final orgId = appState.currentUser?.orgId;
    await Clipboard.setData(
      ClipboardData(text: orgId == null ? 'TapLoop' : 'Organización: $orgId'),
    );
    if (!mounted) return;
    TapLoopToast.show(
      context,
      'Referencia de acceso copiada.',
      TapLoopToastType.success,
    );
  }

  void _showInviteUnavailable() {
    TapLoopToast.show(
      context,
      'El flujo de invitaciones aún no está configurado en la base de datos.',
      TapLoopToastType.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: TapLoopProgressIndicator()));
    }
    final isDesktop = Responsive.isDesktop(context);
    final hPad = Responsive.isMobile(context) ? 20.0 : 32.0;
    final activeMembers = _members.where((member) => member.isActive).toList();
    final activeCount = activeMembers.length;
    final inactiveCount = _members.length - activeCount;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: context.bgCard,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administración',
                    style: GoogleFonts.outfit(
                      fontSize: isDesktop ? 42 : 30,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Centraliza la gestión de tu equipo, su identidad y su operación desde un solo lugar.',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CompanyHeader(onManageTeam: _scrollToProfiles),
                  const SizedBox(height: 20),
                  _TeamConsistencyPanel(
                    settings: _consistency,
                    syncing: _syncingConsistency,
                    expandedKind: _expandedConsistencyKind,
                    templateMember: _currentTemplateMember(),
                    onToggle: _toggleConsistency,
                    onSelectKind: (kind) {
                      setState(() => _expandedConsistencyKind = kind);
                    },
                    onEditTemplate: _editTemplateMember,
                    onChangeTemplate: _changeTemplateMember,
                  ),
                  const SizedBox(height: 20),
                  if (_members.isEmpty)
                    const EmptyDataState(
                      hint: 'Aún no hay miembros del equipo para mostrar.',
                    )
                  else
                    _TeamProfilesPanel(
                      key: _profilesKey,
                      members: _members,
                      activeCount: activeCount,
                      inactiveCount: inactiveCount,
                      onView: _viewMember,
                      onEdit: _editMember,
                      onToggle: _toggleMember,
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMember(_AdminMember m, bool value) async {
    if (m.isAdmin) {
      _showAdminEditBlockedToast();
      return;
    }
    final previous = m.isActive;
    setState(() => m.isActive = value);
    try {
      await AdminRepository.updateCardActivation(
        cardId: m.card.id,
        isActive: value,
        reason: value ? null : 'Tarjeta digital desactivada por seguridad',
      );
      m.card = m.card.copyWith(
        isActive: value,
        deactivatedAt: value ? null : DateTime.now(),
        deactivationReason: value
            ? null
            : 'Tarjeta digital desactivada por seguridad',
      );
      if (appState.currentCard?.id == m.card.id) {
        appState.updateCard(m.card);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => m.isActive = previous);
      TapLoopToast.show(
        context,
        'No se pudo actualizar la tarjeta. Intenta de nuevo.',
        TapLoopToastType.error,
      );
    }
  }

  void _viewMember(_AdminMember member) {
    final url = member.card.publicUrl;
    html.window.open(url, '_blank');
  }

  void _showAdminEditBlockedToast() {
    TapLoopToast.show(
      context,
      'No se pueden editar administradores desde esta sección.',
      TapLoopToastType.warning,
    );
  }
}

// ─── Company Header ───────────────────────────────────────────────────────────

class _CompanyHeader extends StatefulWidget {
  final VoidCallback onManageTeam;

  const _CompanyHeader({required this.onManageTeam});

  @override
  State<_CompanyHeader> createState() => _CompanyHeaderState();
}

class _CompanyHeaderState extends State<_CompanyHeader> {
  bool _uploading = false;
  String? _organizationLogoUrl;
  String? _organizationLogoPath;

  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
    _loadOrganizationLogo();
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    _loadOrganizationLogo();
  }

  Future<void> _loadOrganizationLogo() async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _organizationLogoUrl = null;
        _organizationLogoPath = null;
      });
      return;
    }
    final orgData = await AdminRepository.fetchOrg(orgId);
    final storedLogoValue = orgData?['company_logo'] as String?;
    final logoPath = CardRepository.extractCompanyLogoStoragePath(
      storedLogoValue,
    );
    final logoUrl = CardRepository.resolveCompanyLogoUrl(storedLogoValue);
    if (!mounted) return;
    setState(() {
      _organizationLogoPath = logoPath;
      _organizationLogoUrl = logoUrl;
    });
  }

  String _initials(String company) {
    final parts = company.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  Future<void> _pickAndUploadLogo() async {
    if (!kIsWeb || _uploading) return;
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) return;

    final input = html.FileUploadInputElement()
      ..accept = 'image/jpeg,image/png,image/svg+xml';
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;

    // Validar tipo de archivo
    const tiposPermitidos = ['image/jpeg', 'image/png', 'image/svg+xml'];
    if (!tiposPermitidos.contains(file.type)) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'Solo se permiten imágenes en formato JPG, PNG o SVG.',
          TapLoopToastType.error,
        );
      }
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'La imagen supera el límite de 5 MB.',
          TapLoopToastType.error,
        );
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      late final Uint8List bytes;
      late final String contentType;
      late final String ext;
      if (file.type == 'image/svg+xml') {
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoad.first;
        bytes = reader.result as Uint8List;
        contentType = file.type;
        ext = 'svg';
      } else {
        final optimized = await optimizeWebRasterImage(
          file,
          maxDimension: 1200,
          outputType: 'image/png',
          flattenToWhite: false,
        );
        bytes = optimized.bytes;
        contentType = optimized.contentType;
        ext = optimized.extension;
      }
      final path = '$orgId/logo_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseService.client.storage
          .from('company-logos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );

      final updatedLogoUrl =
          '${CardRepository.buildCompanyLogoPublicUrl(path)}?t=${DateTime.now().millisecondsSinceEpoch}';

      await AdminRepository.updateOrgLogo(
        orgId: orgId,
        companyLogo: updatedLogoUrl,
      );

      final previousPath = _organizationLogoPath;
      if (previousPath != null &&
          previousPath.isNotEmpty &&
          previousPath != path) {
        try {
          await SupabaseService.client.storage.from('company-logos').remove([
            previousPath,
          ]);
        } catch (_) {}
      }

      final currentCard = appState.currentCard;
      if (currentCard != null && currentCard.orgId == orgId) {
        appState.updateCard(
          currentCard.copyWith(companyLogoUrl: updatedLogoUrl),
        );
      }
      if (mounted) {
        setState(() {
          _organizationLogoPath = path;
          _organizationLogoUrl = updatedLogoUrl;
        });
      }

      if (mounted) {
        TapLoopToast.show(
          context,
          'El logo se actualizó correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        TapLoopToast.show(
          context,
          friendlyStorageUploadError(
            error,
            assetLabel: 'el logo',
            bucket: 'company-logos',
          ),
          TapLoopToastType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editOrgName(String currentName) async {
    final orgId = appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) return;
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: ctx.bgCard,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nombre de la organización',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ctx.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TapLoopTextField(
                label: 'Nombre',
                controller: controller,
                hint: 'Nombre de la organización',
                autofocus: true,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  TapLoopButton(
                    label: 'Guardar',
                    onPressed: () {
                      final trimmed = controller.text.trim();
                      if (trimmed.isEmpty) return;
                      Navigator.pop(ctx, trimmed);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      await AdminRepository.updateOrgName(orgId: orgId, name: newName);
      final currentCard = appState.currentCard;
      if (currentCard != null && currentCard.orgId == orgId) {
        appState.updateCard(currentCard.copyWith(company: newName));
      }
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'Nombre de la organización actualizado.',
        TapLoopToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo actualizar el nombre. Intenta de nuevo.',
        TapLoopToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final card = appState.currentCard;
        final company = (card?.company.trim().isNotEmpty ?? false)
            ? card!.company
            : 'Organización';
        final logoUrl = _organizationLogoUrl ?? card?.companyLogoUrl;
        final isDesktop = Responsive.isDesktop(context);

        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 34 : 22,
            28,
            isDesktop ? 34 : 22,
            28,
          ),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderStrongSoft, width: 1.1),
          ),
          child: isDesktop
              ? Row(
                  children: [
                    _CompanyLogo(
                      logoUrl: logoUrl,
                      initials: _initials(company),
                      onTap: appState.currentUser?.orgId == null
                          ? null
                          : _pickAndUploadLogo,
                    ),
                    const SizedBox(width: 28),
                    Expanded(child: _CompanyTitle(company: company)),
                    const SizedBox(width: 18),
                    _AdminHeroButton(
                      icon: _uploading
                          ? Icons.hourglass_top_rounded
                          : Icons.edit_outlined,
                      label: _uploading ? 'Cargando...' : 'Cambiar logo',
                      onTap: _uploading ? null : _pickAndUploadLogo,
                    ),
                    const SizedBox(width: 12),
                    _AdminHeroButton(
                      icon: Icons.drive_file_rename_outline_rounded,
                      label: 'Cambiar nombre',
                      onTap: () => _editOrgName(company),
                    ),
                    const SizedBox(width: 12),
                    _AdminHeroButton(
                      icon: Icons.groups_2_outlined,
                      label: 'Gestionar equipo',
                      onTap: widget.onManageTeam,
                    ),
                    const SizedBox(width: 10),
                    _AdminCircleAction(
                      icon: Icons.delete_outline_rounded,
                      onTap: () => TapLoopToast.show(
                        context,
                        'La eliminación de organización no está habilitada.',
                        TapLoopToastType.warning,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _CompanyLogo(
                          logoUrl: logoUrl,
                          initials: _initials(company),
                          onTap: appState.currentUser?.orgId == null
                              ? null
                              : _pickAndUploadLogo,
                        ),
                        const SizedBox(width: 18),
                        Expanded(child: _CompanyTitle(company: company)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _AdminHeroButton(
                          icon: Icons.edit_outlined,
                          label: 'Cambiar logo',
                          onTap: _uploading ? null : _pickAndUploadLogo,
                        ),
                        _AdminHeroButton(
                          icon: Icons.drive_file_rename_outline_rounded,
                          label: 'Cambiar nombre',
                          onTap: () => _editOrgName(company),
                        ),
                        _AdminHeroButton(
                          icon: Icons.groups_2_outlined,
                          label: 'Gestionar equipo',
                          onTap: widget.onManageTeam,
                        ),
                      ],
                    ),
                  ],
                ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0);
      },
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  final String? logoUrl;
  final String initials;
  final VoidCallback? onTap;

  const _CompanyLogo({
    required this.logoUrl,
    required this.initials,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.bgCard,
          shape: BoxShape.circle,
          border: Border.all(color: context.borderStrongSoft, width: 1.1),
          image: logoUrl != null
              ? DecorationImage(
                  image: NetworkImage(logoUrl!),
                  fit: BoxFit.contain,
                )
              : null,
        ),
        child: logoUrl == null
            ? Text(
                initials,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              )
            : null,
      ),
    );
  }
}

class _CompanyTitle extends StatelessWidget {
  final String company;

  const _CompanyTitle({required this.company});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        HelpTitle(
          title: company,
          helpText: 'Identifica la organización que estás administrando.',
          style: GoogleFonts.outfit(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
            height: 1.0,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.primary, width: 1.2),
          ),
          child: Text(
            'Plan ENTERPRISE',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminHeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _AdminHeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.textPrimary,
        side: BorderSide(color: context.borderStrongSoft, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        textStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AdminCircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AdminCircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: context.bgCard,
          shape: BoxShape.circle,
          border: Border.all(color: context.borderStrongSoft, width: 1.1),
        ),
        child: Icon(icon, color: context.textPrimary, size: 24),
      ),
    );
  }
}

// ─── Summary Strip ────────────────────────────────────────────────────────────

class _TeamConsistencyPanel extends StatelessWidget {
  final _TeamConsistencySettings settings;
  final bool syncing;
  final _ConsistencyKind? expandedKind;
  final _AdminMember? templateMember;
  final Future<void> Function({
    required _ConsistencyKind kind,
    required bool enabled,
  })
  onToggle;
  final ValueChanged<_ConsistencyKind> onSelectKind;
  final VoidCallback onEditTemplate;
  final VoidCallback onChangeTemplate;

  const _TeamConsistencyPanel({
    required this.settings,
    required this.syncing,
    required this.expandedKind,
    required this.templateMember,
    required this.onToggle,
    required this.onSelectKind,
    required this.onEditTemplate,
    required this.onChangeTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _ConsistencyItem(
        kind: _ConsistencyKind.design,
        icon: Icons.palette_outlined,
        title: 'Diseño compartido',
        description: 'Usa los mismos colores, portada y estilo visual.',
        enabled: settings.sharedDesign,
      ),
      _ConsistencyItem(
        kind: _ConsistencyKind.forms,
        icon: Icons.dynamic_form_outlined,
        title: 'Formulario compartido',
        description:
            'Usa el mismo formulario de captura para todos los perfiles.',
        enabled: settings.sharedForms,
      ),
      _ConsistencyItem(
        kind: _ConsistencyKind.links,
        icon: Icons.link_rounded,
        title: 'Enlaces compartidos',
        description: 'Usa las mismas redes sociales para todos los perfiles.',
        enabled: settings.sharedLinks,
      ),
      _ConsistencyItem(
        kind: _ConsistencyKind.integrations,
        icon: Icons.add_link_rounded,
        title: 'Integración compartida',
        description:
            'Usa las mismas conexiones externas para todos los perfiles.',
        enabled: settings.sharedIntegrations,
      ),
    ];

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
          HelpTitle(
            title: 'Consistencia del equipo',
            helpText:
                'Controla qué campos se mantienen uniformes en los perfiles del equipo.',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Define qué elementos se mantienen iguales para todos los perfiles y cuáles puede personalizar cada miembro.',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 30),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980 ? 3 : 1;
              final gap = 18.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: width,
                        child: _ConsistencyCard(
                          item: item,
                          syncing: syncing,
                          selected: expandedKind == item.kind,
                          onToggle: (enabled) =>
                              onToggle(kind: item.kind, enabled: enabled),
                          onSelect: () {
                            if (item.enabled) onSelectKind(item.kind);
                          },
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          if (expandedKind != null) ...[
            const SizedBox(height: 24),
            _TemplateMemberSurface(
              templateMember: templateMember,
              onEditTemplate: onEditTemplate,
              onChangeTemplate: onChangeTemplate,
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsistencyItem {
  final _ConsistencyKind kind;
  final IconData icon;
  final String title;
  final String description;
  final bool enabled;

  const _ConsistencyItem({
    required this.kind,
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
  });
}

class _ConsistencyCard extends StatelessWidget {
  final _ConsistencyItem item;
  final bool syncing;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSelect;

  const _ConsistencyCard({
    required this.item,
    required this.syncing,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 236,
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : context.borderStrongSoft,
            width: 1.1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, color: AppColors.primary, size: 32),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HelpTitle(
                        title: item.title,
                        helpText: item.description,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.description,
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          color: context.textSecondary,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  item.enabled
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  size: 20,
                  color: item.enabled
                      ? AppColors.success
                      : context.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  item.enabled ? 'Activo' : 'Inactivo',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: item.enabled
                        ? AppColors.success
                        : context.textSecondary,
                  ),
                ),
                const Spacer(),
                Switch.adaptive(
                  value: item.enabled,
                  onChanged: syncing ? null : onToggle,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.35),
                  activeThumbColor: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a consistency toggle is expanded: names the current template
/// member and offers to edit that member's profile (which is what every
/// other member will see while the toggle is active) or to swap which
/// member acts as the template.
class _TemplateMemberSurface extends StatelessWidget {
  final _AdminMember? templateMember;
  final VoidCallback onEditTemplate;
  final VoidCallback onChangeTemplate;

  const _TemplateMemberSurface({
    required this.templateMember,
    required this.onEditTemplate,
    required this.onChangeTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final name = templateMember?.card.name.trim();
    final displayName = (name == null || name.isEmpty)
        ? 'Sin miembro asignado'
        : name;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Miembro plantilla',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lo que configures para este miembro es lo que verán todos los demás mientras el toggle esté activo. Su propia configuración nunca se pierde.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: context.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              TapLoopButton(
                label: 'Editar plantilla',
                onPressed: templateMember == null ? null : onEditTemplate,
              ),
              OutlinedButton(
                onPressed: onChangeTemplate,
                child: const Text('Cambiar miembro plantilla'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SharedDesignEditor extends StatelessWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;

  const _SharedDesignEditor({required this.card, required this.onChanged});

  static const _colors = <Color>[
    Color(0xFF0D0D0D),
    AppColors.primary,
    Color(0xFF6C4FE8),
    Color(0xFF1A73E8),
    Color(0xFF1A8C4E),
    Color(0xFFD93025),
    Color(0xFF00ACC1),
    Color(0xFFF5A623),
  ];

  Color get _iconColor => card.iconColor;

  Color get _backgroundColor =>
      card.bgColor ??
      card.backgroundColorStart ??
      (card.themeStyle == CardThemeStyle.black
          ? const Color(0xFF111827)
          : Colors.white);

  Color get _backgroundEndColor =>
      card.bgColorEnd ?? card.backgroundColorEnd ?? card.primaryColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SharedConfigHeader(
          icon: Icons.palette_outlined,
          title: 'Configuración de diseño compartido',
          subtitle:
              'Este diseño se aplica a todos los perfiles de la organización. Las configuraciones individuales quedan reemplazadas mientras esté activo.',
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final controls = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SharedDesignSection(
                  title: 'Diseño del perfil',
                  subtitle:
                      'Define si todos los perfiles públicos usan el diseño clásico o moderno.',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SharedOptionChip(
                        label: 'Clásico',
                        selected:
                            card.profileDesign == CardProfileDesign.classic,
                        onTap: () => onChanged(
                          card.copyWith(
                            profileDesign: CardProfileDesign.classic,
                            layoutStyle:
                                CardProfileDesign.classic.compatibleLayoutStyle,
                          ),
                        ),
                      ),
                      _SharedOptionChip(
                        label: 'Moderno',
                        selected:
                            card.profileDesign == CardProfileDesign.modern,
                        onTap: () => onChanged(
                          card.copyWith(
                            profileDesign: CardProfileDesign.modern,
                            layoutStyle:
                                CardProfileDesign.modern.compatibleLayoutStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SharedDesignSection(
                  title: 'Identidad visual',
                  subtitle:
                      'Color principal para acciones y color personalizado para iconos.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sharedColorPicker(
                        context,
                        label: 'Color principal',
                        selectedColor: card.primaryColor,
                        onSelected: (color) =>
                            onChanged(card.copyWith(primaryColor: color)),
                      ),
                      const SizedBox(height: 18),
                      _sharedColorPicker(
                        context,
                        label: 'Color de iconos',
                        selectedColor: _iconColor,
                        onSelected: (color) =>
                            onChanged(card.copyWith(iconColor: color)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SharedDesignSection(
                  title: 'Fondo',
                  subtitle:
                      'Configura el fondo base que se utiliza cuando la portada no tiene imagen.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sharedColorPicker(
                        context,
                        label: 'Color de fondo',
                        selectedColor: _backgroundColor,
                        onSelected: (color) => onChanged(
                          card.copyWith(
                            backgroundColorStart: color,
                            bgColor: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _sharedColorPicker(
                        context,
                        label: 'Color final del fondo',
                        selectedColor: _backgroundEndColor,
                        onSelected: (color) => onChanged(
                          card.copyWith(
                            backgroundColorEnd: color,
                            bgColorEnd: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SharedDesignSection(
                  title: 'Fondo y portada sin imagen',
                  subtitle:
                      'Selecciona el tono general para perfiles sin portada personalizada.',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SharedOptionChip(
                        label: 'Blanco',
                        selected: card.themeStyle == CardThemeStyle.white,
                        onTap: () => onChanged(
                          card.copyWith(
                            themeStyle: CardThemeStyle.white,
                            backgroundColorStart: Colors.white,
                            backgroundColorEnd: _backgroundEndColor,
                            bgColor: Colors.white,
                            bgColorEnd: _backgroundEndColor,
                          ),
                        ),
                      ),
                      _SharedOptionChip(
                        label: 'Negro',
                        selected: card.themeStyle == CardThemeStyle.black,
                        onTap: () => onChanged(
                          card.copyWith(
                            themeStyle: CardThemeStyle.black,
                            backgroundColorStart: const Color(0xFF0D0D0D),
                            backgroundColorEnd: _backgroundEndColor,
                            bgColor: const Color(0xFF0D0D0D),
                            bgColorEnd: _backgroundEndColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SharedDesignSection(
                  title: 'Efecto de fondo',
                  subtitle:
                      'Aplica un efecto visual compartido para el fondo público.',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SharedOptionChip(
                        label: 'Sin efecto',
                        selected: card.bgStyle == CardBgStyle.plain,
                        onTap: () => onChanged(
                          card.copyWith(bgStyle: CardBgStyle.plain),
                        ),
                      ),
                      _SharedOptionChip(
                        label: 'Gradiente',
                        selected: card.bgStyle == CardBgStyle.gradient,
                        onTap: () => onChanged(
                          card.copyWith(bgStyle: CardBgStyle.gradient),
                        ),
                      ),
                      _SharedOptionChip(
                        label: 'Malla',
                        selected: card.bgStyle == CardBgStyle.mesh,
                        onTap: () =>
                            onChanged(card.copyWith(bgStyle: CardBgStyle.mesh)),
                      ),
                      _SharedOptionChip(
                        label: 'Rayas',
                        selected: card.bgStyle == CardBgStyle.stripes,
                        onTap: () => onChanged(
                          card.copyWith(bgStyle: CardBgStyle.stripes),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final preview = _SharedDesignPreview(
              card: card,
              backgroundColor: _backgroundColor,
              backgroundEndColor: _backgroundEndColor,
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [controls, const SizedBox(height: 24), preview],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: controls),
                const SizedBox(width: 28),
                Expanded(flex: 2, child: preview),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _sharedColorPicker(
    BuildContext context, {
    required String label,
    required Color selectedColor,
    required ValueChanged<Color> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _colors.map((color) {
            final selected = selectedColor == color;
            return InkWell(
              onTap: () => onSelected(color),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? context.textPrimary : context.borderColor,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SharedDesignSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SharedDesignSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HelpTitle(
          title: title,
          helpText: subtitle,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: context.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

class _SharedDesignPreview extends StatelessWidget {
  final DigitalCardModel card;
  final Color backgroundColor;
  final Color backgroundEndColor;

  const _SharedDesignPreview({
    required this.card,
    required this.backgroundColor,
    required this.backgroundEndColor,
  });

  @override
  Widget build(BuildContext context) {
    final dark = card.themeStyle == CardThemeStyle.black;
    final fg = dark ? Colors.white : const Color(0xFF101828);
    final muted = dark ? Colors.white70 : context.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista compartida',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 220,
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: _backgroundGradient(),
              color: backgroundColor,
            ),
            child: Align(
              alignment: card.profileDesign == CardProfileDesign.modern
                  ? Alignment.bottomLeft
                  : Alignment.center,
              child: Container(
                width: card.profileDesign == CardProfileDesign.modern
                    ? double.infinity
                    : 190,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.black.withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: card.primaryColor.withValues(alpha: 0.26),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      card.profileDesign == CardProfileDesign.modern
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: card.primaryColor.withValues(alpha: 0.12),
                        border: Border.all(color: card.primaryColor),
                      ),
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: card.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Perfil del equipo',
                      textAlign: card.profileDesign == CardProfileDesign.modern
                          ? TextAlign.left
                          : TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.profileDesign == CardProfileDesign.modern
                          ? 'Diseño moderno'
                          : 'Diseño clásico',
                      textAlign: card.profileDesign == CardProfileDesign.modern
                          ? TextAlign.left
                          : TextAlign.center,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 8,
                      width: 92,
                      decoration: BoxDecoration(
                        color: backgroundEndColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Gradient? _backgroundGradient() {
    return switch (card.bgStyle) {
      CardBgStyle.plain => null,
      CardBgStyle.gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [backgroundColor, backgroundEndColor],
      ),
      CardBgStyle.mesh => RadialGradient(
        center: Alignment.topLeft,
        radius: 1.45,
        colors: [
          backgroundEndColor.withValues(alpha: 0.9),
          backgroundColor,
          card.primaryColor.withValues(alpha: 0.48),
        ],
      ),
      CardBgStyle.stripes => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          backgroundColor,
          backgroundColor,
          backgroundEndColor.withValues(alpha: 0.62),
          backgroundEndColor.withValues(alpha: 0.62),
        ],
        stops: const [0, 0.48, 0.48, 1],
      ),
    };
  }
}

class _SharedFormsEditor extends StatefulWidget {
  final List<_AdminSmartForm> forms;
  final ValueChanged<List<_AdminSmartForm>> onChanged;

  const _SharedFormsEditor({required this.forms, required this.onChanged});

  @override
  State<_SharedFormsEditor> createState() => _SharedFormsEditorState();
}

class _SharedFormsEditorState extends State<_SharedFormsEditor> {
  late List<_AdminSmartForm> _forms;

  @override
  void initState() {
    super.initState();
    _forms = _AdminViewState._cloneAdminForms(widget.forms);
  }

  @override
  void didUpdateWidget(covariant _SharedFormsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forms != widget.forms) {
      _forms = _AdminViewState._cloneAdminForms(widget.forms);
    }
  }

  void _emit() => widget.onChanged(_AdminViewState._cloneAdminForms(_forms));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SharedConfigHeader(
          icon: Icons.dynamic_form_outlined,
          title: 'Configuración de formulario compartido',
          subtitle:
              'Estos formularios se usan en todos los perfiles de la organización mientras el formulario compartido esté activo.',
        ),
        const SizedBox(height: 12),
        ..._forms.asMap().entries.map((entry) {
          final index = entry.key;
          final form = entry.value;
          return Column(
            children: [
              _AdminFormRow(
                form: form,
                onToggle: (value) {
                  setState(() => form.enabled = value);
                  _emit();
                },
                onChanged: () {
                  setState(() {});
                  _emit();
                },
              ),
              if (index < _forms.length - 1)
                Divider(color: context.borderStrongSoft, height: 1),
            ],
          );
        }),
      ],
    );
  }
}

class _SharedIntegrationEditor extends StatefulWidget {
  final _AdminCalProvider? provider;
  final String? calendarUrl;
  final Future<void> Function({
    required _AdminCalProvider? provider,
    required String? url,
  })
  onChanged;

  const _SharedIntegrationEditor({
    required this.provider,
    required this.calendarUrl,
    required this.onChanged,
  });

  @override
  State<_SharedIntegrationEditor> createState() =>
      _SharedIntegrationEditorState();
}

class _SharedIntegrationEditorState extends State<_SharedIntegrationEditor> {
  late TextEditingController _urlCtrl;
  _AdminCalProvider? _provider;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider;
    _urlCtrl = TextEditingController(text: widget.calendarUrl ?? '');
  }

  @override
  void didUpdateWidget(covariant _SharedIntegrationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _provider = widget.provider;
    if (oldWidget.calendarUrl != widget.calendarUrl) {
      _urlCtrl.text = widget.calendarUrl ?? '';
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onChanged(provider: _provider, url: _urlCtrl.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SharedConfigHeader(
          icon: Icons.add_link_rounded,
          title: 'Configuración de integración compartida',
          subtitle:
              'Esta conexión externa reemplaza las integraciones individuales de todos los miembros de la organización.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _AdminCalProvider.values.map((provider) {
            return _SharedOptionChip(
              label: provider.label,
              selected: _provider == provider,
              onTap: () => setState(() => _provider = provider),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            hintText: _provider?.hint ?? 'https://calendario.com/tu-enlace',
            prefixIcon: const Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 180,
            child: TapLoopButton(
              label: _saving ? 'Guardando...' : 'Guardar',
              onPressed: _saving ? null : _save,
              height: 46,
            ),
          ),
        ),
      ],
    );
  }
}

class _SharedConfigHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SharedConfigHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HelpTitle(
                title: title,
                helpText: subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: context.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SharedOptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SharedOptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : context.bgCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : context.borderStrongSoft,
            width: 1.1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.primary : context.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TeamProfilesPanel extends StatelessWidget {
  final List<_AdminMember> members;
  final int activeCount;
  final int inactiveCount;
  final void Function(_AdminMember) onView;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;

  const _TeamProfilesPanel({
    super.key,
    required this.members,
    required this.activeCount,
    required this.inactiveCount,
    required this.onView,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
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
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 960;
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Perfiles del equipo',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Gestiona los perfiles digitales de tu equipo.',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  _ProfileCounterPill(
                    icon: Icons.badge_outlined,
                    value: members.length,
                    label: 'Perfiles',
                    color: AppColors.primary,
                  ),
                  _ProfileCounterPill(
                    icon: Icons.check_circle_outline_rounded,
                    value: activeCount,
                    label: 'Activos',
                    color: AppColors.success,
                  ),
                  _ProfileCounterPill(
                    icon: Icons.pause_circle_outline_rounded,
                    value: inactiveCount,
                    label: 'Inactivos',
                    color: context.textSecondary,
                  ),
                ],
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 18), actions],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: title),
                        actions,
                      ],
                    );
            },
          ),
          const SizedBox(height: 26),
          Divider(color: context.borderStrongSoft, height: 1),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 1120),
              child: Column(
                children: [
                  const _TeamProfilesHeader(),
                  Divider(color: context.borderStrongSoft, height: 28),
                  ...members.map(
                    (member) => _TeamProfileRow(
                      member: member,
                      onView: () => onView(member),
                      onEdit: () => onEdit(member),
                      onToggle: (enabled) => onToggle(member, enabled),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCounterPill extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;

  const _ProfileCounterPill({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Text(
            '$value',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamProfilesHeader extends StatelessWidget {
  const _TeamProfilesHeader();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.dmSans(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: context.textSecondary,
    );
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: HelpTitle(title: 'Miembro', style: style),
        ),
        SizedBox(
          width: 250,
          child: HelpTitle(title: 'Cargo / Empresa', style: style),
        ),
        SizedBox(
          width: 220,
          child: HelpTitle(title: 'Perfil público', style: style),
        ),
        SizedBox(
          width: 150,
          child: HelpTitle(title: 'Estado', style: style),
        ),
        SizedBox(
          width: 180,
          child: HelpTitle(title: 'Progreso', style: style),
        ),
        SizedBox(
          width: 300,
          child: HelpTitle(title: 'Acciones', style: style),
        ),
      ],
    );
  }
}

class _TeamProfileRow extends StatelessWidget {
  final _AdminMember member;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  const _TeamProfileRow({
    required this.member,
    required this.onView,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _profileCompletion(member.card);
    final isAdmin = member.isAdmin;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderStrongSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Row(
              children: [
                _AdminMemberAvatar(member: member, size: 58),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    member.card.name.trim().isNotEmpty
                        ? member.card.name
                        : member.member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.card.jobTitle.trim().isNotEmpty
                      ? member.card.jobTitle
                      : 'Sin cargo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${member.card.company.trim().isEmpty ? member.member.name : member.card.company} · ${member.member.email}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 220,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    member.card.publicUrl.replaceFirst('https://', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Icon(
                  member.isActive
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  size: 20,
                  color: member.isActive
                      ? AppColors.success
                      : context.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  member.isActive ? 'Activo' : 'Inactivo',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: member.isActive
                        ? AppColors.success
                        : context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 180,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: progress >= 0.8
                        ? AppColors.success
                        : context.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Completo ${(progress * 100).round()}%',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 300,
            child: Row(
              children: [
                _ProfileActionButton(
                  icon: Icons.visibility_outlined,
                  label: 'Ver',
                  onTap: onView,
                ),
                const SizedBox(width: 10),
                _ProfileActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Editar',
                  onTap: onEdit,
                ),
                const SizedBox(width: 10),
                Switch.adaptive(
                  value: member.isActive,
                  onChanged: isAdmin ? null : onToggle,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.32),
                  activeThumbColor: AppColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMemberAvatar extends StatelessWidget {
  final _AdminMember member;
  final double size;

  const _AdminMemberAvatar({required this.member, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = member.card.profilePhotoUrl ?? member.member.avatarUrl;
    final hasImage = url?.trim().isNotEmpty == true;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.bgCard,
        shape: BoxShape.circle,
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
        image: hasImage
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      child: hasImage
          ? null
          : Icon(
              Icons.person_outline_rounded,
              color: AppColors.primary,
              size: size * 0.46,
            ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.textPrimary,
        side: BorderSide(color: context.borderStrongSoft, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        textStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

double _profileCompletion(DigitalCardModel card) {
  final checks = [
    card.name.trim().isNotEmpty,
    card.jobTitle.trim().isNotEmpty,
    card.contactItems.any((item) => item.value.trim().isNotEmpty),
    card.socialLinks.any((link) => link.url.trim().isNotEmpty),
    card.smartForms.any((form) => form.isActive),
    card.calendarEnabled && (card.calendarUrl?.trim().isNotEmpty ?? false),
  ];
  return checks.where((value) => value).length / checks.length;
}

class _AdminSummaryStrip extends StatelessWidget {
  final int activeCount;
  final int totalCount;
  final int totalTaps;
  final int totalLeads;
  final int totalViews;
  final int totalClicks;

  const _AdminSummaryStrip({
    required this.activeCount,
    required this.totalCount,
    required this.totalTaps,
    required this.totalLeads,
    required this.totalViews,
    required this.totalClicks,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('$activeCount / $totalCount', 'Miembros activos', Icons.people_outlined),
      ('$totalViews', 'Vistas del equipo', Icons.visibility_outlined),
      ('$totalTaps', 'Taps del equipo', Icons.touch_app_outlined),
      ('$totalClicks', 'Clicks en enlace', Icons.ads_click_outlined),
      ('$totalLeads', 'Leads del equipo', Icons.bolt_outlined),
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: stats.asMap().entries.map((entry) {
          final s = entry.value;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(s.$3, size: 16, color: context.textSecondary),
                      const SizedBox(height: 6),
                      Text(
                        s.$1,
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.$2,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.key < stats.length - 1)
                  Container(width: 1, height: 42, color: context.borderColor),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AdminPerformancePanel extends StatelessWidget {
  final List<int> viewsSeries;
  final List<int> tapsSeries;
  final List<int> clicksSeries;

  const _AdminPerformancePanel({
    required this.viewsSeries,
    required this.tapsSeries,
    required this.clicksSeries,
  });

  @override
  Widget build(BuildContext context) {
    final hasData =
        viewsSeries.any((value) => value > 0) ||
        tapsSeries.any((value) => value > 0) ||
        clicksSeries.any((value) => value > 0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: 'Rendimiento del equipo',
            helpText:
                'Vista consolidada de vistas, taps y clics de los miembros activos.',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Vista consolidada de vistas, taps y clicks en enlaces de todos los miembros activos.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (!hasData)
            const EmptyDataState(
              hint: 'Aún no hay actividad del equipo registrada.',
            )
          else ...[
            _AdminTrendRow(
              label: 'Vistas',
              total: viewsSeries.fold(0, (a, b) => a + b),
              series: viewsSeries,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            _AdminTrendRow(
              label: 'Taps',
              total: tapsSeries.fold(0, (a, b) => a + b),
              series: tapsSeries,
              color: const Color(0xFF0F9D58),
            ),
            const SizedBox(height: 12),
            _AdminTrendRow(
              label: 'Clicks en enlace',
              total: clicksSeries.fold(0, (a, b) => a + b),
              series: clicksSeries,
              color: const Color(0xFFE67E22),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminTrendRow extends StatelessWidget {
  final String label;
  final int total;
  final List<int> series;
  final Color color;

  const _AdminTrendRow({
    required this.label,
    required this.total,
    required this.series,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = series.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '$total',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(series.length, (index) {
              final value = series[index];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == series.length - 1 ? 0 : 6,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: ((value / maxValue) * 48)
                                .clamp(4, 48)
                                .toDouble(),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _adminDayLabel(index),
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _AdminTeamHighlights extends StatelessWidget {
  final List<_AdminMember> members;

  const _AdminTeamHighlights({required this.members});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Highlights del equipo',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Miembros con mayor número de taps e interacción comercial.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (members.isEmpty)
            Text(
              'Sin miembros activos.',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            )
          else
            ...members
                .take(4)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: entry.key == 3 ? 0 : 12),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.bgPage,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value.member.name,
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                '${entry.value.member.taps} taps · ${entry.value.member.totalClicks} clicks · ${entry.value.member.leads} leads',
                                style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Desktop Grid ─────────────────────────────────────────────────────────────

class _DesktopMemberGrid extends StatelessWidget {
  final List<_AdminMember> members;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;
  const _DesktopMemberGrid({
    required this.members,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 128,
      ),
      itemCount: members.length,
      itemBuilder: (_, i) =>
          _MemberCard(member: members[i], onEdit: onEdit, onToggle: onToggle),
    );
  }
}

// ─── Mobile List ──────────────────────────────────────────────────────────────

class _MobileMembers extends StatelessWidget {
  final List<_AdminMember> members;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;
  const _MobileMembers({
    required this.members,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: members
          .map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MemberCard(member: m, onEdit: onEdit, onToggle: onToggle),
            ),
          )
          .toList(),
    );
  }
}

// ─── Member Card ──────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final _AdminMember member;
  final void Function(_AdminMember) onEdit;
  final void Function(_AdminMember, bool) onToggle;
  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final m = member.member;
    final isAdmin = member.isAdmin;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: member.isActive ? context.bgCard : context.bgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m.name,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: member.isActive
                        ? context.textPrimary
                        : context.textMuted,
                  ),
                ),
                Text(
                  m.jobTitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textSecondary,
                  ),
                ),
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Administrador',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${m.taps} taps · ${m.conversions} conv.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isAdmin ? () => onToggle(member, member.isActive) : null,
                child: AbsorbPointer(
                  absorbing: isAdmin,
                  child: Opacity(
                    opacity: isAdmin ? 0.55 : 1,
                    child: Switch.adaptive(
                      value: member.isActive,
                      onChanged: (v) => onToggle(member, v),
                      activeTrackColor: context.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              MouseRegion(
                cursor: isAdmin
                    ? SystemMouseCursors.forbidden
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => isAdmin
                      ? onToggle(member, member.isActive)
                      : onEdit(member),
                  child: Text(
                    'Editar',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isAdmin ? context.textMuted : context.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<int> _sumAdminSeries(List<List<int>> all) {
  final result = List.filled(7, 0);
  for (final series in all) {
    for (var i = 0; i < 7 && i < series.length; i++) {
      result[i] += series[i];
    }
  }
  return result;
}

String _adminDayLabel(int index) {
  const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  return labels[index % labels.length];
}

// ─── Admin Form Row ───────────────────────────────────────────────────────────

class _AdminFormRow extends StatefulWidget {
  final _AdminSmartForm form;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChanged;

  const _AdminFormRow({
    required this.form,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  State<_AdminFormRow> createState() => _AdminFormRowState();
}

class _AdminFormRowState extends State<_AdminFormRow> {
  bool _fieldsOpen = false;
  int? _editingIdx;
  final _addCtrl = TextEditingController();
  _AdminFieldType _addType = _AdminFieldType.text;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: form.enabled
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : context.bgSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  form.icon,
                  size: 18,
                  color: form.enabled ? AppColors.primary : context.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form.title,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: form.enabled
                            ? context.textPrimary
                            : context.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      form.description,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    if (form.enabled) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          _fieldsOpen = !_fieldsOpen;
                          if (!_fieldsOpen) _editingIdx = null;
                        }),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedRotation(
                              turns: _fieldsOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 15,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _fieldsOpen
                                  ? 'Ocultar campos'
                                  : 'Personalizar campos (${form.fields.length})',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: form.enabled,
                onChanged: (v) {
                  widget.onToggle(v);
                  if (!v) setState(() => _fieldsOpen = false);
                },
                activeTrackColor: AppColors.primary,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _fieldsOpen
              ? Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.bgSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Campos del formulario',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${form.fields.where((f) => f.required).length} obligatorios',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: context.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        onReorder: (oldIdx, newIdx) {
                          setState(() {
                            if (newIdx > oldIdx) newIdx--;
                            final item = form.fields.removeAt(oldIdx);
                            form.fields.insert(newIdx, item);
                            if (_editingIdx != null) {
                              if (_editingIdx == oldIdx) {
                                _editingIdx = newIdx;
                              } else if (oldIdx < _editingIdx! &&
                                  newIdx >= _editingIdx!) {
                                _editingIdx = _editingIdx! - 1;
                              } else if (oldIdx > _editingIdx! &&
                                  newIdx <= _editingIdx!) {
                                _editingIdx = _editingIdx! + 1;
                              }
                            }
                          });
                          widget.onChanged();
                        },
                        children: form.fields.asMap().entries.map((e) {
                          final idx = e.key;
                          final field = e.value;
                          final isEditing = _editingIdx == idx;
                          return Column(
                            key: ValueKey('af_${form.id}_$idx'),
                            children: [
                              GestureDetector(
                                onTap: () => setState(
                                  () => _editingIdx = isEditing ? null : idx,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: idx,
                                        child: Icon(
                                          Icons.drag_indicator,
                                          size: 15,
                                          color: context.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: field.type.color.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              field.type.icon,
                                              size: 10,
                                              color: field.type.color,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              field.type.label,
                                              style: GoogleFonts.dmSans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: field.type.color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          field.label,
                                          style: GoogleFonts.dmSans(
                                            fontSize: 12,
                                            color: context.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (field.required)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Req',
                                            style: GoogleFonts.dmSans(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ),
                                      AnimatedRotation(
                                        turns: isEditing ? 0.5 : 0,
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: Icon(
                                          Icons.expand_more_rounded,
                                          size: 14,
                                          color: context.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            form.fields.removeAt(idx);
                                            if (_editingIdx == idx) {
                                              _editingIdx = null;
                                            } else if (_editingIdx != null &&
                                                _editingIdx! > idx) {
                                              _editingIdx = _editingIdx! - 1;
                                            }
                                          });
                                          widget.onChanged();
                                        },
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: context.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeInOut,
                                child: isEditing
                                    ? Container(
                                        margin: const EdgeInsets.only(
                                          left: 20,
                                          bottom: 4,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: context.bgCard,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: context.borderColor,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tipo de campo',
                                              style: GoogleFonts.dmSans(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: context.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: _AdminFieldType.values.map((
                                                t,
                                              ) {
                                                final sel = field.type == t;
                                                return GestureDetector(
                                                  onTap: () => setState(
                                                    () => field.type = t,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: sel
                                                          ? t.color.withValues(
                                                              alpha: 0.15,
                                                            )
                                                          : context.bgSubtle,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: sel
                                                            ? t.color
                                                            : context
                                                                  .borderColor,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          t.icon,
                                                          size: 11,
                                                          color: sel
                                                              ? t.color
                                                              : context
                                                                    .textMuted,
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Text(
                                                          t.label,
                                                          style: GoogleFonts.dmSans(
                                                            fontSize: 10,
                                                            fontWeight: sel
                                                                ? FontWeight
                                                                      .w700
                                                                : FontWeight
                                                                      .w400,
                                                            color: sel
                                                                ? t.color
                                                                : context
                                                                      .textSecondary,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                            const SizedBox(height: 8),
                                            GestureDetector(
                                              onTap: () => setState(
                                                () => field.required =
                                                    !field.required,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    field.required
                                                        ? Icons
                                                              .check_box_rounded
                                                        : Icons
                                                              .check_box_outline_blank_rounded,
                                                    size: 15,
                                                    color: field.required
                                                        ? AppColors.primary
                                                        : context.textMuted,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Campo obligatorio',
                                                    style: GoogleFonts.dmSans(
                                                      fontSize: 12,
                                                      color:
                                                          context.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      Divider(color: context.borderColor, height: 16),
                      Text(
                        'Agregar campo',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: _AdminFieldType.values.map((t) {
                          final sel = _addType == t;
                          return GestureDetector(
                            onTap: () => setState(() => _addType = t),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: sel
                                    ? t.color.withValues(alpha: 0.15)
                                    : context.bgCard,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: sel ? t.color : context.borderColor,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    t.icon,
                                    size: 11,
                                    color: sel ? t.color : context.textMuted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    t.label,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 10,
                                      fontWeight: sel
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: sel
                                          ? t.color
                                          : context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addCtrl,
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: context.textPrimary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Nombre del campo...',
                                hintStyle: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: context.textMuted,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: context.borderColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: context.borderColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: context.bgCard,
                              ),
                              onSubmitted: (v) {
                                final val = v.trim();
                                if (val.isNotEmpty) {
                                  setState(() {
                                    form.fields.add(
                                      _AdminFormField(
                                        label: val,
                                        type: _addType,
                                      ),
                                    );
                                    _addCtrl.clear();
                                  });
                                  widget.onChanged();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final val = _addCtrl.text.trim();
                              if (val.isNotEmpty) {
                                setState(() {
                                  form.fields.add(
                                    _AdminFormField(label: val, type: _addType),
                                  );
                                  _addCtrl.clear();
                                });
                                widget.onChanged();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
