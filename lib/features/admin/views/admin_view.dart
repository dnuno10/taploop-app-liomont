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
import '../../../core/widgets/empty_data_state.dart';
import '../../../core/widgets/taploop_text_field.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../analytics/models/team_member_model.dart';
import '../../card/models/digital_card_model.dart';
import '../../card/models/contact_item_model.dart';
import '../../card/models/smart_form_model.dart';
import '../../card/models/social_link_model.dart';
import '../../card/utils/calendar_links.dart';
import '../../card/views/edit_card_view.dart';
import '../../card/widgets/digital_profile_preview.dart';

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

  const _TeamConsistencySettings({
    this.sharedDesign = false,
    this.sharedForms = false,
    this.sharedIntegrations = false,
  });

  factory _TeamConsistencySettings.fromOrg(Map<String, dynamic>? org) {
    return _TeamConsistencySettings(
      sharedDesign: org?['shared_design_enabled'] as bool? ?? false,
      sharedForms: org?['shared_forms_enabled'] as bool? ?? false,
      sharedIntegrations: org?['shared_integrations_enabled'] as bool? ?? false,
    );
  }

  _TeamConsistencySettings copyWith({
    bool? sharedDesign,
    bool? sharedForms,
    bool? sharedIntegrations,
  }) {
    return _TeamConsistencySettings(
      sharedDesign: sharedDesign ?? this.sharedDesign,
      sharedForms: sharedForms ?? this.sharedForms,
      sharedIntegrations: sharedIntegrations ?? this.sharedIntegrations,
    );
  }
}

enum _ConsistencyKind { design, forms, integrations }

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
    return Future.wait(
      teamMembers.asMap().entries.map((e) async {
        final i = e.key;
        final m = e.value;
        final fetchedCard = await AdminRepository.fetchCardForUser(m.id);
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
      }),
    );
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
            child: _EditMemberDialog(
              member: member,
              consistency: _consistency,
              onSave: _saveMember,
            ),
          ),
        ),
      );
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
            child: _EditMemberDialog(
              member: member,
              consistency: _consistency,
              scrollController: ctrl,
              onSave: _saveMember,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _saveMember(_AdminMember updated) async {
    try {
      await AdminRepository.saveAdminMember(
        card: updated.card,
        contacts: updated.card.contactItems,
        socialLinks: updated.card.socialLinks,
        smartForms: _smartFormsFromAdminForms(updated.card.id, updated.forms),
      );

      final cardIds = _allMemberCardIds();
      if (_consistency.sharedDesign) {
        await AdminRepository.applySharedDesign(
          sourceCard: updated.card,
          targetCardIds: cardIds,
        );
      }
      if (_consistency.sharedForms) {
        await AdminRepository.applySharedForms(
          sourceCardId: updated.card.id,
          targetCardIds: cardIds,
        );
      }
      if (_consistency.sharedIntegrations) {
        await AdminRepository.applySharedIntegrations(
          sourceCard: updated.card,
          targetCardIds: cardIds,
        );
      }

      if (!mounted) return;
      setState(() {
        final idx = _members.indexWhere(
          (m) => m.member.id == updated.member.id,
        );
        if (idx != -1) _members[idx] = updated;
      });
      TapLoopToast.show(
        context,
        'Perfil actualizado correctamente.',
        TapLoopToastType.success,
      );
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudieron guardar los cambios. Revisa la conexión e intenta de nuevo.',
        TapLoopToastType.error,
      );
      rethrow;
    }
  }

  List<String> _allMemberCardIds() {
    return _members
        .map((member) => member.card.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
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
    final source = _sourceMemberForSharedSettings();
    if (orgId == null || orgId.isEmpty || source == null) return;
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
      );
      if (enabled) {
        final cardIds = _allMemberCardIds();
        switch (kind) {
          case _ConsistencyKind.design:
            await AdminRepository.applySharedDesign(
              sourceCard: source.card,
              targetCardIds: cardIds,
            );
            break;
          case _ConsistencyKind.forms:
            await AdminRepository.applySharedForms(
              sourceCardId: source.card.id,
              targetCardIds: cardIds,
            );
            break;
          case _ConsistencyKind.integrations:
            await AdminRepository.applySharedIntegrations(
              sourceCard: source.card,
              targetCardIds: cardIds,
            );
            break;
        }
      }
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

  Future<void> _updateSharedDesign(DigitalCardModel sourceCard) async {
    final cardIds = _allMemberCardIds();
    if (cardIds.isEmpty) return;
    setState(() {
      _members = _members.map((member) {
        return _copyMemberWithCard(
          member,
          member.card.copyWith(
            themeStyle: sourceCard.themeStyle,
            primaryColor: sourceCard.primaryColor,
            iconColor: sourceCard.iconColor,
            backgroundColorStart: sourceCard.backgroundColorStart,
            backgroundColorEnd: sourceCard.backgroundColorEnd,
            profileDesign: sourceCard.profileDesign,
            layoutStyle: sourceCard.profileDesign.compatibleLayoutStyle,
            bgStyle: sourceCard.bgStyle,
            bgColor: sourceCard.bgColor,
            bgColorEnd: sourceCard.bgColorEnd,
            showVerifiedBadge: sourceCard.showVerifiedBadge,
          ),
        );
      }).toList();
    });
    try {
      await AdminRepository.applySharedDesign(
        sourceCard: sourceCard,
        targetCardIds: cardIds,
      );
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo guardar el diseño compartido.',
        TapLoopToastType.error,
      );
    }
  }

  Future<void> _updateSharedForms(List<_AdminSmartForm> forms) async {
    final source = _sourceMemberForSharedSettings();
    if (source == null) return;
    setState(() {
      _members = _members
          .map(
            (member) => _copyMemberWithForms(member, _cloneAdminForms(forms)),
          )
          .toList();
    });
    try {
      await AdminRepository.applySharedForms(
        sourceCardId: source.card.id,
        targetCardIds: _allMemberCardIds(),
      );
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo guardar el formulario compartido.',
        TapLoopToastType.error,
      );
    }
  }

  Future<void> _updateSharedIntegration({
    required _AdminCalProvider? provider,
    required String? url,
  }) async {
    final source = _sourceMemberForSharedSettings();
    if (source == null) return;
    final cleanUrl = url?.trim() ?? '';
    final nextCard = source.card.copyWith(
      calendarEnabled: provider != null && cleanUrl.isNotEmpty,
      calendarUrl: cleanUrl,
    );
    setState(() {
      _members = _members.map((member) {
        return _AdminMember(
          member: member.member,
          card: member.card.copyWith(
            calendarEnabled: nextCard.calendarEnabled,
            calendarUrl: nextCard.calendarUrl,
          ),
          isActive: member.isActive,
          forms: member.forms,
          calendarProvider: provider,
          calendarioUrl: _firstCalendarUrlFromStored(cleanUrl),
          customIntegrationLabel: parseCustomCalendarLabel(cleanUrl),
        );
      }).toList();
    });
    try {
      await AdminRepository.applySharedIntegrations(
        sourceCard: nextCard,
        targetCardIds: _allMemberCardIds(),
      );
    } catch (_) {
      if (!mounted) return;
      TapLoopToast.show(
        context,
        'No se pudo guardar la integración compartida.',
        TapLoopToastType.error,
      );
    }
  }

  static _AdminMember _copyMemberWithCard(
    _AdminMember member,
    DigitalCardModel card, {
    _AdminCalProvider? calendarProvider,
    String? calendarioUrl,
    String? customIntegrationLabel,
  }) {
    return _AdminMember(
      member: member.member,
      card: card,
      isActive: member.isActive,
      forms: member.forms,
      calendarProvider: calendarProvider ?? member.calendarProvider,
      calendarioUrl: calendarioUrl ?? member.calendarioUrl,
      customIntegrationLabel:
          customIntegrationLabel ?? member.customIntegrationLabel,
    );
  }

  static _AdminMember _copyMemberWithForms(
    _AdminMember member,
    List<_AdminSmartForm> forms,
  ) {
    return _AdminMember(
      member: member.member,
      card: member.card,
      isActive: member.isActive,
      forms: forms,
      calendarProvider: member.calendarProvider,
      calendarioUrl: member.calendarioUrl,
      customIntegrationLabel: member.customIntegrationLabel,
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

  static List<SmartFormModel> _smartFormsFromAdminForms(
    String cardId,
    List<_AdminSmartForm> forms,
  ) {
    return forms.where((form) => form.enabled).map((form) {
      final includedFields = _includedFieldsFromAdminFields(form.fields);
      return SmartFormModel(
        id: form.id.startsWith('form_') || form.id.length > 20 ? form.id : '',
        cardId: cardId,
        name: form.title,
        description: form.description,
        isActive: form.enabled,
        includedFields: includedFields.isEmpty
            ? const [SmartFormIncludedField.name, SmartFormIncludedField.email]
            : includedFields,
      );
    }).toList();
  }

  static List<SmartFormIncludedField> _includedFieldsFromAdminFields(
    List<_AdminFormField> fields,
  ) {
    final selected = <SmartFormIncludedField>{};
    for (final field in fields) {
      final label = field.label.toLowerCase();
      if (label.contains('nombre')) selected.add(SmartFormIncludedField.name);
      if (label.contains('correo') ||
          label.contains('email') ||
          field.type == _AdminFieldType.email) {
        selected.add(SmartFormIncludedField.email);
      }
      if (label.contains('tel') ||
          label.contains('whatsapp') ||
          field.type == _AdminFieldType.phone) {
        selected.add(SmartFormIncludedField.phone);
      }
      if (label.contains('empresa')) {
        selected.add(SmartFormIncludedField.company);
      }
      if (label.contains('mensaje') ||
          label.contains('descrip') ||
          field.type == _AdminFieldType.textarea) {
        selected.add(SmartFormIncludedField.message);
      }
      if (label.contains('presupuesto')) {
        selected.add(SmartFormIncludedField.budget);
      }
      if (label.contains('fecha')) selected.add(SmartFormIncludedField.date);
    }
    return smartFormIncludedFieldOrder
        .where((field) => selected.contains(field))
        .toList();
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
                    sourceMember: _sourceMemberForSharedSettings(),
                    onToggle: _toggleConsistency,
                    onSelectKind: (kind) {
                      setState(() => _expandedConsistencyKind = kind);
                    },
                    onDesignChanged: _updateSharedDesign,
                    onFormsChanged: _updateSharedForms,
                    onIntegrationChanged: _updateSharedIntegration,
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
        Text(
          company,
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
  final _AdminMember? sourceMember;
  final Future<void> Function({
    required _ConsistencyKind kind,
    required bool enabled,
  })
  onToggle;
  final ValueChanged<_ConsistencyKind> onSelectKind;
  final ValueChanged<DigitalCardModel> onDesignChanged;
  final ValueChanged<List<_AdminSmartForm>> onFormsChanged;
  final Future<void> Function({
    required _AdminCalProvider? provider,
    required String? url,
  })
  onIntegrationChanged;

  const _TeamConsistencyPanel({
    required this.settings,
    required this.syncing,
    required this.expandedKind,
    required this.sourceMember,
    required this.onToggle,
    required this.onSelectKind,
    required this.onDesignChanged,
    required this.onFormsChanged,
    required this.onIntegrationChanged,
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
          Text(
            'Consistencia del equipo',
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
          if (expandedKind != null && sourceMember != null) ...[
            const SizedBox(height: 24),
            _SharedConfigurationSurface(
              kind: expandedKind!,
              member: sourceMember!,
              onDesignChanged: onDesignChanged,
              onFormsChanged: onFormsChanged,
              onIntegrationChanged: onIntegrationChanged,
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
                      Text(
                        item.title,
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

class _SharedConfigurationSurface extends StatelessWidget {
  final _ConsistencyKind kind;
  final _AdminMember member;
  final ValueChanged<DigitalCardModel> onDesignChanged;
  final ValueChanged<List<_AdminSmartForm>> onFormsChanged;
  final Future<void> Function({
    required _AdminCalProvider? provider,
    required String? url,
  })
  onIntegrationChanged;

  const _SharedConfigurationSurface({
    required this.kind,
    required this.member,
    required this.onDesignChanged,
    required this.onFormsChanged,
    required this.onIntegrationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderStrongSoft, width: 1.1),
      ),
      child: switch (kind) {
        _ConsistencyKind.design => SharedProfileDesignEditor(
          card: member.card,
          onChanged: onDesignChanged,
        ),
        _ConsistencyKind.forms => SharedProfileFormsEditor(
          cardId: member.card.id,
          onFormsChanged: (forms) =>
              onFormsChanged(_AdminViewState._adminFormsFromSmartForms(forms)),
        ),
        _ConsistencyKind.integrations => SharedProfileIntegrationsEditor(
          calendarEnabled: member.card.calendarEnabled,
          calendarUrl: member.card.calendarUrl,
          onChanged: (enabled, url) => onIntegrationChanged(
            provider: enabled ? _AdminViewState._providerFromUrl(url) : null,
            url: enabled ? url : null,
          ),
        ),
      },
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
        Text(
          title,
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
              Text(
                title,
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
        SizedBox(width: 260, child: Text('Miembro', style: style)),
        SizedBox(width: 250, child: Text('Cargo / Empresa', style: style)),
        SizedBox(width: 220, child: Text('Perfil público', style: style)),
        SizedBox(width: 150, child: Text('Estado', style: style)),
        SizedBox(width: 180, child: Text('Progreso', style: style)),
        SizedBox(width: 300, child: Text('Acciones', style: style)),
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

class _AdminEditSharedLockState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AdminEditSharedLockState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: context.textSecondary,
                          height: 1.45,
                        ),
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
          Text(
            'Rendimiento del equipo',
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

// ─── Edit Member Dialog / Sheet ───────────────────────────────────────────────

class _EditMemberDialog extends StatefulWidget {
  final _AdminMember member;
  final _TeamConsistencySettings consistency;
  final Future<void> Function(_AdminMember) onSave;
  final ScrollController? scrollController;
  const _EditMemberDialog({
    required this.member,
    required this.consistency,
    required this.onSave,
    this.scrollController,
  });

  @override
  State<_EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends State<_EditMemberDialog>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _companyCtrl;
  late DigitalCardModel _card;
  late List<TextEditingController> _contactCtrls;
  late List<TextEditingController> _contactLabelCtrls;
  late List<TextEditingController> _socialCtrls;
  late List<TextEditingController> _socialLabelCtrls;
  late List<_AdminSmartForm> _forms;
  _AdminCalProvider? _calProvider;
  late TextEditingController _calUrlCtrl;
  late TextEditingController _calLabelCtrl;
  bool _saving = false;

  static const _preferredColors = <Color>[
    Color(0xFF0D0D0D),
    AppColors.primary,
    Color(0xFF6C4FE8),
    Color(0xFF1A73E8),
    Color(0xFF1A8C4E),
    Color(0xFFD93025),
    Color(0xFF00ACC1),
    Color(0xFFF5A623),
  ];

  static const _steps = <_AdminEditStepData>[
    _AdminEditStepData('Perfil', Icons.person_outline_rounded),
    _AdminEditStepData('Contacto', Icons.call_outlined),
    _AdminEditStepData('Redes', Icons.alternate_email_rounded),
    _AdminEditStepData('Diseño', Icons.palette_outlined),
    _AdminEditStepData('Formularios', Icons.description_outlined),
    _AdminEditStepData('Calendario', Icons.calendar_today_outlined),
  ];

  int get _stepIndex => _tabController.index;
  bool get _unsaved => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _card = widget.member.card;
    _nameCtrl = TextEditingController(text: _card.name);
    _titleCtrl = TextEditingController(text: _card.jobTitle);
    _bioCtrl = TextEditingController(text: _card.bio ?? '');
    _companyCtrl = TextEditingController(text: _card.company);
    _contactCtrls = _card.contactItems
        .map((c) => TextEditingController(text: c.value))
        .toList();
    _contactLabelCtrls = _card.contactItems
        .map((c) => TextEditingController(text: c.label ?? ''))
        .toList();
    _socialCtrls = _card.socialLinks
        .map((s) => TextEditingController(text: s.url))
        .toList();
    _socialLabelCtrls = _card.socialLinks
        .map((s) => TextEditingController(text: s.customLabel ?? ''))
        .toList();
    // Deep-copy forms so cancelling dialog doesn't mutate originals
    _forms = widget.member.forms
        .map(
          (f) => _AdminSmartForm(
            id: f.id,
            title: f.title,
            description: f.description,
            icon: f.icon,
            enabled: f.enabled,
            fields: f.fields
                .map(
                  (fld) => _AdminFormField(
                    label: fld.label,
                    type: fld.type,
                    required: fld.required,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    _calProvider = widget.member.calendarProvider;
    _calUrlCtrl = TextEditingController(
      text: widget.member.calendarioUrl ?? '',
    );
    _calLabelCtrl = TextEditingController(
      text: widget.member.customIntegrationLabel ?? 'Otra integración',
    );
    _nameCtrl.addListener(_updateCard);
    _titleCtrl.addListener(_updateCard);
    _bioCtrl.addListener(_updateCard);
  }

  void _updateCard() {
    setState(() {
      _card = _card.copyWith(
        name: _nameCtrl.text,
        jobTitle: _titleCtrl.text,
        bio: _bioCtrl.text,
      );
    });
  }

  void _goToStep(int index) {
    _tabController.animateTo(index);
    setState(() {});
  }

  void _prevStep() {
    if (_stepIndex > 0) {
      _goToStep(_stepIndex - 1);
    }
  }

  void _nextStep() {
    if (_stepIndex < _steps.length - 1) {
      _goToStep(_stepIndex + 1);
    }
  }

  List<bool> _stepCompletion() {
    return [
      _nameCtrl.text.trim().isNotEmpty && _titleCtrl.text.trim().isNotEmpty,
      _card.contactItems.any((item) => item.value.trim().isNotEmpty),
      _card.socialLinks.any((item) => item.url.trim().isNotEmpty),
      true,
      widget.consistency.sharedForms || _forms.any((form) => form.enabled),
      widget.consistency.sharedIntegrations ||
          (_calProvider != null && _calUrlCtrl.text.trim().isNotEmpty),
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    final calendarUrl = _calUrlCtrl.text.trim();
    final storedCalendarUrl = _AdminViewState._encodeAdminCalendarUrl(
      provider: _calProvider,
      url: calendarUrl,
      customLabel: _calLabelCtrl.text,
    );
    final enabledFormIds = _forms
        .where((form) => form.enabled)
        .map((form) => form.id)
        .toList();
    final nextCard = _card.copyWith(
      enabledForms: enabledFormIds,
      calendarEnabled: _calProvider != null && calendarUrl.isNotEmpty,
      calendarUrl: storedCalendarUrl,
      contactItems: _card.contactItems,
      socialLinks: _card.socialLinks,
    );
    final updated = _AdminMember(
      member: widget.member.member,
      card: nextCard,
      isActive: widget.member.isActive,
      forms: _forms,
      calendarProvider: _calProvider,
      calendarioUrl: calendarUrl.isEmpty ? null : calendarUrl,
      customIntegrationLabel: _calLabelCtrl.text.trim().isEmpty
          ? 'Otra integración'
          : _calLabelCtrl.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await widget.onSave(updated);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _bioCtrl.dispose();
    _companyCtrl.dispose();
    _calUrlCtrl.dispose();
    _calLabelCtrl.dispose();
    for (final c in _contactCtrls) {
      c.dispose();
    }
    for (final c in _contactLabelCtrls) {
      c.dispose();
    }
    for (final c in _socialCtrls) {
      c.dispose();
    }
    for (final c in _socialLabelCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDialog = widget.scrollController == null;
    final stepCompletion = _stepCompletion();
    final stepProgress = (_stepIndex + 1) / _steps.length;

    Widget contentScroll({ScrollController? controller}) {
      return SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(24),
        child: _buildTabContent(_stepIndex),
      );
    }

    Widget topHeader = Container(
      color: context.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Editar miembro',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              if (_unsaved) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Paso ${_stepIndex + 1} de ${_steps.length}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _steps[_stepIndex].label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _steps[_stepIndex].icon,
                size: 16,
                color: context.textSecondary,
              ),
              const Spacer(),
              _AdminStepNavButton(
                icon: Icons.arrow_back_rounded,
                enabled: _stepIndex > 0,
                onTap: _prevStep,
              ),
              const SizedBox(width: 6),
              _AdminStepNavButton(
                icon: Icons.arrow_forward_rounded,
                enabled: _stepIndex < _steps.length - 1,
                onTap: _nextStep,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            minHeight: 5,
            value: stepProgress,
            color: AppColors.primary,
            backgroundColor: context.borderColor,
          ),
        ],
      ),
    );

    if (isDialog) {
      return Column(
        children: [
          topHeader,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: _AdminVerticalStepRail(
                    steps: _steps,
                    completedSteps: stepCompletion,
                    currentIndex: _stepIndex,
                    onTap: _goToStep,
                  ),
                ),
                Container(width: 1, color: context.borderColor),
                Expanded(child: contentScroll()),
                Container(width: 1, color: context.borderColor),
                SizedBox(width: 320, child: _AdminPreviewPanel(card: _card)),
              ],
            ),
          ),
          Container(height: 1, color: context.borderColor),
          _AdminBottomStepNav(
            currentIndex: _stepIndex,
            totalSteps: _steps.length,
            onPrev: _prevStep,
            onNext: _nextStep,
            onSave: _save,
            saving: _saving,
          ),
        ],
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        topHeader,
        _AdminHorizontalStepSelector(
          steps: _steps,
          completedSteps: stepCompletion,
          currentIndex: _stepIndex,
          onTap: _goToStep,
        ),
        Divider(color: context.borderColor, height: 1),
        Expanded(child: contentScroll(controller: widget.scrollController)),
        Container(height: 1, color: context.borderColor),
        _AdminBottomStepNav(
          currentIndex: _stepIndex,
          totalSteps: _steps.length,
          onPrev: _prevStep,
          onNext: _nextStep,
          onSave: _save,
          saving: _saving,
        ),
      ],
    );
  }

  Widget _buildTabContent(int idx) {
    switch (idx) {
      case 0:
        return _buildPerfilTab();
      case 1:
        return _buildContactoTab();
      case 2:
        return _buildRedesTab();
      case 3:
        if (widget.consistency.sharedDesign) {
          return const _AdminEditSharedLockState(
            icon: Icons.palette_outlined,
            title: 'Diseño compartido activo',
            message:
                'El diseño se gestiona desde Consistencia del equipo y se aplica a todos los miembros.',
          );
        }
        return _buildDisenoTab();
      case 4:
        if (widget.consistency.sharedForms) {
          return const _AdminEditSharedLockState(
            icon: Icons.assignment_outlined,
            title: 'Formulario compartido activo',
            message:
                'Los formularios se gestionan desde Consistencia del equipo y se aplican a todos los miembros.',
          );
        }
        return _buildFormulariosTab();
      case 5:
        if (widget.consistency.sharedIntegrations) {
          return const _AdminEditSharedLockState(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Integración compartida activa',
            message:
                'Las integraciones se gestionan desde Consistencia del equipo y reemplazan la configuración individual.',
          );
        }
        return _buildCalendarioTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPerfilTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapLoopTextField(
          label: 'Nombre',
          controller: _nameCtrl,
          hint: 'Nombre completo',
        ),
        const SizedBox(height: 16),
        TapLoopTextField(
          label: 'Cargo',
          controller: _titleCtrl,
          hint: 'Cargo o puesto',
        ),
        const SizedBox(height: 16),
        TapLoopTextField(
          label: 'Empresa',
          controller: _companyCtrl,
          hint: 'Empresa',
          enabled: false,
        ),
        const SizedBox(height: 16),
        TapLoopTextField(
          label: 'Bio / Descripción',
          controller: _bioCtrl,
          hint: 'Una breve descripción profesional...',
          maxLines: 3,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildContactoTab() {
    final contacts = _card.contactItems;
    return _adminStepPageShell(
      title: 'Contacto',
      subtitle:
          '${contacts.where((c) => c.isVisible).length} de ${contacts.length} visibles',
      action: TapLoopButton(
        label: 'Añadir',
        width: 120,
        height: 38,
        icon: const Icon(Icons.add_rounded, size: 16),
        onPressed: _addContact,
      ),
      child: contacts.isEmpty
          ? const _AdminEditEmptyState(
              message: 'Sin información de contacto',
              hint: 'Añade teléfono, correo o sitio web del miembro.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildContactEditors(),
                const SizedBox(height: 12),
                Text(
                  'Activa Visible para mostrar el dato en la tarjeta del miembro.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRedesTab() {
    final socials = _card.socialLinks;
    return _adminStepPageShell(
      title: 'Redes sociales',
      subtitle:
          '${socials.where((s) => s.isVisible).length} de ${socials.length} visibles',
      action: TapLoopButton(
        label: 'Añadir',
        width: 120,
        height: 38,
        icon: const Icon(Icons.add_rounded, size: 16),
        onPressed: _addSocial,
      ),
      child: socials.isEmpty
          ? const _AdminEditEmptyState(
              message: 'Sin redes sociales',
              hint: 'Añade LinkedIn, Instagram u otros enlaces del miembro.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildSocialEditors(),
                const SizedBox(height: 12),
                Text(
                  'Los enlaces marcados como visibles aparecerán en la tarjeta.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDisenoTab() {
    final stylePreviews = [
      (CardThemeStyle.white, 'Blanco'),
      (CardThemeStyle.black, 'Negro'),
    ];
    final designOptions = [
      (CardProfileDesign.classic, 'Clásico'),
      (CardProfileDesign.modern, 'Moderno'),
    ];
    return _adminStepPageShell(
      title: 'Diseño',
      subtitle: 'Ajusta estilo, layout y color principal de la tarjeta.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Color preferido'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _preferredColors.map((c) {
              final selected = _card.primaryColor == c;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _card = _card.copyWith(primaryColor: c)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.textPrimary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Estilo de tarjeta'),
          const SizedBox(height: 8),
          Text(
            'Selecciona el tono visual que mejor representa a este miembro.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stylePreviews.map((s) {
              final selected = _card.themeStyle == s.$1;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _card = _card.copyWith(themeStyle: s.$1)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? context.textPrimary : context.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.textPrimary
                            : context.borderColor,
                      ),
                    ),
                    child: Text(
                      s.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? (context.isDark ? Colors.black : Colors.white)
                            : context.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Diseño del perfil'),
          const SizedBox(height: 8),
          Text(
            'Define si el perfil público usa el diseño clásico o moderno.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: designOptions.map((opt) {
              final selected = _card.profileDesign == opt.$1;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(
                    () => _card = _card.copyWith(
                      profileDesign: opt.$1,
                      layoutStyle: opt.$1.compatibleLayoutStyle,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? context.textPrimary : context.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.textPrimary
                            : context.borderColor,
                      ),
                    ),
                    child: Text(
                      opt.$2,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? (context.isDark ? Colors.black : Colors.white)
                            : context.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulariosTab() {
    final active = _forms.where((f) => f.enabled).length;
    return _adminStepPageShell(
      title: 'Formularios inteligentes',
      subtitle: '$active activos · cada uno crea un lead',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._forms.asMap().entries.map((e) {
            final i = e.key;
            final form = e.value;
            return Column(
              children: [
                _AdminFormRow(
                  form: form,
                  onToggle: (v) => setState(() => form.enabled = v),
                  onChanged: () => setState(() {}),
                ),
                if (i < _forms.length - 1)
                  Divider(color: context.borderColor, height: 1),
              ],
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cada formulario completado crea un lead en el pipeline del miembro.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.primary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarioTab() {
    return _adminStepPageShell(
      title: 'Calendario de reuniones',
      subtitle:
          'Conecta el calendario para que los prospectos agenden directamente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Plataforma'),
          const SizedBox(height: 12),
          ...List.generate(_AdminCalProvider.values.length, (i) {
            final provider = _AdminCalProvider.values[i];
            final selected = _calProvider == provider;
            return GestureDetector(
              onTap: () => setState(() {
                _calProvider = provider;
                if (provider == _AdminCalProvider.custom &&
                    _calLabelCtrl.text.trim().isEmpty) {
                  _calLabelCtrl.text = 'Otra integración';
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : context.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.primary : context.borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      provider.icon,
                      size: 18,
                      color: selected
                          ? AppColors.primary
                          : context.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.label,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: selected
                              ? AppColors.primary
                              : context.textPrimary,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                  ],
                ),
              ),
            );
          }),
          if (_calProvider != null) ...[
            const SizedBox(height: 16),
            if (_calProvider == _AdminCalProvider.custom) ...[
              _sectionTitle('Etiqueta visible'),
              const SizedBox(height: 10),
              TextField(
                controller: _calLabelCtrl,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Ej. Demo personalizada, WhatsApp, CRM',
                  hintStyle: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: context.textMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  filled: true,
                  fillColor: context.bgInput,
                ),
              ),
              const SizedBox(height: 16),
            ],
            _sectionTitle('URL del calendario'),
            const SizedBox(height: 10),
            TextField(
              controller: _calUrlCtrl,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: _calProvider!.hint,
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: context.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: context.bgInput,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Esta URL aparecerá en la tarjeta digital del miembro.',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color: context.textMuted,
                height: 1.5,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Selecciona una plataforma para configurar el enlace del calendario.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Text(
      label,
      style: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: context.textPrimary,
      ),
    );
  }

  Widget _adminStepPageShell({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: context.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (action != null) ...[const SizedBox(width: 16), action],
                ],
              ),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContactEditors() {
    if (_card.contactItems.isEmpty) {
      return [
        Text(
          'Sin contactos todavía.',
          style: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
        ),
      ];
    }

    return _card.contactItems.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Contacto ${i + 1}',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _removeContact(i),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label: const Text('Eliminar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ContactType>(
                initialValue: item.type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: ContactType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(_contactTypeLabel(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _replaceContact(i, item.copyWith(type: v));
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactCtrls[i],
                decoration: const InputDecoration(labelText: 'Valor'),
                onChanged: (v) => _replaceContact(i, item.copyWith(value: v)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactLabelCtrls[i],
                decoration: const InputDecoration(
                  labelText: 'Etiqueta personalizada (opcional)',
                  hintText: 'Ej: Trabajo, Personal…',
                ),
                onChanged: (v) => _replaceContact(
                  i,
                  item.copyWith(label: v.trim().isEmpty ? null : v.trim()),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Switch.adaptive(
                    value: item.isVisible,
                    onChanged: (v) =>
                        _replaceContact(i, item.copyWith(isVisible: v)),
                    activeTrackColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.isVisible
                        ? 'Visible en la tarjeta'
                        : 'Oculto en la tarjeta',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: item.isVisible
                          ? context.textPrimary
                          : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildSocialEditors() {
    if (_card.socialLinks.isEmpty) {
      return [
        Text(
          'Sin redes todavía.',
          style: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
        ),
      ];
    }

    return _card.socialLinks.asMap().entries.map((entry) {
      final i = entry.key;
      final link = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Red ${i + 1}',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _removeSocial(i),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label: const Text('Eliminar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SocialPlatform>(
                initialValue: link.platform,
                decoration: const InputDecoration(labelText: 'Red'),
                items: SocialPlatform.values
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(_socialPlatformLabel(p)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _replaceSocial(i, link.copyWith(platform: v));
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _socialCtrls[i],
                decoration: const InputDecoration(labelText: 'URL'),
                onChanged: (v) => _replaceSocial(i, link.copyWith(url: v)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _socialLabelCtrls[i],
                decoration: const InputDecoration(
                  labelText: 'Etiqueta personalizada (opcional)',
                  hintText: 'Ej: Mi LinkedIn, Portafolio…',
                ),
                onChanged: (v) => _replaceSocial(
                  i,
                  link.copyWith(
                    customLabel: v.trim().isEmpty ? null : v.trim(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Switch.adaptive(
                    value: link.isVisible,
                    onChanged: (v) =>
                        _replaceSocial(i, link.copyWith(isVisible: v)),
                    activeTrackColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    link.isVisible
                        ? 'Visible en la tarjeta'
                        : 'Oculta en la tarjeta',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: link.isVisible
                          ? context.textPrimary
                          : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _addContact() {
    final item = ContactItemModel(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      type: ContactType.phone,
      value: '',
    );
    setState(() {
      _contactCtrls.add(TextEditingController());
      _contactLabelCtrls.add(TextEditingController());
      _card = _card.copyWith(contactItems: [..._card.contactItems, item]);
    });
  }

  void _removeContact(int index) {
    setState(() {
      _contactCtrls[index].dispose();
      _contactCtrls.removeAt(index);
      _contactLabelCtrls[index].dispose();
      _contactLabelCtrls.removeAt(index);
      final updated = [..._card.contactItems]..removeAt(index);
      _card = _card.copyWith(contactItems: updated);
    });
  }

  void _replaceContact(int index, ContactItemModel item) {
    setState(() {
      final updated = [..._card.contactItems];
      updated[index] = item;
      _card = _card.copyWith(contactItems: updated);
    });
  }

  void _addSocial() {
    final link = SocialLinkModel(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      platform: SocialPlatform.linkedin,
      url: '',
    );
    setState(() {
      _socialCtrls.add(TextEditingController());
      _socialLabelCtrls.add(TextEditingController());
      _card = _card.copyWith(socialLinks: [..._card.socialLinks, link]);
    });
  }

  void _removeSocial(int index) {
    setState(() {
      _socialCtrls[index].dispose();
      _socialCtrls.removeAt(index);
      _socialLabelCtrls[index].dispose();
      _socialLabelCtrls.removeAt(index);
      final updated = [..._card.socialLinks]..removeAt(index);
      _card = _card.copyWith(socialLinks: updated);
    });
  }

  void _replaceSocial(int index, SocialLinkModel item) {
    setState(() {
      final updated = [..._card.socialLinks];
      updated[index] = item;
      _card = _card.copyWith(socialLinks: updated);
    });
  }

  String _contactTypeLabel(ContactType type) => switch (type) {
    ContactType.phone => 'Teléfono',
    ContactType.whatsapp => 'WhatsApp',
    ContactType.email => 'Email',
    ContactType.address => 'Dirección',
    ContactType.website => 'Sitio web',
  };

  String _socialPlatformLabel(SocialPlatform platform) => switch (platform) {
    SocialPlatform.linkedin => 'LinkedIn',
    SocialPlatform.instagram => 'Instagram',
    SocialPlatform.facebook => 'Facebook',
    SocialPlatform.tiktok => 'TikTok',
    SocialPlatform.twitter => 'X / Twitter',
    SocialPlatform.youtube => 'YouTube',
    SocialPlatform.whatsapp => 'WhatsApp',
    SocialPlatform.calendly => 'Calendly',
    SocialPlatform.github => 'GitHub',
    SocialPlatform.custom => 'Enlace',
  };
}

class _AdminEditStepData {
  final String label;
  final IconData icon;

  const _AdminEditStepData(this.label, this.icon);
}

class _AdminEditEmptyState extends StatelessWidget {
  final String message;
  final String hint;

  const _AdminEditEmptyState({required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: context.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminStepNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _AdminStepNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.08)
                : context.bgPage,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : context.borderColor,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.primary : context.textMuted,
          ),
        ),
      ),
    );
  }
}

class _AdminHorizontalStepSelector extends StatelessWidget {
  final List<_AdminEditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AdminHorizontalStepSelector({
    required this.steps,
    required this.completedSteps,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final active = index == currentIndex;
          final completed = completedSteps[index];
          return InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : context.bgCard,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active ? AppColors.primary : context.borderColor,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : context.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    steps[index].label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? AppColors.primary : context.textSecondary,
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AdminVerticalStepRail extends StatelessWidget {
  final List<_AdminEditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AdminVerticalStepRail({
    required this.steps,
    required this.completedSteps,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      itemCount: steps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        final active = index == currentIndex;
        final completed = completedSteps[index];
        return InkWell(
          onTap: () => onTap(index),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : context.bgCard,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? AppColors.primary : context.borderColor,
                    ),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[index].label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? AppColors.primary : context.textSecondary,
                    ),
                  ),
                ),
                if (completed)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: AppColors.success,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminBottomStepNav extends StatelessWidget {
  final int currentIndex;
  final int totalSteps;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Future<void> Function() onSave;
  final bool saving;

  const _AdminBottomStepNav({
    required this.currentIndex,
    required this.totalSteps,
    required this.onPrev,
    required this.onNext,
    required this.onSave,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex < totalSteps - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: TapLoopButton(
                label: 'Paso anterior',
                onPressed: hasPrev ? onPrev : null,
                variant: TapLoopButtonVariant.outline,
                height: 44,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TapLoopButton(
                label: saving
                    ? 'Guardando...'
                    : hasNext
                    ? 'Siguiente paso'
                    : 'Guardar cambios',
                onPressed: saving
                    ? null
                    : hasNext
                    ? onNext
                    : () {
                        onSave();
                      },
                icon: saving
                    ? null
                    : Icon(
                        hasNext
                            ? Icons.arrow_forward_rounded
                            : Icons.save_outlined,
                        size: 18,
                      ),
                animateIconOnHover: hasNext,
                height: 44,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPreviewPanel extends StatelessWidget {
  final DigitalCardModel card;

  const _AdminPreviewPanel({required this.card});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VISTA PREVIA',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'liomont.taploop.com.mx/${card.publicSlug}',
            style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
          ),
          const SizedBox(height: 24),
          Center(child: DigitalProfilePreview(card: card, width: 240)),
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
