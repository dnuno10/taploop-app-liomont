// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/storage_upload_error.dart';
import '../../../core/utils/web_image_optimizer.dart';
import '../../../core/utils/field_validators.dart';
import '../../../core/data/app_state.dart';
import '../../../core/data/repositories/card_repository.dart';
import '../../../core/data/repositories/linked_admin_gateway.dart';
import '../../../core/widgets/card_initial_setup_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/shared_template_lock_banner.dart';
import '../../../core/widgets/taploop_button.dart';
import '../../../core/widgets/taploop_motion.dart';
import '../../../core/widgets/platform_icon.dart';
import '../../../core/widgets/taploop_progress_indicator.dart';
import '../../../core/widgets/taploop_toast.dart';
import '../models/digital_card_model.dart';
import '../models/social_link_model.dart';
import '../models/contact_item_model.dart';
import '../models/smart_form_model.dart';
import '../utils/calendar_links.dart';
import '../widgets/digital_profile_preview.dart';

class EditCardView extends StatefulWidget {
  const EditCardView({
    super.key,
    this.overrideCard,
    this.overrideOrgId,
    this.onClose,
  });

  /// When non-null, this view edits ANOTHER user's card (admin override mode)
  /// instead of the authenticated user's own card. In this mode the global
  /// [appState] is never mutated, so the admin's own session is unaffected.
  final DigitalCardModel? overrideCard;

  /// Org of the member being edited in override mode. Defaults to the
  /// admin's own org; the admin view passes the member's org when editing a
  /// member of a linked org (Liomont ↔ Promofarma).
  final String? overrideOrgId;

  /// Shown as a close button in the header when provided (override mode).
  final VoidCallback? onClose;

  @override
  State<EditCardView> createState() => _EditCardViewState();
}

class _EditCardViewState extends State<EditCardView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late DigitalCardModel _card;
  int _stepIndex = 0;
  bool _hasCompletedForm = false;

  static const _steps = <_EditStepData>[
    _EditStepData('Perfil', Icons.person_outline_rounded),
    _EditStepData('Contacto', Icons.call_outlined),
    _EditStepData('Enlaces', Icons.link_rounded),
    _EditStepData('Diseño', Icons.palette_outlined),
    _EditStepData('Formularios', Icons.assignment_outlined),
    _EditStepData('Integraciones', Icons.hub_outlined),
  ];

  late TextEditingController _nameCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _companyCtrl;
  late TextEditingController _bioCtrl;

  bool _unsaved = false;
  bool _saving = false;
  bool _suppressTextSync = false;
  String? _organizationName;
  bool _syncingOrganizationCompany = false;
  bool _sharedDesignLocked = false;
  bool _sharedFormsLocked = false;
  bool _sharedIntegrationsLocked = false;
  bool _sharedLinksLocked = false;

  bool get _isOverride => widget.overrideCard != null;

  /// Name as last saved, to detect a rename when the admin saves a
  /// collaborator (and offer to update their public link).
  String _savedName = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _tab.addListener(_syncStepWithTab);
    if (_isOverride) {
      _card = widget.overrideCard!;
    } else {
      appState.addListener(_onAppStateChanged);
      _card =
          appState.currentCard ??
          DigitalCardModel(
            id: '',
            userId: '',
            name: '',
            jobTitle: '',
            company: '',
            contactItems: const [],
            socialLinks: const [],
            publicSlug: '',
          );
    }
    _savedName = _card.name.trim();
    _nameCtrl = TextEditingController(text: _card.name);
    _titleCtrl = TextEditingController(text: _card.jobTitle);
    _companyCtrl = TextEditingController(text: _card.company);
    _bioCtrl = TextEditingController(text: _card.bio ?? '');
    for (final ctrl in [_nameCtrl, _titleCtrl, _companyCtrl, _bioCtrl]) {
      ctrl.addListener(_onTextChanged);
    }
    _loadOrganizationName();
    _loadFormCompletion();
  }

  @override
  void dispose() {
    if (!_isOverride) appState.removeListener(_onAppStateChanged);
    _tab.removeListener(_syncStepWithTab);
    _tab.dispose();
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final card = appState.currentCard;
    if (card != null && card.id == _card.id && _unsaved) {
      if (card.showVerifiedBadge != _card.showVerifiedBadge) {
        setState(() {
          _card = _card.copyWith(showVerifiedBadge: card.showVerifiedBadge);
        });
      }
      _loadOrganizationName();
      _loadFormCompletion();
      return;
    }
    if (card != null &&
        (card.id != _card.id ||
            card.companyLogoUrl != _card.companyLogoUrl ||
            card.profilePhotoUrl != _card.profilePhotoUrl ||
            card.name != _card.name ||
            card.jobTitle != _card.jobTitle ||
            card.company != _card.company ||
            card.bio != _card.bio ||
            card.showVerifiedBadge != _card.showVerifiedBadge ||
            card.profileDesign != _card.profileDesign)) {
      _applyCard(card);
    }
    _loadOrganizationName();
    _loadFormCompletion();
  }

  void _applyCard(DigitalCardModel card) {
    _syncControllers(
      name: card.name,
      title: card.jobTitle,
      company: _organizationName ?? card.company,
      bio: card.bio ?? '',
    );
    if (!mounted) return;
    setState(() {
      _card = card.copyWith(company: _organizationName ?? card.company);
    });
    _loadFormCompletion();
  }

  void _onTextChanged() {
    if (_suppressTextSync) return;
    setState(() {
      _card = _card.copyWith(
        name: _nameCtrl.text,
        jobTitle: _titleCtrl.text,
        company: _companyCtrl.text,
        bio: _bioCtrl.text,
      );
      _unsaved = true;
    });
  }

  Future<void> _loadOrganizationName() async {
    final orgId = _isOverride && widget.overrideOrgId != null
        ? widget.overrideOrgId
        : appState.currentUser?.orgId;
    if (orgId == null || orgId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _organizationName = null;
        _sharedDesignLocked = false;
        _sharedFormsLocked = false;
        _sharedIntegrationsLocked = false;
        _sharedLinksLocked = false;
      });
      return;
    }

    try {
      // Shared-template toggles are org-wide, but while they're on they only
      // hide a section for members OTHER than the template member: editing
      // the template member is what every other member's public card reads
      // from, so that member must always be able to edit it normally.
      final sharedSettings = await CardRepository.fetchSharedTemplateSettings(
        orgId,
      );
      final isTemplate =
          sharedSettings?.templateCardId != null &&
          sharedSettings!.templateCardId == _card.id;
      final sharedDesign =
          (sharedSettings?.designShared ?? false) && !isTemplate;
      final sharedForms = (sharedSettings?.formsShared ?? false) && !isTemplate;
      final sharedIntegrations =
          (sharedSettings?.integrationsShared ?? false) && !isTemplate;
      final sharedLinks = (sharedSettings?.linksShared ?? false) && !isTemplate;

      final Map<String, dynamic>? org;
      if (LinkedAdminGateway.handlesOrg(orgId)) {
        org = await LinkedAdminGateway.fetchOrg(orgId);
      } else {
        final rows = await SupabaseService.client
            .from('organizations')
            .select('name')
            .eq('id', orgId)
            .limit(1);
        final orgRows = rows as List;
        org = orgRows.isNotEmpty ? orgRows.first : null;
      }
      final orgName = (org?['name'] as String?)?.trim();
      if (!mounted) return;
      if (orgName == null || orgName.isEmpty) {
        setState(() {
          _sharedDesignLocked = sharedDesign;
          _sharedFormsLocked = sharedForms;
          _sharedIntegrationsLocked = sharedIntegrations;
          _sharedLinksLocked = sharedLinks;
        });
        return;
      }

      final shouldPersistCompany =
          _card.id.isNotEmpty && _card.company.trim() != orgName;
      final previousUnsaved = _unsaved;
      _syncControllers(company: orgName);
      setState(() {
        _organizationName = orgName;
        _sharedDesignLocked = sharedDesign;
        _sharedFormsLocked = sharedForms;
        _sharedIntegrationsLocked = sharedIntegrations;
        _sharedLinksLocked = sharedLinks;
        _card = _card.copyWith(company: orgName);
        _unsaved = previousUnsaved;
      });
      if (shouldPersistCompany) {
        await _persistOrganizationCompanyIfNeeded(orgId, orgName);
      }
    } catch (_) {}
  }

  Future<void> _persistOrganizationCompanyIfNeeded(
    String orgId,
    String orgName,
  ) async {
    if (_syncingOrganizationCompany || _card.id.isEmpty) return;

    _syncingOrganizationCompany = true;
    try {
      await CardRepository.syncCardOrganizationCompany(
        cardId: _card.id,
        company: orgName,
        orgId: orgId,
      );
      if (!mounted) return;
      final updatedCard = _card.copyWith(company: orgName, orgId: orgId);
      _syncCard(updatedCard);
    } catch (_) {
    } finally {
      _syncingOrganizationCompany = false;
    }
  }

  void _syncControllers({
    String? name,
    String? title,
    String? company,
    String? bio,
  }) {
    _suppressTextSync = true;
    if (name != null) _nameCtrl.text = name;
    if (title != null) _titleCtrl.text = title;
    if (company != null) _companyCtrl.text = company;
    if (bio != null) _bioCtrl.text = bio;
    _suppressTextSync = false;
  }

  /// Updates the locally-edited card and, unless this view is editing
  /// ANOTHER user's card (override mode), mirrors the change into the
  /// global [appState] so the rest of the app stays in sync.
  void _syncCard(DigitalCardModel card) {
    if (!mounted) return;
    setState(() => _card = card);
    if (!_isOverride) appState.updateCard(card);
  }

  Future<void> _loadFormCompletion() async {
    final cardId = _card.id;
    if (cardId.isEmpty) {
      if (!mounted || !_hasCompletedForm) return;
      setState(() => _hasCompletedForm = false);
      return;
    }

    try {
      final forms = await CardRepository.fetchSmartForms(cardId);
      final hasCompletedForm = forms.any(
        (form) => form.isActive && form.fields.isNotEmpty,
      );
      if (!mounted || _hasCompletedForm == hasCompletedForm) return;
      setState(() => _hasCompletedForm = hasCompletedForm);
    } catch (_) {}
  }

  void _syncStepWithTab() {
    if (!_tab.indexIsChanging && _stepIndex != _tab.index) {
      setState(() => _stepIndex = _tab.index);
    }
  }

  void _goToStep(int index) {
    if (index < 0 || index >= _steps.length) return;
    setState(() => _stepIndex = index);
    _tab.animateTo(
      index,
      duration: TapLoopMotion.slow,
      curve: TapLoopMotion.entrance,
    );
  }

  void _nextStep() {
    if (_stepIndex >= _steps.length - 1) return;
    _goToStep(_stepIndex + 1);
  }

  void _prevStep() {
    if (_stepIndex <= 0) return;
    _goToStep(_stepIndex - 1);
  }

  List<bool> _stepCompletion() {
    final hasVisibleContact = _card.contactItems.any(
      (item) => item.isVisible && item.value.trim().isNotEmpty,
    );
    final hasVisibleSocial = _card.socialLinks.any(
      (link) => link.isVisible && link.url.trim().isNotEmpty,
    );
    final hasCalendar =
        _card.calendarEnabled && (_card.calendarUrl?.trim().isNotEmpty == true);

    return [
      _nameCtrl.text.trim().isNotEmpty &&
          _titleCtrl.text.trim().isNotEmpty &&
          _companyCtrl.text.trim().isNotEmpty &&
          _bioCtrl.text.trim().isNotEmpty,
      hasVisibleContact,
      _sharedLinksLocked || hasVisibleSocial,
      true,
      _sharedFormsLocked || _hasCompletedForm,
      _sharedIntegrationsLocked || hasCalendar,
    ];
  }

  Future<void> _onSave() async {
    if (_saving) return;
    if (_card.id.isEmpty) {
      TapLoopToast.show(
        context,
        'No hay tarjeta activa. Recarga la página.',
        TapLoopToastType.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await CardRepository.saveCard(_card);
      if (!_isOverride) appState.updateCard(_card);
      final renamed = _card.name.trim() != _savedName;
      _savedName = _card.name.trim();
      if (mounted) {
        setState(() {
          _saving = false;
          _unsaved = false;
        });
        TapLoopToast.show(
          context,
          'Cambios guardados correctamente.',
          TapLoopToastType.success,
        );
      }
      if (mounted && _isOverride && renamed) {
        await _offerPublicSlugUpdate();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        TapLoopToast.show(
          context,
          'No se pudieron guardar los cambios. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  /// Admin editing a collaborator renamed them: ask before changing their
  /// public link to match the new name (old links/QRs stop working).
  Future<void> _offerPublicSlugUpdate() async {
    final name = _card.name.trim();
    if (name.isEmpty || _card.id.isEmpty) return;
    if (CardRepository.slugFromName(name) == _card.publicSlug) return;

    final String proposed;
    try {
      proposed = await CardRepository.availableSlugForName(
        name,
        cardId: _card.id,
      );
    } catch (_) {
      return;
    }
    if (!mounted || proposed == _card.publicSlug) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '¿Deseas actualizar el enlace público del colaborador?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El nombre cambió a "$name".',
              style: GoogleFonts.dmSans(color: ctx.textSecondary),
            ),
            const SizedBox(height: 14),
            _SlugChangeLine(
              label: 'Actual',
              value: 'liomont.taploop.com.mx/${_card.publicSlug}',
              muted: true,
            ),
            const SizedBox(height: 6),
            _SlugChangeLine(
              label: 'Nuevo',
              value: 'liomont.taploop.com.mx/$proposed',
            ),
            const SizedBox(height: 14),
            Text(
              'Los QR impresos y enlaces ya compartidos con el enlace actual '
              'dejarán de funcionar. Las tarjetas NFC siguen funcionando.',
              style: GoogleFonts.dmSans(fontSize: 13, color: ctx.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mantener enlace actual'),
          ),
          _OrangeGradientButton(
            label: 'Actualizar enlace',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // The availability check can't see every org's cards, so if the database
    // still reports the slug as taken, try the next numbered variant.
    var slug = proposed;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await CardRepository.updateSlug(cardId: _card.id, slug: slug);
        if (!mounted) return;
        setState(() => _card = _card.copyWith(publicSlug: slug));
        TapLoopToast.show(
          context,
          'Enlace público actualizado: liomont.taploop.com.mx/$slug',
          TapLoopToastType.success,
        );
        return;
      } catch (error) {
        if (!error.toString().contains('slug_taken')) break;
        final match = RegExp(r'-(\d+)$').firstMatch(slug);
        final next = match == null ? 2 : int.parse(match.group(1)!) + 1;
        try {
          slug = await CardRepository.availableSlugForName(
            name,
            cardId: _card.id,
            startSuffix: next,
          );
        } catch (_) {
          break;
        }
      }
    }
    if (!mounted) return;
    TapLoopToast.show(
      context,
      'No se pudo actualizar el enlace público. Intenta de nuevo.',
      TapLoopToastType.warning,
    );
  }

  Future<void> _handleProfilePhotoRemoved() async {
    if (_card.id.isEmpty) return;

    final previousCard = _card;
    final previousUnsaved = _unsaved;
    setState(() {
      _card = _card.copyWith(clearProfilePhoto: true);
      _unsaved = previousUnsaved;
    });

    try {
      await CardRepository.clearProfilePhoto(previousCard.id);
      if (!_isOverride) {
        final appCard = appState.currentCard;
        if (appCard?.id == previousCard.id) {
          appState.updateCard(appCard!.copyWith(clearProfilePhoto: true));
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _card = previousCard;
        _unsaved = previousUnsaved;
      });
      rethrow;
    }
  }

  Future<void> _handleProfilePhotoChanged(String url) async {
    if (_card.id.isEmpty) return;

    final previousCard = _card;
    final previousUnsaved = _unsaved;
    final updatedCard = _card.copyWith(profilePhotoUrl: url);
    setState(() {
      _card = updatedCard;
      _unsaved = previousUnsaved;
    });

    try {
      await CardRepository.updateProfilePhoto(
        cardId: updatedCard.id,
        profilePhotoUrl: url,
      );
      if (!_isOverride) {
        final appCard = appState.currentCard;
        if (appCard?.id == updatedCard.id) {
          appState.updateCard(appCard!.copyWith(profilePhotoUrl: url));
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _card = previousCard;
        _unsaved = previousUnsaved;
      });
      rethrow;
    }
  }

  void _showAddContact([ContactType initialType = ContactType.phone]) {
    if (_card.contactItems.length >= 8) {
      TapLoopToast.show(
        context,
        'Máximo 8 contactos permitidos.',
        TapLoopToastType.error,
      );
      return;
    }
    void onAdd(ContactItemModel item) => _persistNewContact(item);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          backgroundColor: ctx.bgCard,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 28,
          ),
          child: SizedBox(
            width: 920,
            child: _AddContactSheet(
              onSubmit: onAdd,
              isDialog: true,
              initialType: initialType,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _AddContactSheet(onSubmit: onAdd, initialType: initialType),
      );
    }
  }

  void _showEditContact(ContactItemModel item) {
    void onSave(ContactItemModel updated) => _persistEditedContact(updated);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          backgroundColor: ctx.bgCard,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 28,
          ),
          child: SizedBox(
            width: 920,
            child: _AddContactSheet(
              onSubmit: onSave,
              isDialog: true,
              initialItem: item,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddContactSheet(onSubmit: onSave, initialItem: item),
      );
    }
  }

  Future<void> _persistNewContact(ContactItemModel item) async {
    try {
      final saved = await CardRepository.addContactItem(_card.id, item);
      if (mounted) {
        _syncCard(_card.copyWith(contactItems: [..._card.contactItems, saved]));
        TapLoopToast.show(
          context,
          'Contacto añadido correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo añadir el contacto. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _persistEditedContact(ContactItemModel updatedItem) async {
    try {
      await CardRepository.updateContactItem(updatedItem);
      if (mounted) {
        _syncCard(
          _card.copyWith(
            contactItems: _card.contactItems
                .map((c) => c.id == updatedItem.id ? updatedItem : c)
                .toList(),
          ),
        );
        TapLoopToast.show(
          context,
          'Contacto actualizado correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo actualizar el contacto: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar el contacto. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  void _showAddSocial() {
    if (_card.socialLinks.length >= 8) {
      TapLoopToast.show(
        context,
        'Máximo 8 redes sociales permitidas.',
        TapLoopToastType.error,
      );
      return;
    }
    void onAdd(SocialLinkModel link) => _persistNewSocial(link);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          backgroundColor: ctx.bgCard,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 28,
          ),
          child: SizedBox(
            width: 920,
            child: _AddSocialSheet(onSubmit: onAdd, isDialog: true),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddSocialSheet(onSubmit: onAdd),
      );
    }
  }

  void _showEditSocial(SocialLinkModel link) {
    void onSave(SocialLinkModel updated) => _persistEditedSocial(updated);
    if (Responsive.isDesktop(context)) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          backgroundColor: ctx.bgCard,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 28,
          ),
          child: SizedBox(
            width: 920,
            child: _AddSocialSheet(
              onSubmit: onSave,
              isDialog: true,
              initialLink: link,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AddSocialSheet(onSubmit: onSave, initialLink: link),
      );
    }
  }

  Future<void> _persistNewSocial(SocialLinkModel link) async {
    try {
      final saved = await CardRepository.addSocialLink(_card.id, link);
      if (mounted) {
        _syncCard(_card.copyWith(socialLinks: [..._card.socialLinks, saved]));
        TapLoopToast.show(
          context,
          'Red social añadida correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo añadir la red social. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _persistEditedSocial(SocialLinkModel updatedLink) async {
    try {
      await CardRepository.updateSocialLink(updatedLink);
      if (mounted) {
        _syncCard(
          _card.copyWith(
            socialLinks: _card.socialLinks
                .map((s) => s.id == updatedLink.id ? updatedLink : s)
                .toList(),
          ),
        );
        TapLoopToast.show(
          context,
          'Red social actualizada correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar la red social. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _handleContactsChanged(DigitalCardModel updated) async {
    final oldItems = _card.contactItems;
    final newItems = updated.contactItems
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    if (mounted) {
      setState(() => _card = updated.copyWith(contactItems: newItems));
    }
    try {
      for (final old in oldItems) {
        if (!newItems.any((i) => i.id == old.id)) {
          await CardRepository.deleteContactItem(old.id);
        }
      }
      for (final item in newItems) {
        final old = oldItems.firstWhere(
          (i) => i.id == item.id,
          orElse: () => item,
        );
        if (old.type != item.type ||
            old.value != item.value ||
            old.label != item.label ||
            old.isVisible != item.isVisible ||
            old.sortOrder != item.sortOrder) {
          await CardRepository.updateContactItem(item);
        }
      }
      await CardRepository.reorderContactItems(_card.id, newItems);
      if (mounted) {
        _syncCard(_card.copyWith(contactItems: newItems));
      }
      if (mounted && newItems.length < oldItems.length) {
        TapLoopToast.show(
          context,
          'Contacto eliminado.',
          TapLoopToastType.success,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudieron actualizar los contactos: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _syncCard(_card.copyWith(contactItems: oldItems));
        TapLoopToast.show(
          context,
          'No se pudieron actualizar los contactos. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _handleSocialsChanged(DigitalCardModel updated) async {
    final oldLinks = _card.socialLinks;
    final newLinks = updated.socialLinks
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    if (mounted) {
      setState(() => _card = updated.copyWith(socialLinks: newLinks));
    }
    try {
      for (final old in oldLinks) {
        if (!newLinks.any((i) => i.id == old.id)) {
          await CardRepository.deleteSocialLink(old.id);
        }
      }
      for (final link in newLinks) {
        final old = oldLinks.firstWhere(
          (i) => i.id == link.id,
          orElse: () => link,
        );
        if (old.platform != link.platform ||
            old.url != link.url ||
            old.customLabel != link.customLabel ||
            old.iconKey != link.iconKey ||
            old.isVisible != link.isVisible ||
            old.sortOrder != link.sortOrder) {
          await CardRepository.updateSocialLink(link);
        }
      }
      await CardRepository.reorderSocialLinks(_card.id, newLinks);
      if (mounted) {
        _syncCard(_card.copyWith(socialLinks: newLinks));
      }
      if (mounted && newLinks.length < oldLinks.length) {
        TapLoopToast.show(
          context,
          'Red social eliminada.',
          TapLoopToastType.success,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudieron actualizar los enlaces: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _syncCard(_card.copyWith(socialLinks: oldLinks));
        TapLoopToast.show(
          context,
          'No se pudieron actualizar las redes sociales. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final hasLinkedCard = _isOverride
        ? _card.id.isNotEmpty
        : appState.currentCard != null;
    final overrideName = widget.overrideCard?.name.trim() ?? '';
    final headerTitleText = _isOverride
        ? (overrideName.isNotEmpty
              ? 'Editando a $overrideName'
              : 'Editando perfil del equipo')
        : 'Perfil digital';
    final headerSubtitleText = _isOverride
        ? 'Estás editando el perfil de este miembro de tu equipo.'
        : 'Edita tu perfil, contacto, diseño y flujos de captura desde un mismo espacio.';
    final headerTitle = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: isDesktop ? 320 : 240,
        maxWidth: isDesktop ? 560 : double.infinity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headerTitleText,
                style: GoogleFonts.outfit(
                  fontSize: isDesktop ? 34 : 30,
                  fontWeight: FontWeight.w800,
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
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headerSubtitleText,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
    final stepControls = hasLinkedCard ? _buildStepControls() : null;
    final closeButton = widget.onClose == null
        ? null
        : TapLoopPressable(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(999),
            hoverColor: TapLoopMotion.hoverSurfaceColor(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.bgCard,
                shape: BoxShape.circle,
                border: Border.all(color: context.borderStrongSoft),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: context.textSecondary,
              ),
            ),
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
                color: context.bgCard,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: headerTitle),
                        if (stepControls != null) stepControls,
                        if (closeButton != null) ...[
                          const SizedBox(width: 10),
                          closeButton,
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (closeButton != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: headerTitle),
                              closeButton,
                            ],
                          )
                        else
                          headerTitle,
                        if (stepControls != null) ...[
                          const SizedBox(height: 14),
                          stepControls,
                        ],
                      ],
                    ),
            ),
            Expanded(
              child: hasLinkedCard
                  ? (isDesktop ? _desktopLayout() : _mobileLayout())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      child: CardInitialSetupState(
                        onLinked: () => _applyCard(appState.currentCard!),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepControls() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.borderStrongSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 14, color: AppColors.primary),
              const SizedBox(width: 7),
              Text(
                'Paso ${_stepIndex + 1} de ${_steps.length}: ${_steps[_stepIndex].label}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
        _StepNavButton(
          icon: Icons.arrow_back_rounded,
          enabled: _stepIndex > 0,
          onTap: _prevStep,
        ),
        _StepNavButton(
          icon: Icons.arrow_forward_rounded,
          enabled: _stepIndex < _steps.length - 1,
          onTap: _nextStep,
        ),
        _SaveButton(unsaved: _unsaved, saving: _saving, onSave: _onSave),
      ],
    );
  }

  Widget _mobileLayout() {
    final stepCompletion = _stepCompletion();
    return Container(
      color: context.bgPage,
      child: Column(
        children: [
          Container(
            color: context.bgPage,
            child: _HorizontalStepSelector(
              steps: _steps,
              completedSteps: stepCompletion,
              currentIndex: _stepIndex,
              onTap: _goToStep,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(color: context.borderStrongSoft),
                ),
                clipBehavior: Clip.hardEdge,
                child: TabBarView(
                  controller: _tab,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _tabChildren(),
                ),
              ),
            ),
          ),
          _BottomStepNav(
            currentIndex: _stepIndex,
            totalSteps: _steps.length,
            onPrev: _prevStep,
            onNext: _nextStep,
          ),
        ],
      ),
    );
  }

  Widget _desktopLayout() {
    final stepCompletion = _stepCompletion();
    return Container(
      color: context.bgPage,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 252,
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.borderStrongSoft),
              ),
              child: _VerticalStepRail(
                steps: _steps,
                completedSteps: stepCompletion,
                currentIndex: _stepIndex,
                onTap: _goToStep,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.borderStrongSoft),
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: [
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        physics: const NeverScrollableScrollPhysics(),
                        children: _tabChildren(),
                      ),
                    ),
                    _BottomStepNav(
                      currentIndex: _stepIndex,
                      totalSteps: _steps.length,
                      onPrev: _prevStep,
                      onNext: _nextStep,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(width: 390, child: _LivePreviewPanel(card: _card)),
          ],
        ),
      ),
    );
  }

  List<Widget> _tabChildren() => [
    _ProfileTab(
      nameCtrl: _nameCtrl,
      titleCtrl: _titleCtrl,
      companyCtrl: _companyCtrl,
      bioCtrl: _bioCtrl,
      card: _card,
      companyLocked: _organizationName != null,
      onPhotoChanged: _handleProfilePhotoChanged,
      onPhotoRemoved: _handleProfilePhotoRemoved,
      onChanged: (c) {
        final verifiedChanged = c.showVerifiedBadge != _card.showVerifiedBadge;
        setState(() {
          _card = c;
          _unsaved = true;
        });
        if (!_isOverride) {
          final appCard = appState.currentCard;
          if (verifiedChanged && appCard?.id == c.id) {
            appState.updateCard(
              appCard!.copyWith(showVerifiedBadge: c.showVerifiedBadge),
            );
          }
        }
      },
    ),
    _ContactTab(
      card: _card,
      onChanged: (c) => _handleContactsChanged(c),
      onAdd: _showAddContact,
      onEdit: _showEditContact,
    ),
    if (_sharedLinksLocked)
      const SharedTemplateLockBanner(
        icon: Icons.link_rounded,
        title: 'Enlaces compartidos activos',
        message:
            'Esta sección es gestionada por tu organización: tus redes sociales públicas se toman del perfil plantilla del equipo.',
      )
    else
      _SocialTab(
        card: _card,
        onChanged: (c) => _handleSocialsChanged(c),
        onAdd: _showAddSocial,
        onEdit: _showEditSocial,
      ),
    if (_sharedDesignLocked)
      const SharedTemplateLockBanner(
        icon: Icons.palette_outlined,
        title: 'Diseño compartido activo',
        message:
            'Esta sección es gestionada por tu organización: tu diseño público se toma del perfil plantilla del equipo.',
      )
    else
      _DesignTab(
        card: _card,
        onChanged: (c) => setState(() {
          _card = c;
          _unsaved = true;
        }),
      ),
    if (_sharedFormsLocked)
      const SharedTemplateLockBanner(
        icon: Icons.assignment_outlined,
        title: 'Formulario compartido activo',
        message:
            'Esta sección es gestionada por tu organización: tu formulario público se toma del perfil plantilla del equipo.',
      )
    else
      _FormulariosTab(
        cardId: _card.id,
        onCompletionChanged: (hasCompletedForm) {
          if (_hasCompletedForm == hasCompletedForm) return;
          setState(() => _hasCompletedForm = hasCompletedForm);
        },
        onFormsChanged: (forms) {
          setState(() => _card = _card.copyWith(smartForms: forms));
        },
      ),
    if (_sharedIntegrationsLocked)
      const SharedTemplateLockBanner(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Integración compartida activa',
        message:
            'Esta sección es gestionada por tu organización: tu calendario público se toma del perfil plantilla del equipo.',
      )
    else
      _CalendarioTab(
        calendarEnabled: _card.calendarEnabled,
        calendarUrl: _card.calendarUrl,
        onChanged: (enabled, url) => setState(() {
          _card = _card.copyWith(
            calendarEnabled: enabled,
            calendarUrl: url.isEmpty ? null : url,
          );
          _unsaved = true;
        }),
      ),
  ];
}

class _EditStepData {
  final String label;
  final IconData icon;
  const _EditStepData(this.label, this.icon);
}

class _StepNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapLoopPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      borderRadius: BorderRadius.circular(999),
      hoverColor: TapLoopMotion.hoverSurfaceColor(context),
      child: AnimatedContainer(
        duration: TapLoopMotion.fast,
        curve: TapLoopMotion.standard,
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: context.bgCard,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? context.borderStrongSoft : context.borderColor,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? context.textPrimary : context.textMuted,
        ),
      ),
    );
  }
}

class _HorizontalStepSelector extends StatelessWidget {
  final List<_EditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _HorizontalStepSelector({
    required this.steps,
    required this.completedSteps,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final step = steps[i];
          final completed = completedSteps[i];
          final active = i == currentIndex;
          var hovered = false;
          return StatefulBuilder(
            builder: (context, setHover) {
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setHover(() => hovered = true),
                onExit: (_) => setHover(() => hovered = false),
                child: TapLoopPressable(
                  onTap: () => onTap(i),
                  borderRadius: BorderRadius.circular(16),
                  hoverColor: Colors.transparent,
                  child: AnimatedContainer(
                    duration: TapLoopMotion.fast,
                    curve: TapLoopMotion.standard,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.black
                          : hovered
                          ? TapLoopMotion.hoverSurfaceColor(context)
                          : context.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: active ? Colors.black : context.borderStrongSoft,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active
                                  ? Colors.white
                                  : context.borderStrongSoft,
                            ),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? Colors.black
                                  : context.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          step.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: active
                                ? Colors.white
                                : context.textSecondary,
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _VerticalStepRail extends StatelessWidget {
  final List<_EditStepData> steps;
  final List<bool> completedSteps;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _VerticalStepRail({
    required this.steps,
    required this.completedSteps,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      itemCount: steps.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final step = steps[i];
        final completed = completedSteps[i];
        final active = i == currentIndex;
        var hovered = false;
        return StatefulBuilder(
          builder: (context, setHover) {
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setHover(() => hovered = true),
              onExit: (_) => setHover(() => hovered = false),
              child: TapLoopPressable(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(16),
                hoverColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: TapLoopMotion.fast,
                  curve: TapLoopMotion.standard,
                  constraints: const BoxConstraints(minHeight: 58),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.black
                        : hovered
                        ? TapLoopMotion.hoverSurfaceColor(context)
                        : context.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? Colors.black : context.borderStrongSoft,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active
                                ? Colors.white
                                : context.borderStrongSoft,
                          ),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? Colors.black
                                : context.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                step.label,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: active
                                      ? Colors.white
                                      : context.textSecondary,
                                ),
                              ),
                            ),
                            if (completed) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _BottomStepNav extends StatelessWidget {
  final int currentIndex;
  final int totalSteps;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _BottomStepNav({
    required this.currentIndex,
    required this.totalSteps,
    required this.onPrev,
    required this.onNext,
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
                height: 46,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TapLoopButton(
                label: hasNext ? 'Siguiente paso' : 'Último paso',
                onPressed: hasNext ? onNext : null,
                height: 46,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab selector ─────────────────────────────────────────────────────────────

// ─── Live Preview (desktop) ───────────────────────────────────────────────────

class _LivePreviewPanel extends StatelessWidget {
  final DigitalCardModel card;
  const _LivePreviewPanel({required this.card});

  @override
  Widget build(BuildContext context) {
    final slug = card.publicSlug.trim();
    final publicPath = slug.isEmpty
        ? 'liomont.taploop.com.mx'
        : 'liomont.taploop.com.mx/$slug';
    final publicUrl = 'https://$publicPath';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderStrongSoft),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HelpTitle(
              title: 'Vista previa',
              helpText:
                  'Previsualiza cómo se verá el perfil público antes de publicar cambios.',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF181411),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Así se verá tu perfil público en TapLoop.',
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.borderStrongSoft),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 16,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      publicPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Abrir perfil público',
                    child: TapLoopPressable(
                      onTap: () => html.window.open(publicUrl, '_blank'),
                      borderRadius: BorderRadius.circular(12),
                      hoverColor: TapLoopMotion.hoverSurfaceColor(context),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.open_in_new_rounded,
                          size: 17,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(child: DigitalProfilePreview(card: card, width: 300)),
            const SizedBox(height: 24),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 16),
            Text(
              card.name.isEmpty ? 'Nombre' : card.name,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: card.name.isEmpty
                    ? context.textMuted
                    : context.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              card.jobTitle.isEmpty
                  ? 'Cargo · Empresa'
                  : '${card.jobTitle} · ${card.company}',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
            if (card.bio?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                card.bio!,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: context.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Profile Tab ─────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController titleCtrl;
  final TextEditingController companyCtrl;
  final TextEditingController bioCtrl;
  final DigitalCardModel card;
  final bool companyLocked;
  final Future<void> Function(String) onPhotoChanged;
  final Future<void> Function() onPhotoRemoved;
  final ValueChanged<DigitalCardModel> onChanged;

  const _ProfileTab({
    required this.nameCtrl,
    required this.titleCtrl,
    required this.companyCtrl,
    required this.bioCtrl,
    required this.card,
    required this.companyLocked,
    required this.onPhotoChanged,
    required this.onPhotoRemoved,
    required this.onChanged,
  });

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String _nameError = '';
  String _titleError = '';
  String _bioError = '';

  @override
  void initState() {
    super.initState();
    widget.nameCtrl.addListener(() => setState(() {}));
    widget.titleCtrl.addListener(() => setState(() {}));
    widget.bioCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _validateFieldsOnBlur(String fieldName) {
    setState(() {
      switch (fieldName) {
        case 'name':
          final validation = FieldValidators.validateMaxLength(
            widget.nameCtrl.text,
            FieldValidators.nameMaxLength,
            'Nombre',
          );
          _nameError = validation.errorMessage ?? '';
          break;
        case 'title':
          final validation = FieldValidators.validateMaxLength(
            widget.titleCtrl.text,
            FieldValidators.jobTitleMaxLength,
            'Cargo',
          );
          _titleError = validation.errorMessage ?? '';
          break;
        case 'bio':
          final validation = FieldValidators.validateMaxLength(
            widget.bioCtrl.text,
            FieldValidators.bioMaxLength,
            'Biografía',
          );
          _bioError = validation.errorMessage ?? '';
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    size: 22,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Perfil',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              AvatarPicker(
                card: widget.card,
                onPhotoChanged: widget.onPhotoChanged,
                onPhotoRemoved: widget.onPhotoRemoved,
              ),
              const SizedBox(height: 28),
              _EditInputField(
                label: 'Nombre completo',
                controller: widget.nameCtrl,
                hint: 'Ej: Juan García',
                error: _nameError,
                maxLength: FieldValidators.nameMaxLength,
                onChanged: (_) => _validateFieldsOnBlur('name'),
              ),
              const SizedBox(height: 18),
              _VerifiedProfileOption(
                enabled: widget.card.showVerifiedBadge,
                onChanged: (value) => widget.onChanged(
                  widget.card.copyWith(showVerifiedBadge: value),
                ),
              ),
              const SizedBox(height: 18),
              _EditInputField(
                label: 'Cargo / Rol',
                controller: widget.titleCtrl,
                hint: 'Ej: Representante de ventas',
                error: _titleError,
                maxLength: FieldValidators.jobTitleMaxLength,
                onChanged: (_) => _validateFieldsOnBlur('title'),
              ),
              const SizedBox(height: 18),
              _EditInputField(
                label: 'Empresa',
                controller: widget.companyCtrl,
                hint: 'Ej: TapLoop',
                enabled: !widget.companyLocked,
              ),
              if (widget.companyLocked) ...[
                const SizedBox(height: 8),
                Text(
                  'Este campo se completa automaticamente segun la organizacion del usuario y no puede modificarse.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _EditInputField(
                label: 'Biografía',
                controller: widget.bioCtrl,
                hint: 'Especialista en...',
                maxLines: 4,
                error: _bioError,
                maxLength: FieldValidators.bioMaxLength,
                onChanged: (_) => _validateFieldsOnBlur('bio'),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill button with the same orange gradient as "Guardar cambios".
class _OrangeGradientButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _OrangeGradientButton({required this.label, required this.onPressed});

  @override
  State<_OrangeGradientButton> createState() => _OrangeGradientButtonState();
}

class _OrangeGradientButtonState extends State<_OrangeGradientButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? const [Color(0xFFFF6A2A), Color(0xFFFF9A52)]
                  : const [Color(0xFFFF5A1F), Color(0xFFFF8A3D)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlugChangeLine extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;

  const _SlugChangeLine({
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: context.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: muted ? context.textSecondary : AppColors.primary,
              decoration: muted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

class AvatarPicker extends StatefulWidget {
  final DigitalCardModel card;
  final Future<void> Function(String) onPhotoChanged;
  final Future<void> Function()? onPhotoRemoved;
  const AvatarPicker({
    super.key,
    required this.card,
    required this.onPhotoChanged,
    this.onPhotoRemoved,
  });

  @override
  State<AvatarPicker> createState() => AvatarPickerState();
}

class AvatarPickerState extends State<AvatarPicker> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    if (!kIsWeb) return;
    final input = html.FileUploadInputElement()
      ..accept = 'image/jpeg,image/png';
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return;

    // Validar tipo de archivo
    const tiposPermitidos = ['image/jpeg', 'image/png'];
    if (!tiposPermitidos.contains(file.type)) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'Solo se permiten imágenes en formato JPG o PNG.',
          TapLoopToastType.error,
        );
      }
      return;
    }

    // Validar tamaño
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

    if (!mounted) return;
    final adjustment = await _showImageAdjustmentDialog(
      context,
      file: file,
      title: 'Ajustar foto de perfil',
      subtitle:
          'Previsualiza el encuadre antes de guardarlo en tu perfil público.',
      aspectRatio: 1,
      shape: BoxShape.circle,
    );
    if (adjustment == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final optimized = await optimizeAdjustedWebRasterImage(
        file,
        maxDimension: 720,
        outputType: 'image/jpeg',
        aspectRatio: 1,
        quality: 0.88,
        zoom: adjustment.zoom,
        position: adjustment.position,
        flattenToWhite: true,
      );

      final userId = widget.card.userId ?? 'unknown';
      final cardId = widget.card.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      var path = '$userId/$cardId/profile_$timestamp.${optimized.extension}';
      final fileOptions = FileOptions(
        upsert: true,
        contentType: optimized.contentType,
      );

      try {
        await SupabaseService.client.storage
            .from('avatars')
            .uploadBinary(path, optimized.bytes, fileOptions: fileOptions);
      } catch (_) {
        // Storage policies may only allow writing under the uploader's own
        // folder; for a linked-org member, retry under the admin's folder.
        final adminId = SupabaseService.client.auth.currentUser?.id;
        if (!LinkedAdminGateway.handlesCard(cardId) || adminId == null) {
          rethrow;
        }
        path = '$adminId/$cardId/profile_$timestamp.${optimized.extension}';
        await SupabaseService.client.storage
            .from('avatars')
            .uploadBinary(path, optimized.bytes, fileOptions: fileOptions);
      }

      final rawUrl = SupabaseService.client.storage
          .from('avatars')
          .getPublicUrl(path);

      await widget.onPhotoChanged(rawUrl);
      if (mounted) {
        TapLoopToast.show(
          context,
          'Foto de perfil actualizada.',
          TapLoopToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        TapLoopToast.show(
          context,
          friendlyStorageUploadError(
            error,
            assetLabel: 'la imagen',
            bucket: 'avatars',
          ),
          TapLoopToastType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmAndRemove() async {
    final onPhotoRemoved = widget.onPhotoRemoved;
    if (onPhotoRemoved == null || _uploading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Eliminar foto de perfil',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'La foto dejará de mostrarse en el perfil público.',
          style: GoogleFonts.dmSans(color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploading = true);
    try {
      await onPhotoRemoved();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Foto de perfil eliminada.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo eliminar la foto. Intenta de nuevo.',
          TapLoopToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.card.profilePhotoUrl?.trim().isNotEmpty == true
        ? widget.card.profilePhotoUrl
        : null;
    var hoveringButton = false;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _uploading ? null : _pickAndUpload,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.bgCard,
                border: Border.all(color: context.borderStrongSoft),
              ),
              clipBehavior: Clip.antiAlias,
              child: photoUrl != null
                  ? Image.network(photoUrl, fit: BoxFit.cover)
                  : Center(
                      child: _uploading
                          ? const TapLoopProgressIndicator(
                              color: AppColors.primary,
                            )
                          : Icon(
                              Icons.person_outline_rounded,
                              size: 42,
                              color: AppColors.primary,
                            ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (context, setHover) {
              final hovered = hoveringButton && !_uploading;
              return MouseRegion(
                cursor: _uploading
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                onEnter: (_) => setHover(() => hoveringButton = true),
                onExit: (_) => setHover(() => hoveringButton = false),
                child: GestureDetector(
                  onTap: _uploading ? null : _pickAndUpload,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 280,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: hovered
                          ? TapLoopMotion.hoverSurfaceColor(context)
                          : context.bgCard,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: hovered
                            ? context.borderStrong
                            : context.borderStrongSoft,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(
                          Icons.photo_camera_outlined,
                          size: 17,
                          color: context.textPrimary,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          _uploading
                              ? 'Subiendo foto...'
                              : photoUrl == null
                              ? 'Cargar foto de perfil'
                              : 'Cambiar foto de perfil',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (photoUrl != null && widget.onPhotoRemoved != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _uploading ? null : _confirmAndRemove,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                'Eliminar foto',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'JPG, PNG · máx 5 MB',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageAdjustmentResult {
  final double zoom;
  final WebImageCropPosition position;

  const _ImageAdjustmentResult({required this.zoom, required this.position});
}

Future<_ImageAdjustmentResult?> _showImageAdjustmentDialog(
  BuildContext context, {
  required html.File file,
  required String title,
  required String subtitle,
  required double aspectRatio,
  required BoxShape shape,
}) {
  return showDialog<_ImageAdjustmentResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: _ImageAdjustmentDialog(
        file: file,
        title: title,
        subtitle: subtitle,
        aspectRatio: aspectRatio,
        shape: shape,
      ),
    ),
  );
}

class _ImageAdjustmentDialog extends StatefulWidget {
  final html.File file;
  final String title;
  final String subtitle;
  final double aspectRatio;
  final BoxShape shape;

  const _ImageAdjustmentDialog({
    required this.file,
    required this.title,
    required this.subtitle,
    required this.aspectRatio,
    required this.shape,
  });

  @override
  State<_ImageAdjustmentDialog> createState() => _ImageAdjustmentDialogState();
}

class _ImageAdjustmentDialogState extends State<_ImageAdjustmentDialog> {
  late final String _objectUrl;
  double _zoom = 1;
  WebImageCropPosition _position = WebImageCropPosition.center;

  @override
  void initState() {
    super.initState();
    _objectUrl = html.Url.createObjectUrlFromBlob(widget.file);
  }

  @override
  void dispose() {
    html.Url.revokeObjectUrl(_objectUrl);
    super.dispose();
  }

  Alignment _alignmentFor(WebImageCropPosition position) {
    return switch (position) {
      WebImageCropPosition.top => Alignment.topCenter,
      WebImageCropPosition.center => Alignment.center,
      WebImageCropPosition.bottom => Alignment.bottomCenter,
      WebImageCropPosition.left => Alignment.centerLeft,
      WebImageCropPosition.right => Alignment.centerRight,
    };
  }

  String _labelFor(WebImageCropPosition position) {
    return switch (position) {
      WebImageCropPosition.top => 'Arriba',
      WebImageCropPosition.center => 'Centro',
      WebImageCropPosition.bottom => 'Abajo',
      WebImageCropPosition.left => 'Izquierda',
      WebImageCropPosition.right => 'Derecha',
    };
  }

  @override
  Widget build(BuildContext context) {
    final availableWidth = (MediaQuery.sizeOf(context).width - 124).clamp(
      240.0,
      420.0,
    );
    final previewWidth = widget.shape == BoxShape.circle
        ? availableWidth.clamp(220.0, 280.0)
        : availableWidth;
    final previewHeight = widget.shape == BoxShape.circle
        ? previewWidth
        : previewWidth / widget.aspectRatio;
    final positions = WebImageCropPosition.values;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.borderStrongSoft),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
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
                                HelpTitle(
                                  title: widget.title,
                                  helpText: widget.subtitle,
                                  style: GoogleFonts.outfit(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: context.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.subtitle,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 15,
                                    height: 1.3,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, size: 26),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          width: previewWidth,
                          height: previewHeight,
                          decoration: BoxDecoration(
                            color: context.bgSubtle,
                            shape: widget.shape,
                            borderRadius: widget.shape == BoxShape.circle
                                ? null
                                : BorderRadius.circular(18),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Transform.scale(
                            scale: _zoom,
                            child: Image.network(
                              _objectUrl,
                              fit: BoxFit.cover,
                              alignment: _alignmentFor(_position),
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      HelpTitle(
                        title: 'Zoom',
                        helpText: 'Ajusta el acercamiento de la imagen.',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.primary,
                          thumbColor: AppColors.primary,
                          inactiveTrackColor: context.borderStrongSoft,
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                        ),
                        child: Slider(
                          min: 1,
                          max: 2.4,
                          divisions: 7,
                          value: _zoom,
                          onChanged: (value) => setState(() => _zoom = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      HelpTitle(
                        title: 'Posición',
                        helpText:
                            'Elige el encuadre de la imagen dentro del recorte.',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: positions.map((position) {
                          final selected = _position == position;
                          return _ImagePositionChip(
                            label: _labelFor(position),
                            selected: selected,
                            onTap: () => setState(() => _position = position),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(color: context.borderStrongSoft, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 210,
                      child: TapLoopButton(
                        label: 'Usar imagen',
                        height: 52,
                        borderRadius: 999,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        onPressed: () => Navigator.pop(
                          context,
                          _ImageAdjustmentResult(
                            zoom: _zoom,
                            position: _position,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePositionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ImagePositionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapLoopPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      hoverColor: TapLoopMotion.hoverSurfaceColor(context),
      child: AnimatedContainer(
        duration: TapLoopMotion.fast,
        curve: TapLoopMotion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : context.bgCard,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppColors.primary : context.borderStrongSoft,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(
                Icons.check_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.primary : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedProfileOption extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  static const _verifiedBlue = Color(0xFF2F5BFF);
  static const _verifiedInactive = Color(0xFF94A3B8);

  const _VerifiedProfileOption({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? _verifiedBlue : _verifiedInactive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled
              ? _verifiedBlue.withValues(alpha: 0.24)
              : context.borderStrongSoft,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: enabled ? 0.1 : 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_rounded, size: 21, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Verificado',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: enabled ? 0.1 : 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Premium',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Muestra una insignia junto a tu nombre público.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _EditorVisibilitySwitch(
            value: enabled,
            onChanged: onChanged,
            activeColor: _verifiedBlue,
            inactiveColor: _verifiedInactive,
          ),
        ],
      ),
    );
  }
}

// ─── Contact Tab ─────────────────────────────────────────────────────────────

class _ContactTab extends StatefulWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;
  final ValueChanged<ContactType> onAdd;
  final ValueChanged<ContactItemModel> onEdit;
  const _ContactTab({
    required this.card,
    required this.onChanged,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_ContactTab> createState() => _ContactTabState();
}

class _ContactTabState extends State<_ContactTab> {
  @override
  Widget build(BuildContext context) {
    final contacts = [...widget.card.contactItems]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final usedIds = <String>{};
    final rows = <({ContactType type, ContactItemModel? item})>[];
    for (final type in ContactType.values) {
      ContactItemModel? match;
      for (final item in contacts) {
        if (item.type == type && !usedIds.contains(item.id)) {
          match = item;
          usedIds.add(item.id);
          break;
        }
      }
      rows.add((type: type, item: match));
    }
    for (final item in contacts) {
      if (!usedIds.contains(item.id)) {
        rows.add((type: item.type, item: item));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Información de contacto',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Completa tus datos y decide cuáles aparecerán como acciones en tu perfil público.',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TapLoopButton(
                    label: 'Añadir contacto',
                    width: 224,
                    height: 46,
                    borderRadius: 999,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: () => widget.onAdd(ContactType.phone),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ...rows.map((row) {
                final item = row.item;
                return _ContactRow(
                  key: ValueKey(item?.id ?? 'contact_empty_${row.type.name}'),
                  type: row.type,
                  item: item,
                  onAdd: () => widget.onAdd(row.type),
                  onEdit: item == null ? null : () => widget.onEdit(item),
                  onToggle: item == null
                      ? null
                      : (val) {
                          final updated = contacts
                              .map(
                                (c) => c.id == item.id
                                    ? c.copyWith(isVisible: val)
                                    : c,
                              )
                              .toList();
                          widget.onChanged(
                            widget.card.copyWith(contactItems: updated),
                          );
                        },
                  onDelete: item == null
                      ? null
                      : () {
                          final updated = contacts
                              .where((c) => c.id != item.id)
                              .toList();
                          widget.onChanged(
                            widget.card.copyWith(contactItems: updated),
                          );
                        },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ContactType type;
  final ContactItemModel? item;
  final VoidCallback onAdd;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _ContactRow({
    super.key,
    required this.type,
    required this.item,
    required this.onAdd,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final active = item != null;
    final visible = item?.isVisible ?? false;
    final value = item?.value.trim();
    final label = item?.displayLabel ?? _contactTypeLabel(type);
    final contactColor = _contactTypeColor(type);
    final displayedValue = active && value != null && value.isNotEmpty
        ? value
        : _contactTypePlaceholder(type);
    final statusText = active ? (visible ? 'Visible' : 'Oculto') : 'Sin dato';
    final statusColor = active
        ? (visible ? AppColors.success : context.textMuted)
        : context.textMuted;
    final rowTap = active ? onEdit : onAdd;
    Widget separator({double height = 32}) =>
        Container(width: 1, height: height, color: const Color(0xFFE1E8F0));
    Widget statusControls() => SizedBox(
      width: active ? 128 : 84,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: _EditorVisibilitySwitch(
                value: visible,
                activeColor: AppColors.success,
                onChanged: onToggle ?? (_) => onAdd(),
              ),
            ),
          ],
        ],
      ),
    );
    Widget actionButtons() => SizedBox(
      width: active ? 66 : 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: active ? 'Editar contacto' : 'Añadir contacto',
            onPressed: active ? onEdit : onAdd,
            constraints: const BoxConstraints.tightFor(width: 32, height: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              active ? Icons.edit_outlined : Icons.add_rounded,
              color: const Color(0xFF334155),
              size: 21,
            ),
          ),
          if (active)
            IconButton(
              tooltip: 'Eliminar contacto',
              onPressed: onDelete,
              constraints: const BoxConstraints.tightFor(width: 32, height: 34),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 23,
              ),
            ),
        ],
      ),
    );
    Widget buildIcon() => SizedBox(
      width: 28,
      height: 34,
      child: Center(
        child: _contactTypeIcon(type, color: contactColor, size: 25),
      ),
    );
    Widget buildLeading(double labelWidth) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildIcon(),
        const SizedBox(width: 10),
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: active ? const Color(0xFF0F172A) : context.textMuted,
            ),
          ),
        ),
      ],
    );
    Widget buildValue() => Text(
      displayedValue,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.dmSans(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: active ? const Color(0xFF475569) : context.textMuted,
      ),
    );
    var hoveringRow = false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StatefulBuilder(
        builder: (context, setHover) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setHover(() => hoveringRow = true),
            onExit: (_) => setHover(() => hoveringRow = false),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: rowTap,
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: hoveringRow
                        ? TapLoopMotion.hoverSurfaceColor(context)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: hoveringRow
                          ? const Color(0xFFCFE0F2)
                          : const Color(0xFFE0E8F1),
                      width: 1.2,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 690;
                      final leadingWidth = compact ? 82.0 : 98.0;
                      final valueGap = compact ? 9.0 : 14.0;
                      final statusGap = compact ? 7.0 : 10.0;

                      return Row(
                        children: [
                          buildLeading(leadingWidth),
                          SizedBox(width: valueGap),
                          separator(),
                          SizedBox(width: valueGap),
                          Expanded(child: buildValue()),
                          SizedBox(width: statusGap),
                          statusControls(),
                          SizedBox(width: statusGap),
                          separator(),
                          const SizedBox(width: 8),
                          actionButtons(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Social Tab ──────────────────────────────────────────────────────────────

class _SocialTab extends StatefulWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;
  final VoidCallback onAdd;
  final ValueChanged<SocialLinkModel> onEdit;
  const _SocialTab({
    required this.card,
    required this.onChanged,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_SocialTab> createState() => _SocialTabState();
}

class _SocialTabState extends State<_SocialTab> {
  void _onReorder(List<SocialLinkModel> baseItems, int oldIndex, int newIndex) {
    final items = [...baseItems];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    final normalized = items
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key))
        .toList();
    widget.onChanged(widget.card.copyWith(socialLinks: normalized));
  }

  @override
  Widget build(BuildContext context) {
    final socials = [...widget.card.socialLinks]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
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
                          'Enlaces principales',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gestiona los enlaces que aparecen en tu perfil. Ordénalos, edítalos y destaca los importantes.',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.bgSubtle,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: context.borderStrongSoft),
                    ),
                    child: Text(
                      '${socials.length}/8',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TapLoopButton(
                  label: 'Agregar enlace',
                  width: 220,
                  height: 50,
                  borderRadius: 999,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  onPressed: widget.onAdd,
                ),
              ),
              const SizedBox(height: 18),
              if (socials.isEmpty)
                _EmptyState(
                  message: 'Sin enlaces visibles',
                  hint: 'Añade WhatsApp, sitio web, Instagram u otro canal.',
                )
              else ...[
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: socials.length,
                  onReorder: (oldIndex, newIndex) =>
                      _onReorder(socials, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final link = socials[i];
                    return _SocialRow(
                      key: ValueKey('social_${link.id}'),
                      index: i,
                      link: link,
                      onEdit: () => widget.onEdit(link),
                      onDelete: () {
                        final updated = socials
                            .where((s) => s.id != link.id)
                            .toList();
                        widget.onChanged(
                          widget.card.copyWith(socialLinks: updated),
                        );
                      },
                      onToggle: (val) {
                        final updated = socials
                            .map(
                              (s) => s.id == link.id
                                  ? s.copyWith(isVisible: val)
                                  : s,
                            )
                            .toList();
                        widget.onChanged(
                          widget.card.copyWith(socialLinks: updated),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                _DragHint(
                  text: 'Arrastra los enlaces para cambiar su prioridad.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  final int index;
  final SocialLinkModel link;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SocialRow({
    super.key,
    required this.index,
    required this.link,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    var hoveringRow = false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StatefulBuilder(
        builder: (context, setHover) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setHover(() => hoveringRow = true),
            onExit: (_) => setHover(() => hoveringRow = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: hoveringRow
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: hoveringRow
                      ? context.borderStrongSoft.withValues(alpha: 0.92)
                      : context.borderStrongSoft,
                ),
              ),
              child: Row(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: context.textPrimary,
                        size: 25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _socialPlatformIcon(
                    link.platform,
                    color: _socialPlatformColor(link.platform),
                    size: 29,
                    iconKey: link.iconKey,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.label,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: link.isVisible
                                ? context.textPrimary
                                : context.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          link.url,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: _EditorVisibilitySwitch(
                      value: link.isVisible,
                      onChanged: onToggle,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar enlace',
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit_outlined,
                      color: context.textSecondary,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Eliminar enlace',
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DragHint extends StatelessWidget {
  final String text;
  const _DragHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.drag_indicator_rounded, size: 15, color: context.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorVisibilitySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  final Color? inactiveColor;
  const _EditorVisibilitySwitch({
    required this.value,
    required this.onChanged,
    this.activeColor = AppColors.primary,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final offColor = inactiveColor ?? context.textMuted;
    return Transform.scale(
      scale: 0.86,
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: activeColor.withValues(alpha: 0.26),
        activeThumbColor: activeColor,
        inactiveTrackColor: offColor.withValues(alpha: 0.22),
        inactiveThumbColor: offColor,
      ),
    );
  }
}

class _EditorDialogLabel extends StatelessWidget {
  final String text;
  const _EditorDialogLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: context.textPrimary,
      ),
    );
  }
}

class _SuggestedUsePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SuggestedUsePill({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: TapLoopMotion.fast,
              curve: TapLoopMotion.standard,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: hovering
                      ? AppColors.primary
                      : context.borderStrongSoft,
                  width: hovering ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: hovering ? AppColors.primary : context.textPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: hovering
                            ? AppColors.primary
                            : context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FieldChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _FieldChip({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        final color = selected || hovering
            ? AppColors.primary
            : context.textSecondary;
        return MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: TapLoopMotion.fast,
              curve: TapLoopMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected || hovering
                      ? AppColors.primary
                      : context.borderStrongSoft,
                  width: selected || hovering ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? context.textPrimary
                          : hovering
                          ? AppColors.primary
                          : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _contactTypeIcon(
  ContactType type, {
  required Color color,
  required double size,
}) {
  if (type == ContactType.whatsapp) {
    return FaIcon(FontAwesomeIcons.whatsapp, color: color, size: size);
  }
  final icon = switch (type) {
    ContactType.phone => Icons.phone_outlined,
    ContactType.email => Icons.email_outlined,
    ContactType.address => Icons.location_on_outlined,
    ContactType.website => Icons.language_rounded,
    ContactType.whatsapp => Icons.chat_outlined,
  };
  return Icon(icon, color: color, size: size);
}

Color _contactTypeColor(ContactType type) {
  return switch (type) {
    ContactType.phone => const Color(0xFF16A34A),
    ContactType.whatsapp => const Color(0xFF25D366),
    ContactType.email => const Color(0xFFEF4444),
    ContactType.address => const Color(0xFFF59E0B),
    ContactType.website => const Color(0xFF2563EB),
  };
}

String _contactTypeLabel(ContactType type) {
  return switch (type) {
    ContactType.phone => 'Teléfono',
    ContactType.whatsapp => 'WhatsApp',
    ContactType.email => 'Email',
    ContactType.address => 'Dirección',
    ContactType.website => 'Sitio web',
  };
}

String _contactTypePlaceholder(ContactType type) {
  return switch (type) {
    ContactType.phone => '+52 55 1234 5678',
    ContactType.whatsapp => '+52 55 1234 5678',
    ContactType.email => 'tu@email.com',
    ContactType.address => 'Ciudad de México, CDMX',
    ContactType.website => 'https://tuwebsite.com',
  };
}

Widget _socialPlatformIcon(
  SocialPlatform platform, {
  required Color color,
  required double size,
  String? iconKey,
}) {
  final FaIconData? brandIcon = switch (platform) {
    SocialPlatform.linkedin => FontAwesomeIcons.linkedinIn,
    SocialPlatform.instagram => FontAwesomeIcons.instagram,
    SocialPlatform.facebook => FontAwesomeIcons.facebookF,
    SocialPlatform.tiktok => FontAwesomeIcons.tiktok,
    SocialPlatform.twitter => FontAwesomeIcons.xTwitter,
    SocialPlatform.youtube => FontAwesomeIcons.youtube,
    SocialPlatform.whatsapp => FontAwesomeIcons.whatsapp,
    SocialPlatform.github => FontAwesomeIcons.github,
    SocialPlatform.calendly || SocialPlatform.custom => null,
  };
  if (brandIcon != null) {
    return FaIcon(brandIcon, color: color, size: size);
  }
  final icon = switch (platform) {
    SocialPlatform.calendly => Icons.event_available_outlined,
    SocialPlatform.custom => customSocialIconData(iconKey),
    SocialPlatform.linkedin ||
    SocialPlatform.instagram ||
    SocialPlatform.facebook ||
    SocialPlatform.tiktok ||
    SocialPlatform.twitter ||
    SocialPlatform.youtube ||
    SocialPlatform.whatsapp ||
    SocialPlatform.github => Icons.link_rounded,
  };
  return Icon(icon, color: color, size: size);
}

Color _socialPlatformColor(SocialPlatform platform) {
  return switch (platform) {
    SocialPlatform.instagram => const Color(0xFFE83E7C),
    SocialPlatform.facebook => const Color(0xFF2563EB),
    SocialPlatform.tiktok => const Color(0xFF00D1C7),
    SocialPlatform.youtube => const Color(0xFFEF4444),
    SocialPlatform.whatsapp => const Color(0xFF25D366),
    SocialPlatform.twitter => const Color(0xFF1D9BF0),
    SocialPlatform.linkedin => const Color(0xFF0A66C2),
    SocialPlatform.calendly => const Color(0xFF006BFF),
    SocialPlatform.github => const Color(0xFF6E5494),
    SocialPlatform.custom => AppColors.primary,
  };
}

class _DesignTab extends StatelessWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;
  const _DesignTab({required this.card, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final settingsContent = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final titleBlock = Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.palette_outlined,
                            size: 22,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Diseño de tu perfil',
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Elige un estilo profesional y personaliza tu perfil en segundos.',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
                final tipsButton = _DesignTipsButton(onTap: () {});
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [titleBlock]),
                      const SizedBox(height: 14),
                      tipsButton,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleBlock, const SizedBox(width: 18), tipsButton],
                );
              },
            ),
            const SizedBox(height: 26),
            _ProfileDesignSection(card: card, onChanged: onChanged),
            const SizedBox(height: 22),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Identidad visual',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DesignSectionCard(
              title: 'Color principal',
              child: _DesignColorPicker(
                color: card.primaryColor,
                palette: _primaryDesignPalette,
                onChanged: (c) => onChanged(card.copyWith(primaryColor: c)),
              ),
            ),
            const SizedBox(height: 14),
            _DesignSectionCard(
              title: 'Color de iconos',
              child: _DesignColorPicker(
                color: card.iconColor,
                palette: _accentDesignPalette,
                onChanged: (c) => onChanged(card.copyWith(iconColor: c)),
              ),
            ),
            const SizedBox(height: 14),
            _DesignSectionCard(
              title: 'Fondo',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _DesignChoiceChip(
                    label: 'Claro',
                    selected: !_isDarkDesignColor(card.bgColor ?? Colors.white),
                    onTap: () => onChanged(
                      card.copyWith(
                        bgStyle: CardBgStyle.plain,
                        bgColor: Colors.white,
                      ),
                    ),
                  ),
                  _DesignChoiceChip(
                    label: 'Oscuro',
                    selected: _isDarkDesignColor(card.bgColor ?? Colors.white),
                    onTap: () => onChanged(
                      card.copyWith(
                        bgStyle: CardBgStyle.plain,
                        bgColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _DesignSectionCard(
              title: 'Fondo y portada sin imagen',
              child: _DesignColorPicker(
                color: card.bgColor ?? Colors.white,
                palette: _backgroundDesignPalette,
                onChanged: (c) => onChanged(card.copyWith(bgColor: c)),
              ),
            ),
            const SizedBox(height: 14),
            _DesignSectionCard(
              title: 'Efecto de fondo',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: CardBgStyle.values.map((s) {
                  return _BgStyleChip(
                    style: s,
                    selected: card.bgStyle == s,
                    onTap: () => onChanged(card.copyWith(bgStyle: s)),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );

    if (isDesktop) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: settingsContent,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Center(
              child: DigitalProfilePreview(
                card: card,
                width: 138,
                enableInnerScroll: false,
              ),
            ),
          ),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 24),
          settingsContent,
        ],
      ),
    );
  }
}

const _primaryDesignPalette = [
  AppColors.primary,
  Color(0xFF10B981),
  Color(0xFF7C3AED),
  Color(0xFFF43F5E),
  Color(0xFFF97316),
  Colors.black,
];

const _accentDesignPalette = [
  AppColors.primary,
  Color(0xFF06B6D4),
  Color(0xFF84CC16),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Colors.black,
];

const _backgroundDesignPalette = [
  Colors.white,
  Color(0xFFF4F4F6),
  Color(0xFFF0F4FF),
  Color(0xFFF0FFF4),
  Color(0xFFFFF8F0),
  Color(0xFF0D0D0D),
  Color(0xFF1C1C2E),
  Color(0xFF6C4FE8),
];

bool _isDarkDesignColor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
}

String _designHex(Color color) {
  final argb = color.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _DesignTipsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DesignTipsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: TapLoopMotion.fast,
              curve: TapLoopMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: hovering
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Consejos de diseño',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesignSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DesignSectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderStrongSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: title,
            helpText: 'Configura las opciones de $title en esta tarjeta.',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DesignColorPicker extends StatelessWidget {
  final Color color;
  final List<Color> palette;
  final ValueChanged<Color> onChanged;

  const _DesignColorPicker({
    required this.color,
    required this.palette,
    required this.onChanged,
  });

  Future<void> _openColorDialog(BuildContext context) async {
    final selected = await showDialog<Color>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: _AdvancedColorDialog(initialColor: color),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapLoopPressable(
          onTap: () => _openColorDialog(context),
          borderRadius: BorderRadius.circular(13),
          hoverColor: TapLoopMotion.hoverSurfaceColor(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: context.borderStrongSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: context.borderStrongSoft),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _designHex(color),
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: context.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: palette.map((c) {
            return _ColorDot(
              color: c,
              selected: color == c,
              onTap: () => onChanged(c),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _AdvancedColorDialog extends StatefulWidget {
  final Color initialColor;

  const _AdvancedColorDialog({required this.initialColor});

  @override
  State<_AdvancedColorDialog> createState() => _AdvancedColorDialogState();
}

class _AdvancedColorDialogState extends State<_AdvancedColorDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;
  bool _syncingHex = false;

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexCtrl = TextEditingController(text: _designHex(widget.initialColor));
    _hexCtrl.addListener(_onHexChanged);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _syncHex() {
    _syncingHex = true;
    _hexCtrl.text = _designHex(_color);
    _hexCtrl.selection = TextSelection.collapsed(offset: _hexCtrl.text.length);
    _syncingHex = false;
  }

  void _onHexChanged() {
    if (_syncingHex) return;
    final parsed = _parseDesignHex(_hexCtrl.text);
    if (parsed == null) return;
    setState(() => _hsv = HSVColor.fromColor(parsed));
  }

  void _setSv(Offset localPosition, Size size) {
    final saturation = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - (localPosition.dy / size.height)).clamp(0.0, 1.0);
    setState(() {
      _hsv = _hsv.withSaturation(saturation).withValue(value);
      _syncHex();
    });
  }

  void _setHue(Offset localPosition, double width) {
    final hue = ((localPosition.dx / width).clamp(0.0, 1.0)) * 360;
    setState(() {
      _hsv = _hsv.withHue(hue);
      _syncHex();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderStrongSoft),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.maxWidth.clamp(260.0, 340.0);
                    return Center(
                      child: GestureDetector(
                        onPanDown: (details) =>
                            _setSv(details.localPosition, Size(size, size)),
                        onPanUpdate: (details) =>
                            _setSv(details.localPosition, Size(size, size)),
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.borderStrongSoft),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(color: hueColor),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left:
                                    (_hsv.saturation * size).clamp(0.0, size) -
                                    14,
                                top:
                                    ((1 - _hsv.value) * size).clamp(0.0, size) -
                                    14,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: _color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      onPanDown: (details) =>
                          _setHue(details.localPosition, width),
                      onPanUpdate: (details) =>
                          _setHue(details.localPosition, width),
                      child: SizedBox(
                        height: 30,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF0000),
                                    Color(0xFFFFFF00),
                                    Color(0xFF00FF00),
                                    Color(0xFF00FFFF),
                                    Color(0xFF0000FF),
                                    Color(0xFFFF00FF),
                                    Color(0xFFFF0000),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left:
                                  ((_hsv.hue / 360) * width).clamp(0.0, width) -
                                  14,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: hueColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hexCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: GoogleFonts.outfit(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: context.bgCard,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: context.borderStrongSoft,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: context.borderStrongSoft,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: _color,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.borderStrongSoft),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Copiar color',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _designHex(_color)),
                      );
                      TapLoopToast.show(
                        context,
                        'Color copiado.',
                        TapLoopToastType.success,
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 22),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 180,
                      child: TapLoopButton(
                        label: 'Aplicar',
                        height: 52,
                        borderRadius: 999,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        onPressed: () => Navigator.pop(context, _color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color? _parseDesignHex(String input) {
  final clean = input.replaceAll('#', '').trim();
  if (clean.length != 6) return null;
  final value = int.tryParse('FF$clean', radix: 16);
  return value == null ? null : Color(value);
}

class _DesignChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DesignChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: TapLoopMotion.fast,
              curve: TapLoopMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : context.borderStrongSoft,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.primary : context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BgStyleChip extends StatelessWidget {
  final CardBgStyle style;
  final bool selected;
  final VoidCallback onTap;
  const _BgStyleChip({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (style) {
      CardBgStyle.plain => 'Liso',
      CardBgStyle.gradient => 'Degradado',
      CardBgStyle.mesh => 'Malla',
      CardBgStyle.stripes => 'Rayas',
    };
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? context.textPrimary
                    : hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? context.textPrimary
                      : hovering
                      ? context.borderStrongSoft.withValues(alpha: 0.9)
                      : context.borderStrongSoft,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? (context.isDark ? Colors.black : Colors.white)
                      : context.textSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileDesignSection extends StatelessWidget {
  final DigitalCardModel card;
  final ValueChanged<DigitalCardModel> onChanged;

  const _ProfileDesignSection({required this.card, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = const [CardProfileDesign.classic, CardProfileDesign.modern];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderStrongSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HelpTitle(
            title: 'Estilo de perfil',
            helpText:
                'Selecciona la apariencia pública que usará esta tarjeta digital.',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Elige cómo se organizará la información de tu perfil',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 680;
              final chips = options.map((design) {
                return _ProfileDesignChip(
                  design: design,
                  selected: card.profileDesign == design,
                  onTap: () => onChanged(
                    card.copyWith(
                      profileDesign: design,
                      layoutStyle: design.compatibleLayoutStyle,
                    ),
                  ),
                );
              }).toList();

              if (stacked) {
                return Column(
                  children: [
                    for (var i = 0; i < chips.length; i++) ...[
                      chips[i],
                      if (i != chips.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: chips[0]),
                  const SizedBox(width: 12),
                  Expanded(child: chips[1]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileDesignChip extends StatelessWidget {
  final CardProfileDesign design;
  final bool selected;
  final VoidCallback onTap;
  const _ProfileDesignChip({
    required this.design,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (design) {
      CardProfileDesign.classic => Icons.person_outline,
      CardProfileDesign.modern => Icons.grid_view_rounded,
    };
    final label = switch (design) {
      CardProfileDesign.classic => 'Clásico',
      CardProfileDesign.modern => 'Moderno',
    };
    final desc = switch (design) {
      CardProfileDesign.classic => 'Información centrada',
      CardProfileDesign.modern => 'Acciones y contenido primero',
    };
    final iconColor = context.textSecondary;
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 86),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : hovering
                      ? context.borderStrongSoft.withValues(alpha: 0.9)
                      : context.borderStrongSoft,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 34),
                    child: Row(
                      children: [
                        Icon(icon, size: 30, color: iconColor),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditorInlineMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _EditorInlineMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 12),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        HelpTitle(
          title: label,
          helpText: 'Métrica del perfil digital para $label.',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.transparent
                    : hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : context.borderStrongSoft,
                  width: selected ? 2 : 1,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.borderSoft),
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        color: _isDarkDesignColor(color)
                            ? Colors.white
                            : AppColors.primary,
                        size: 13,
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomColorPanel extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _CustomColorPanel({required this.color, required this.onChanged});

  @override
  State<_CustomColorPanel> createState() => _CustomColorPanelState();
}

class _CustomColorPanelState extends State<_CustomColorPanel> {
  late final TextEditingController _hexCtrl;
  bool _settingFromSlider = false;

  static String _toHex(Color c) {
    final argb = c.toARGB32();
    return ((argb) & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  static Color? _parseHex(String input) {
    final clean = input.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _hexCtrl = TextEditingController(text: _toHex(widget.color));
    _hexCtrl.addListener(_onHexChanged);
  }

  @override
  void didUpdateWidget(covariant _CustomColorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_settingFromSlider && oldWidget.color != widget.color) {
      final newHex = _toHex(widget.color);
      if (_hexCtrl.text.toUpperCase() != newHex) {
        _hexCtrl.removeListener(_onHexChanged);
        _hexCtrl.text = newHex;
        _hexCtrl.addListener(_onHexChanged);
      }
    }
  }

  void _onHexChanged() {
    if (_hexCtrl.text.isEmpty) return;
    final parsed = _parseHex(_hexCtrl.text);
    if (parsed != null) {
      _settingFromSlider = false;
      widget.onChanged(parsed);
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final argb = widget.color.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Custom',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.borderColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Hex Input ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 32,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.bgSubtle,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  '#',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                    letterSpacing: 1.8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── RGB Sliders ──────────────────────────────────────────────
          _ColorSlider(
            label: 'R',
            value: r.toDouble(),
            activeColor: Colors.red,
            onChanged: (v) {
              _settingFromSlider = true;
              widget.onChanged(Color.fromARGB(a, v.round(), g, b));
            },
          ),
          _ColorSlider(
            label: 'G',
            value: g.toDouble(),
            activeColor: Colors.green,
            onChanged: (v) {
              _settingFromSlider = true;
              widget.onChanged(Color.fromARGB(a, r, v.round(), b));
            },
          ),
          _ColorSlider(
            label: 'B',
            value: b.toDouble(),
            activeColor: Colors.blue,
            onChanged: (v) {
              _settingFromSlider = true;
              widget.onChanged(Color.fromARGB(a, r, g, v.round()));
            },
          ),
        ],
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color activeColor;
  final ValueChanged<double> onChanged;
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(
              context,
            ).copyWith(activeTrackColor: activeColor, thumbColor: activeColor),
            child: Slider(min: 0, max: 255, value: value, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

// ─── Save Button ──────────────────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  final bool unsaved;
  final bool saving;
  final Future<void> Function() onSave;

  const _SaveButton({
    required this.unsaved,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.unsaved && !widget.saving;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      // The whole pill is the hit area (opaque): with the default behavior
      // only taps landing exactly on the label/icon glyphs registered, so
      // it often took several clicks to save.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => widget.onSave() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.saving
                ? AppColors.success.withValues(alpha: 0.1)
                : widget.unsaved
                ? null
                : context.bgSubtle,
            gradient: widget.unsaved && !widget.saving
                ? LinearGradient(
                    colors: _hovered
                        ? const [Color(0xFFFF6A2A), Color(0xFFFF9A52)]
                        : const [Color(0xFFFF5A1F), Color(0xFFFF8A3D)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.unsaved && !widget.saving
                  ? Colors.transparent
                  : context.borderStrongSoft,
            ),
            boxShadow: enabled && _hovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: widget.saving
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TapLoopProgressIndicator(color: AppColors.success),
                      const SizedBox(width: 8),
                      Text(
                        'Guardando...',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.unsaved) ...[
                        const Icon(
                          Icons.save_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.unsaved ? 'Guardar cambios' : 'Guardado',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: widget.unsaved
                              ? Colors.white
                              : context.textMuted,
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

// ─── Add Contact Sheet ────────────────────────────────────────────────────────

class _AddContactSheet extends StatefulWidget {
  final ValueChanged<ContactItemModel> onSubmit;
  final ContactItemModel? initialItem;
  final ContactType initialType;
  final bool isDialog;
  const _AddContactSheet({
    required this.onSubmit,
    this.initialItem,
    this.initialType = ContactType.phone,
    this.isDialog = false,
  });

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  ContactType _type = ContactType.phone;
  final _valueCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _isVisible = true;
  String _valueError = '';
  String _labelError = '';

  bool get _isEditing => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    if (initial != null) {
      _type = initial.type;
      _valueCtrl.text = initial.value;
      _labelCtrl.text = initial.label ?? '';
      _isVisible = initial.isVisible;
    } else {
      _type = widget.initialType;
    }
    _valueCtrl.addListener(() => setState(() {}));
    _labelCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  bool _validateFields() {
    setState(() {
      _valueError = '';
      _labelError = '';
    });

    final value = _valueCtrl.text.trim();
    final label = _labelCtrl.text.trim();
    bool hasError = false;

    // Validar el campo principal según el tipo
    ValidationResult valueValidation;
    switch (_type) {
      case ContactType.phone:
      case ContactType.whatsapp:
        valueValidation = FieldValidators.validateContactPhone(value);
        break;
      case ContactType.email:
        valueValidation = FieldValidators.validateContactEmail(value);
        break;
      case ContactType.website:
        valueValidation = FieldValidators.validateUrl(value);
        if (valueValidation.isValid && value.isNotEmpty) {
          final lengthValidation = FieldValidators.validateMaxLength(
            value,
            FieldValidators.contactPrimaryMaxLength,
            'El sitio web',
          );
          valueValidation = lengthValidation;
        }
        break;
      case ContactType.address:
        valueValidation = FieldValidators.validateContactText(value);
        break;
    }

    if (!valueValidation.isValid) {
      setState(() => _valueError = valueValidation.errorMessage ?? '');
      hasError = true;
    }

    // Validar etiqueta
    final labelValidation = FieldValidators.validateSocialLabel(label);
    if (!labelValidation.isValid) {
      setState(() => _labelError = labelValidation.errorMessage ?? '');
      hasError = true;
    }

    return !hasError;
  }

  static const _hints = {
    ContactType.phone: '+52 55 1234 5678',
    ContactType.whatsapp: '+52 55 1234 5678',
    ContactType.email: 'tu@email.com',
    ContactType.address: 'Ciudad de México, CDMX',
    ContactType.website: 'https://tuwebsite.com',
  };

  static const _labels = {
    ContactType.phone: 'Teléfono',
    ContactType.whatsapp: 'WhatsApp',
    ContactType.email: 'Email',
    ContactType.address: 'Dirección',
    ContactType.website: 'Sitio web',
  };

  @override
  Widget build(BuildContext context) {
    final bottomPad = widget.isDialog
        ? 28.0
        : MediaQuery.of(context).viewInsets.bottom + 28;

    final contactCards = GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: widget.isDialog ? 2 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: widget.isDialog ? 1.85 : 1.75,
      children: ContactType.values.map((type) {
        final active = _type == type;
        var hoveringCard = false;
        return StatefulBuilder(
          builder: (context, setHover) {
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setHover(() => hoveringCard = true),
              onExit: (_) => setHover(() => hoveringCard = false),
              child: GestureDetector(
                onTap: () => setState(() => _type = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : hoveringCard
                        ? TapLoopMotion.hoverSurfaceColor(context)
                        : context.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? AppColors.primary
                          : hoveringCard
                          ? context.borderStrongSoft
                          : context.borderStrongSoft,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _contactTypeIcon(
                              type,
                              size: 24,
                              color: active
                                  ? Colors.white
                                  : _contactTypeColor(type),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _labels[type]!,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: active
                                    ? Colors.white
                                    : context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (active)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditInputField(
          label: 'Etiqueta visible (opcional)',
          controller: _labelCtrl,
          hint: 'Ej: Oficina',
          error: _labelError,
          maxLength: FieldValidators.contactSecondaryMaxLength,
        ),
        const SizedBox(height: 16),
        _EditInputField(
          label: _labels[_type]!,
          controller: _valueCtrl,
          hint: _hints[_type],
          error: _valueError,
          maxLength: FieldValidators.contactPrimaryMaxLength,
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderStrongSoft),
          ),
          child: Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visible en el perfil público',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Las personas podrán usar este medio desde tu tarjeta.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _EditorVisibilitySwitch(
                value: _isVisible,
                onChanged: (value) => setState(() => _isVisible = value),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      constraints: widget.isDialog
          ? const BoxConstraints(maxHeight: 760)
          : const BoxConstraints(),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(30)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(30, 26, 30, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isDialog)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.borderStrongSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Editar contacto' : 'Añadir contacto',
                        style: GoogleFonts.outfit(
                          fontSize: widget.isDialog ? 30 : 22,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Elige el medio y completa el dato que aparecerá en tu perfil.',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isDialog)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 28),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (widget.isDialog)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 392,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _EditorDialogLabel('Medio de contacto'),
                        const SizedBox(height: 12),
                        contactCards,
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 282,
                    margin: const EdgeInsets.symmetric(horizontal: 26),
                    color: context.borderStrongSoft,
                  ),
                  Expanded(child: fields),
                ],
              )
            else ...[
              _EditorDialogLabel('Medio de contacto'),
              const SizedBox(height: 12),
              contactCards,
              const SizedBox(height: 20),
              fields,
            ],
            const SizedBox(height: 28),
            Divider(color: context.borderStrongSoft, height: 1),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 220,
                  child: TapLoopButton(
                    label: _isEditing ? 'Guardar cambios' : 'Añadir',
                    height: 54,
                    borderRadius: 999,
                    icon: Icon(
                      _isEditing ? Icons.save_outlined : Icons.add_rounded,
                      size: 18,
                    ),
                    onPressed: () {
                      if (!_validateFields()) {
                        TapLoopToast.show(
                          context,
                          'Por favor, verifica los campos marcados.',
                          TapLoopToastType.error,
                        );
                        return;
                      }

                      if (_valueCtrl.text.trim().isEmpty) {
                        TapLoopToast.show(
                          context,
                          '${_labels[_type]} es requerido.',
                          TapLoopToastType.error,
                        );
                        return;
                      }

                      final initial = widget.initialItem;
                      widget.onSubmit(
                        ContactItemModel(
                          id:
                              initial?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          type: _type,
                          value: _valueCtrl.text.trim(),
                          label: _labelCtrl.text.trim().isEmpty
                              ? null
                              : _labelCtrl.text.trim(),
                          isVisible: _isVisible,
                          sortOrder: initial?.sortOrder ?? 0,
                        ),
                      );
                      if (!widget.isDialog) Navigator.pop(context);
                      if (widget.isDialog && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Social Sheet ─────────────────────────────────────────────────────────

class _AddSocialSheet extends StatefulWidget {
  final ValueChanged<SocialLinkModel> onSubmit;
  final SocialLinkModel? initialLink;
  final bool isDialog;
  const _AddSocialSheet({
    required this.onSubmit,
    this.initialLink,
    this.isDialog = false,
  });

  @override
  State<_AddSocialSheet> createState() => _AddSocialSheetState();
}

class _AddSocialSheetState extends State<_AddSocialSheet> {
  SocialPlatform _platform = SocialPlatform.linkedin;
  final _urlCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _isVisible = true;
  String _customIconKey = 'link';
  String _urlError = '';
  String _labelError = '';

  bool get _isEditing => widget.initialLink != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLink;
    if (initial != null) {
      _platform = initial.platform;
      _urlCtrl.text = initial.url;
      _labelCtrl.text = initial.customLabel ?? '';
      _customIconKey = initial.iconKey ?? 'link';
      _isVisible = initial.isVisible;
    }
    _urlCtrl.addListener(() => setState(() {}));
    _labelCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  bool _validateFields() {
    setState(() {
      _urlError = '';
      _labelError = '';
    });

    final url = _urlCtrl.text.trim();
    final label = _labelCtrl.text.trim();
    bool hasError = false;

    // Validar URL o teléfono si el enlace es WhatsApp.
    final urlValidation = _platform == SocialPlatform.whatsapp
        ? _validateWhatsAppLink(url)
        : FieldValidators.validateSocialUrl(url);
    if (!urlValidation.isValid) {
      setState(() => _urlError = urlValidation.errorMessage ?? '');
      hasError = true;
    }

    // Validar etiqueta
    final labelValidation = FieldValidators.validateSocialLabel(label);
    if (!labelValidation.isValid) {
      setState(() => _labelError = labelValidation.errorMessage ?? '');
      hasError = true;
    }

    return !hasError;
  }

  ValidationResult _validateWhatsAppLink(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return ValidationResult.valid();
    if (clean.length > FieldValidators.socialUrlMaxLength) {
      return ValidationResult.invalid(
        'El WhatsApp no puede exceder ${FieldValidators.socialUrlMaxLength} caracteres.',
      );
    }
    if (clean.startsWith(RegExp(r'https?://'))) {
      return FieldValidators.validateUrl(clean);
    }
    return FieldValidators.validateContactPhone(clean);
  }

  static const _platformLabels = {
    SocialPlatform.linkedin: 'LinkedIn',
    SocialPlatform.instagram: 'Instagram',
    SocialPlatform.facebook: 'Facebook',
    SocialPlatform.tiktok: 'TikTok',
    SocialPlatform.twitter: 'X / Twitter',
    SocialPlatform.youtube: 'YouTube',
    SocialPlatform.whatsapp: 'WhatsApp',
    SocialPlatform.calendly: 'Calendly',
    SocialPlatform.github: 'GitHub',
    SocialPlatform.custom: 'Otro enlace',
  };

  static const _platformHints = {
    SocialPlatform.linkedin: 'https://linkedin.com/in/tu-usuario',
    SocialPlatform.instagram: 'https://instagram.com/tu_usuario',
    SocialPlatform.facebook: 'https://facebook.com/tu-pagina',
    SocialPlatform.tiktok: 'https://tiktok.com/@tu_usuario',
    SocialPlatform.twitter: 'https://x.com/tu_usuario',
    SocialPlatform.youtube: 'https://youtube.com/@canal',
    SocialPlatform.whatsapp: '+52 55 1234 5678',
    SocialPlatform.calendly: 'https://calendly.com/tu-nombre',
    SocialPlatform.github: 'https://github.com/tu-usuario',
    SocialPlatform.custom: 'https://tuenlace.com',
  };

  static const _selectablePlatforms = [
    SocialPlatform.linkedin,
    SocialPlatform.instagram,
    SocialPlatform.facebook,
    SocialPlatform.tiktok,
    SocialPlatform.twitter,
    SocialPlatform.youtube,
    SocialPlatform.whatsapp,
    SocialPlatform.calendly,
    SocialPlatform.custom,
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = widget.isDialog
        ? 28.0
        : MediaQuery.of(context).viewInsets.bottom + 28;
    final platformCards = GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: widget.isDialog ? 3 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: widget.isDialog ? 1.08 : 1.65,
      children: _selectablePlatforms.map((p) {
        final active = _platform == p;
        final label = _platformLabels[p]!;
        final platformColor = _socialPlatformColor(p);
        var hoveringCard = false;
        return StatefulBuilder(
          builder: (context, setHover) {
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setHover(() => hoveringCard = true),
              onExit: (_) => setHover(() => hoveringCard = false),
              child: GestureDetector(
                onTap: () => setState(() => _platform = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active
                        ? platformColor.withValues(alpha: 0.08)
                        : hoveringCard
                        ? TapLoopMotion.hoverSurfaceColor(context)
                        : context.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? platformColor
                          : hoveringCard
                          ? context.borderStrongSoft
                          : context.borderStrongSoft,
                      width: active ? 1.6 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _socialPlatformIcon(
                              p,
                              size: widget.isDialog ? 24 : 18,
                              color: platformColor,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              style: GoogleFonts.dmSans(
                                fontSize: widget.isDialog ? 13 : 12,
                                fontWeight: FontWeight.w800,
                                color: active
                                    ? context.textPrimary
                                    : context.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (active)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: platformColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditInputField(
          label: 'Etiqueta visible',
          controller: _labelCtrl,
          hint: 'Ej: WhatsApp',
          error: _labelError,
          maxLength: FieldValidators.socialLabelMaxLength,
        ),
        const SizedBox(height: 16),
        _EditInputField(
          label: _platformLabels[_platform]!,
          controller: _urlCtrl,
          hint: _platformHints[_platform],
          keyboardType: TextInputType.url,
          error: _urlError,
          maxLength: FieldValidators.socialUrlMaxLength,
        ),
        if (_platform == SocialPlatform.custom) ...[
          const SizedBox(height: 16),
          _EditorDialogLabel('Icono'),
          const SizedBox(height: 10),
          _CustomSocialIconPicker(
            selectedKey: _customIconKey,
            onChanged: (key) => setState(() => _customIconKey = key),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderStrongSoft),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visible en el perfil público',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Las personas podrán abrir este enlace desde tu tarjeta.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _EditorVisibilitySwitch(
                value: _isVisible,
                onChanged: (value) => setState(() => _isVisible = value),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      constraints: widget.isDialog
          ? const BoxConstraints(maxHeight: 760)
          : const BoxConstraints(),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(30)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(30, 26, 30, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isDialog)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.borderStrongSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Editar enlace' : 'Agregar enlace',
                        style: GoogleFonts.outfit(
                          fontSize: widget.isDialog ? 30 : 22,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Conecta tus canales para que otros puedan contactarte fácilmente.',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isDialog)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 28),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (widget.isDialog)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _EditorDialogLabel('Tipo de enlace'),
                        const SizedBox(height: 12),
                        platformCards,
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 360,
                    margin: const EdgeInsets.symmetric(horizontal: 26),
                    color: context.borderStrongSoft,
                  ),
                  Expanded(child: fields),
                ],
              )
            else ...[
              _EditorDialogLabel('Tipo de enlace'),
              const SizedBox(height: 12),
              platformCards,
              const SizedBox(height: 20),
              fields,
            ],
            const SizedBox(height: 28),
            Divider(color: context.borderStrongSoft, height: 1),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 220,
                  child: TapLoopButton(
                    label: _isEditing ? 'Guardar cambios' : 'Agregar enlace',
                    height: 54,
                    borderRadius: 999,
                    icon: Icon(
                      _isEditing ? Icons.save_outlined : Icons.add_rounded,
                      size: 18,
                    ),
                    onPressed: () {
                      if (!_validateFields()) {
                        TapLoopToast.show(
                          context,
                          'Por favor, verifica los campos marcados.',
                          TapLoopToastType.error,
                        );
                        return;
                      }

                      if (_urlCtrl.text.trim().isEmpty) {
                        TapLoopToast.show(
                          context,
                          'La URL es requerida.',
                          TapLoopToastType.error,
                        );
                        return;
                      }

                      final initial = widget.initialLink;
                      widget.onSubmit(
                        SocialLinkModel(
                          id:
                              initial?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          platform: _platform,
                          url: _urlCtrl.text.trim(),
                          customLabel: _labelCtrl.text.trim().isEmpty
                              ? null
                              : _labelCtrl.text.trim(),
                          iconKey: _platform == SocialPlatform.custom
                              ? _customIconKey
                              : null,
                          isVisible: _isVisible,
                          sortOrder: initial?.sortOrder ?? 0,
                        ),
                      );
                      if (!widget.isDialog) Navigator.pop(context);
                      if (widget.isDialog && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomLinkIconOption {
  final String key;
  final String label;
  final IconData icon;

  const _CustomLinkIconOption(this.key, this.label, this.icon);
}

const _customLinkIconOptions = [
  _CustomLinkIconOption('link', 'Enlace', Icons.link_rounded),
  _CustomLinkIconOption('language', 'Web', Icons.language_rounded),
  _CustomLinkIconOption('store', 'Tienda', Icons.storefront_outlined),
  _CustomLinkIconOption('work', 'Trabajo', Icons.work_outline_rounded),
  _CustomLinkIconOption('event', 'Evento', Icons.event_available_outlined),
  _CustomLinkIconOption('location', 'Ubicación', Icons.location_on_outlined),
  _CustomLinkIconOption('phone', 'Teléfono', Icons.phone_outlined),
  _CustomLinkIconOption('mail', 'Correo', Icons.mail_outline_rounded),
  _CustomLinkIconOption('chat', 'Chat', Icons.chat_bubble_outline_rounded),
  _CustomLinkIconOption('document', 'Documento', Icons.description_outlined),
  _CustomLinkIconOption('image', 'Imagen', Icons.image_outlined),
  _CustomLinkIconOption('video', 'Video', Icons.play_circle_outline_rounded),
  _CustomLinkIconOption('music', 'Música', Icons.music_note_rounded),
  _CustomLinkIconOption('payment', 'Pago', Icons.payments_outlined),
  _CustomLinkIconOption('shopping', 'Compra', Icons.shopping_bag_outlined),
  _CustomLinkIconOption('restaurant', 'Restaurante', Icons.restaurant_outlined),
];

class _CustomSocialIconPicker extends StatelessWidget {
  final String selectedKey;
  final ValueChanged<String> onChanged;

  const _CustomSocialIconPicker({
    required this.selectedKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in _customLinkIconOptions)
          Tooltip(
            message: option.label,
            child: Material(
              color: selectedKey == option.key
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : context.bgCard,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => onChanged(option.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedKey == option.key
                          ? AppColors.primary
                          : context.borderStrongSoft,
                      width: selectedKey == option.key ? 1.5 : 1,
                    ),
                  ),
                  child: Icon(
                    option.icon,
                    size: 22,
                    color: selectedKey == option.key
                        ? AppColors.primary
                        : context.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Formularios Tab ─────────────────────────────────────────────────────────

IconData _smartFormIncludedFieldIcon(SmartFormIncludedField field) {
  return switch (field) {
    SmartFormIncludedField.name => Icons.person_outline_rounded,
    SmartFormIncludedField.email => Icons.email_outlined,
    SmartFormIncludedField.phone => Icons.phone_outlined,
    SmartFormIncludedField.company => Icons.business_outlined,
    SmartFormIncludedField.message => Icons.chat_bubble_outline_rounded,
    SmartFormIncludedField.budget => Icons.payments_outlined,
    SmartFormIncludedField.date => Icons.calendar_month_outlined,
  };
}

class _FormulariosTab extends StatefulWidget {
  final String cardId;
  final ValueChanged<bool> onCompletionChanged;
  final ValueChanged<List<SmartFormModel>> onFormsChanged;
  const _FormulariosTab({
    required this.cardId,
    required this.onCompletionChanged,
    required this.onFormsChanged,
  });

  @override
  State<_FormulariosTab> createState() => _FormulariosTabState();
}

class _FormulariosTabState extends State<_FormulariosTab> {
  List<SmartFormModel> _forms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForms();
  }

  Future<void> _loadForms() async {
    try {
      final forms = await CardRepository.fetchSmartForms(widget.cardId);
      final hasCompletedForm = forms.any(
        (form) => form.isActive && form.fields.isNotEmpty,
      );
      if (mounted) {
        setState(() {
          _forms = forms;
          _loading = false;
        });
      }
      widget.onCompletionChanged(hasCompletedForm);
      widget.onFormsChanged(forms);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      widget.onCompletionChanged(false);
      widget.onFormsChanged([]);
    }
  }

  Future<void> _createForm() async {
    if (_forms.length >= 5) {
      TapLoopToast.show(
        context,
        'Máximo 5 formularios permitidos en total.',
        TapLoopToastType.error,
      );
      return;
    }
    final nameCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final successCtrl = TextEditingController(
      text: 'Gracias, recibimos tu información.',
    );
    var activeForm = true;
    final selectedFields = <SmartFormIncludedField>{
      SmartFormIncludedField.name,
      SmartFormIncludedField.email,
      SmartFormIncludedField.phone,
      SmartFormIncludedField.message,
    };
    final created = await showDialog<SmartFormModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final includedFields = smartFormIncludedFieldOrder
              .where(selectedFields.contains)
              .toList();
          final canCreate =
              nameCtrl.text.trim().isNotEmpty && includedFields.isNotEmpty;
          void applyPreset({
            required String name,
            required String description,
            required String successMessage,
            required List<SmartFormIncludedField> fields,
          }) {
            setDialog(() {
              nameCtrl.text = name;
              descriptionCtrl.text = description;
              successCtrl.text = successMessage;
              selectedFields
                ..clear()
                ..addAll(fields);
            });
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 28,
            ),
            backgroundColor: ctx.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Crear formulario',
                                  style: GoogleFonts.outfit(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: ctx.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Crea un formulario para captar contactos, cotizaciones o solicitudes.',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 14,
                                    color: ctx.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _EditorDialogLabel('Nombre del formulario'),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: nameCtrl,
                                  maxLength: 100,
                                  maxLines: 1,
                                  onChanged: (_) => setDialog(() {}),
                                  decoration: _corporateInputDecoration(
                                    ctx,
                                    'Ej. Contacto, cotización o demo',
                                  ).copyWith(counterText: ''),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${nameCtrl.text.length}/100',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: nameCtrl.text.length > 80
                                          ? Colors.red
                                          : ctx.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _EditorDialogLabel('Descripción'),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: descriptionCtrl,
                                  maxLines: 3,
                                  decoration: _corporateInputDecoration(
                                    ctx,
                                    'Describe el propósito de este formulario',
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _EditorDialogLabel('Mensaje de éxito'),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: successCtrl,
                                  decoration: _corporateInputDecoration(
                                    ctx,
                                    'Gracias, recibimos tu información.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: ctx.bgCard,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: ctx.borderStrongSoft),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _EditorDialogLabel('Usos sugeridos'),
                                  const SizedBox(height: 12),
                                  _SuggestedUsePill(
                                    icon: Icons.person_outline_rounded,
                                    label: 'Contacto',
                                    onTap: () => applyPreset(
                                      name: 'Contacto',
                                      description:
                                          'Formulario para recibir datos de contacto.',
                                      successMessage:
                                          'Gracias, recibimos tu información.',
                                      fields: const [
                                        SmartFormIncludedField.name,
                                        SmartFormIncludedField.email,
                                        SmartFormIncludedField.phone,
                                        SmartFormIncludedField.message,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _SuggestedUsePill(
                                    icon: Icons.receipt_long_outlined,
                                    label: 'Cotización',
                                    onTap: () => applyPreset(
                                      name: 'Cotización',
                                      description:
                                          'Formulario para solicitar una cotización.',
                                      successMessage:
                                          'Gracias, recibimos tu solicitud de cotización.',
                                      fields: const [
                                        SmartFormIncludedField.name,
                                        SmartFormIncludedField.email,
                                        SmartFormIncludedField.phone,
                                        SmartFormIncludedField.company,
                                        SmartFormIncludedField.message,
                                        SmartFormIncludedField.budget,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _SuggestedUsePill(
                                    icon: Icons.calendar_month_outlined,
                                    label: 'Agendar demo',
                                    onTap: () => applyPreset(
                                      name: 'Agendar demo',
                                      description:
                                          'Formulario para coordinar una demostración.',
                                      successMessage:
                                          'Gracias, recibimos tu solicitud de demo.',
                                      fields: const [
                                        SmartFormIncludedField.name,
                                        SmartFormIncludedField.email,
                                        SmartFormIncludedField.phone,
                                        SmartFormIncludedField.company,
                                        SmartFormIncludedField.message,
                                        SmartFormIncludedField.date,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: ctx.bgCard,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: ctx.borderStrongSoft),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _EditorDialogLabel('Campos incluidos'),
                            const SizedBox(height: 4),
                            Text(
                              'Selecciona la información que solicitará el formulario.',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: ctx.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: smartFormIncludedFieldOrder.map((
                                field,
                              ) {
                                final selected = selectedFields.contains(field);
                                return _FieldChip(
                                  icon: _smartFormIncludedFieldIcon(field),
                                  label: field.label,
                                  selected: selected,
                                  onTap: () => setDialog(() {
                                    if (selected) {
                                      selectedFields.remove(field);
                                    } else {
                                      selectedFields.add(field);
                                    }
                                  }),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: ctx.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: ctx.borderStrongSoft),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Formulario activo',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: ctx.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Permite recibir respuestas desde tu perfil público.',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: ctx.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _EditorVisibilitySwitch(
                              value: activeForm,
                              onChanged: (value) =>
                                  setDialog(() => activeForm = value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      Divider(color: ctx.borderStrongSoft, height: 1),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 190,
                            child: TapLoopButton(
                              label: 'Crear',
                              height: 54,
                              borderRadius: 999,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              onPressed: canCreate
                                  ? () => Navigator.pop(
                                      ctx,
                                      SmartFormModel(
                                        id: '',
                                        cardId: widget.cardId,
                                        name: nameCtrl.text.trim(),
                                        description: descriptionCtrl.text
                                            .trim(),
                                        successMessage:
                                            successCtrl.text.trim().isEmpty
                                            ? 'Gracias, recibimos tu información.'
                                            : successCtrl.text.trim(),
                                        isActive: activeForm,
                                        includedFields: includedFields,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    nameCtrl.dispose();
    descriptionCtrl.dispose();
    successCtrl.dispose();
    if (created == null) return;
    try {
      await CardRepository.createSmartForm(widget.cardId, created);
      await _loadForms();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Formulario creado correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo crear el formulario. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: TapLoopProgressIndicator());
    }

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Formularios de captura',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Crea y gestiona formularios para capturar prospectos desde tu perfil.',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _EditorInlineMetric(
                    icon: Icons.dynamic_form_outlined,
                    value: '${_forms.length}',
                    label: 'Formularios',
                  ),
                ),
                const SizedBox(width: 34),
                Expanded(
                  child: _EditorInlineMetric(
                    icon: Icons.check_circle_outline_rounded,
                    value: '${_forms.where((form) => form.isActive).length}',
                    label: 'Activos',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TapLoopButton(
              label: 'Crear formulario',
              height: 54,
              borderRadius: 999,
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: _createForm,
            ),
            const SizedBox(height: 28),
            Divider(color: context.borderStrongSoft, height: 1),
            const SizedBox(height: 24),
            if (_forms.isEmpty)
              _EmptyState(
                message: 'No hay formularios creados',
                hint: 'Crea uno seleccionando los campos incluidos.',
              )
            else
              ..._forms.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DbSmartFormCard(form: f, onChanged: _loadForms),
                ),
              ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 210,
                child: TapLoopButton(
                  label: 'Guardar cambios',
                  height: 54,
                  borderRadius: 999,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  onPressed: _loadForms,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 48),
      child: content,
    );
  }
}

class _DbSmartFormCard extends StatefulWidget {
  final SmartFormModel form;
  final VoidCallback onChanged;

  const _DbSmartFormCard({required this.form, required this.onChanged});

  @override
  State<_DbSmartFormCard> createState() => _DbSmartFormCardState();
}

class _DbSmartFormCardState extends State<_DbSmartFormCard> {
  bool _open = false;

  Future<void> _toggleActive(bool v) async {
    await CardRepository.updateSmartForm(widget.form.copyWith(isActive: v));
    widget.onChanged();
  }

  Future<void> _editForm() async {
    final ctrl = TextEditingController(text: widget.form.name);
    final descriptionCtrl = TextEditingController(
      text: widget.form.description ?? '',
    );
    final successCtrl = TextEditingController(text: widget.form.successMessage);
    var activeForm = widget.form.isActive;
    final selectedFields = widget.form.includedFields.toSet();
    final updated = await showDialog<SmartFormModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final includedFields = smartFormIncludedFieldOrder
              .where(selectedFields.contains)
              .toList();
          final canSave =
              ctrl.text.trim().isNotEmpty && includedFields.isNotEmpty;
          return AlertDialog(
            backgroundColor: ctx.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            constraints: const BoxConstraints(maxWidth: 720),
            title: const Text('Editar formulario'),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EditorDialogLabel('Nombre del formulario'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      maxLength: 100,
                      maxLines: 1,
                      onChanged: (value) => setDialog(() {}),
                      decoration: _corporateInputDecoration(
                        ctx,
                        'Nombre',
                      ).copyWith(counterText: ''),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${ctrl.text.length}/100',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: ctrl.text.length > 80
                              ? Colors.red
                              : ctx.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _EditorDialogLabel('Descripción'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionCtrl,
                      maxLines: 3,
                      decoration: _corporateInputDecoration(
                        ctx,
                        'Describe el propósito de este formulario',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _EditorDialogLabel('Mensaje de éxito'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: successCtrl,
                      decoration: _corporateInputDecoration(
                        ctx,
                        'Gracias, recibimos tu información.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _EditorDialogLabel('Campos incluidos'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: smartFormIncludedFieldOrder.map((field) {
                        final selected = selectedFields.contains(field);
                        return _FieldChip(
                          icon: _smartFormIncludedFieldIcon(field),
                          label: field.label,
                          selected: selected,
                          onTap: () => setDialog(() {
                            if (selected) {
                              selectedFields.remove(field);
                            } else {
                              selectedFields.add(field);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Formulario activo',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Text(
                        'Permite recibir respuestas desde tu perfil público.',
                      ),
                      value: activeForm,
                      onChanged: (value) => setDialog(() => activeForm = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: canSave
                    ? () => Navigator.pop(
                        ctx,
                        widget.form.copyWith(
                          name: ctrl.text.trim(),
                          description: descriptionCtrl.text.trim(),
                          successMessage: successCtrl.text.trim().isEmpty
                              ? 'Gracias, recibimos tu información.'
                              : successCtrl.text.trim(),
                          isActive: activeForm,
                          includedFields: includedFields,
                        ),
                      )
                    : null,
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    descriptionCtrl.dispose();
    successCtrl.dispose();
    if (updated == null) return;
    try {
      await CardRepository.updateSmartForm(updated);
      widget.onChanged();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Formulario actualizado correctamente.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo actualizar el formulario. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  Future<void> _deleteForm() async {
    try {
      await CardRepository.deleteSmartForm(widget.form.id);
      widget.onChanged();
      if (mounted) {
        TapLoopToast.show(
          context,
          'Formulario eliminado.',
          TapLoopToastType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        TapLoopToast.show(
          context,
          'No se pudo eliminar el formulario. Intenta de nuevo.',
          TapLoopToastType.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldCount = widget.form.fields.length;
    final fieldLabel = fieldCount == 1 ? '1 campo' : '$fieldCount campos';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderStrongSoft),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.form.name,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Deja tu contacto · $fieldLabel',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _EditorVisibilitySwitch(
                    value: widget.form.isActive,
                    onChanged: _toggleActive,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Editar formulario',
                    onPressed: _editForm,
                    icon: Icon(
                      Icons.edit_outlined,
                      color: context.textSecondary,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Eliminar formulario',
                    onPressed: _deleteForm,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: 22,
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.arrow_forward_rounded,
                    color: context.textPrimary,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 18),
            Divider(color: context.borderStrongSoft, height: 1),
            const SizedBox(height: 14),
            if (widget.form.fields.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Este formulario no tiene campos.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: widget.form.includedFields.map((field) {
                  return _FieldChip(
                    icon: _smartFormIncludedFieldIcon(field),
                    label: field.label,
                    selected: true,
                  );
                }).toList(),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Integraciones Tab ────────────────────────────────────────────────────────

class _CalendarioTab extends StatefulWidget {
  final bool calendarEnabled;
  final String? calendarUrl;
  final void Function(bool enabled, String url) onChanged;

  const _CalendarioTab({
    required this.calendarEnabled,
    required this.calendarUrl,
    required this.onChanged,
  });

  @override
  State<_CalendarioTab> createState() => _CalendarioTabState();
}

class _CalendarioTabState extends State<_CalendarioTab> {
  late bool _enabled;
  late List<CalendarIntegrationLink> _integrations;

  int get _configuredIntegrationCount =>
      _integrations.where((link) => link.url.trim().isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _enabled = widget.calendarEnabled;
    _integrations = parseCalendarIntegrationLinks(widget.calendarUrl);
  }

  void _emitChanges() {
    final payload = encodeCalendarIntegrationLinks(_integrations);
    widget.onChanged(_enabled, payload);
  }

  Future<void> _showIntegrationDialog({int? initialIndex}) async {
    final initial = initialIndex == null ? null : _integrations[initialIndex];
    CalendarProviderType provider =
        initial?.provider ?? CalendarProviderType.calendly;
    final providerCtrl = TextEditingController(text: provider.label);
    final urlCtrl = TextEditingController(text: initial?.url ?? '');
    final labelCtrl = TextEditingController(
      text: provider == CalendarProviderType.custom
          ? initial?.displayLabel ?? 'Otra integración'
          : 'Agenda una reunión',
    );
    bool visible = _enabled;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          void selectProvider(CalendarProviderType selected) {
            setDialog(() {
              provider = selected;
              providerCtrl.text = selected.label;
              labelCtrl.text = selected == CalendarProviderType.custom
                  ? initial?.displayLabel ?? 'Otra integración'
                  : 'Agenda una reunión';
            });
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 28,
            ),
            backgroundColor: ctx.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 820,
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  initialIndex == null
                                      ? 'Agregar integración'
                                      : 'Editar integración',
                                  style: GoogleFonts.outfit(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: ctx.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Conecta herramientas para mostrar agenda, capturar leads o enlazar servicios externos.',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 15,
                                    color: ctx.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, size: 28),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final option in CalendarProviderType.values)
                            _IntegrationTypeCard(
                              icon: _calendarProviderIcon(option),
                              title: option.label,
                              subtitle: _calendarProviderSubtitle(option),
                              selected: provider == option,
                              onTap: () => selectProvider(option),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _EditorDialogLabel('Proveedor'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: providerCtrl,
                        readOnly: true,
                        decoration: _corporateInputDecoration(ctx, 'Proveedor'),
                      ),
                      const SizedBox(height: 16),
                      _EditorDialogLabel('URL pública'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: urlCtrl,
                        keyboardType: TextInputType.url,
                        decoration: _corporateInputDecoration(
                          ctx,
                          provider.hint,
                        ),
                      ),
                      if (provider == CalendarProviderType.custom) ...[
                        const SizedBox(height: 16),
                        _EditorDialogLabel('Etiqueta visible'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: labelCtrl,
                          decoration: _corporateInputDecoration(
                            ctx,
                            'Ej. Demo personalizada, WhatsApp, CRM',
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: ctx.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: ctx.borderStrongSoft),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.visibility_outlined,
                              color: AppColors.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mostrar en el perfil',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: ctx.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Activa esta integración en tu tarjeta pública.',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: ctx.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _EditorVisibilitySwitch(
                              value: visible,
                              onChanged: (value) =>
                                  setDialog(() => visible = value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      Divider(color: ctx.borderStrongSoft, height: 1),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 210,
                            child: TapLoopButton(
                              label: 'Guardar',
                              height: 54,
                              borderRadius: 999,
                              icon: const Icon(Icons.save_outlined, size: 18),
                              onPressed: () {
                                final url = urlCtrl.text.trim();
                                if (url.isEmpty) {
                                  TapLoopToast.show(
                                    context,
                                    'La URL de la integración es requerida.',
                                    TapLoopToastType.error,
                                  );
                                  return;
                                }
                                final label = labelCtrl.text.trim();
                                final nextLink = CalendarIntegrationLink(
                                  provider: provider,
                                  url: url,
                                  customLabel:
                                      provider == CalendarProviderType.custom
                                      ? (label.isEmpty
                                            ? 'Otra integración'
                                            : label)
                                      : null,
                                );
                                setState(() {
                                  _enabled = visible;
                                  if (initialIndex == null) {
                                    _integrations = [
                                      ..._integrations,
                                      nextLink,
                                    ];
                                  } else {
                                    _integrations = [
                                      for (
                                        var i = 0;
                                        i < _integrations.length;
                                        i++
                                      )
                                        i == initialIndex
                                            ? nextLink
                                            : _integrations[i],
                                    ];
                                  }
                                });
                                _emitChanges();
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    providerCtrl.dispose();
    urlCtrl.dispose();
    labelCtrl.dispose();
  }

  void _deleteIntegration(int index) {
    setState(() {
      _integrations = [
        for (var i = 0; i < _integrations.length; i++)
          if (i != index) _integrations[i],
      ];
      if (_integrations.isEmpty) {
        _enabled = false;
      }
    });
    _emitChanges();
    TapLoopToast.show(
      context,
      'Integración eliminada.',
      TapLoopToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Integraciones',
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Conecta herramientas externas a tu perfil.',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _EditorInlineMetric(
                    icon: Icons.hub_outlined,
                    value: '$_configuredIntegrationCount',
                    label: 'Integraciones',
                  ),
                ),
                const SizedBox(width: 34),
                Expanded(
                  child: _EditorInlineMetric(
                    icon: Icons.check_circle_outline_rounded,
                    value: _enabled ? '$_configuredIntegrationCount' : '0',
                    label: 'Activas',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TapLoopButton(
              label: 'Agregar integración',
              height: 54,
              borderRadius: 999,
              icon: const Icon(Icons.add_link_rounded, size: 18),
              onPressed: _showIntegrationDialog,
            ),
            const SizedBox(height: 28),
            Divider(color: context.borderStrongSoft, height: 1),
            const SizedBox(height: 24),
            if (_integrations.every((link) => link.url.trim().isEmpty))
              _EmptyState(
                message: 'No hay integraciones configuradas',
                hint:
                    'Agrega una agenda o herramienta externa para mostrarla en tu perfil.',
              )
            else
              ..._integrations
                  .asMap()
                  .entries
                  .where((entry) => entry.value.url.trim().isNotEmpty)
                  .map((entry) {
                    final index = entry.key;
                    final integration = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _IntegrationRow(
                        integration: integration,
                        onEdit: () =>
                            _showIntegrationDialog(initialIndex: index),
                        onDelete: () => _deleteIntegration(index),
                      ),
                    );
                  }),
            const SizedBox(height: 34),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 210,
                child: TapLoopButton(
                  label: 'Guardar cambios',
                  height: 54,
                  borderRadius: 999,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  onPressed: _emitChanges,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 48),
      child: content,
    );
  }
}

class _IntegrationTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _IntegrationTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.primary : context.borderStrongSoft;

    var hovering = false;
    return StatefulBuilder(
      builder: (context, setHovering) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovering(() => hovering = true),
          onExit: (_) => setHovering(() => hovering = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 212,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected || hovering
                    ? TapLoopMotion.hoverSurfaceColor(context)
                    : context.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : hovering
                      ? context.borderStrongSoft.withValues(alpha: 0.9)
                      : borderColor,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 25, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 37),
                          child: Text(
                            subtitle,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IntegrationRow extends StatelessWidget {
  final CalendarIntegrationLink integration;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IntegrationRow({
    required this.integration,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderStrongSoft),
          ),
          child: Row(
            children: [
              Icon(
                _calendarProviderIcon(integration.provider),
                color: AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      integration.displayLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${integration.provider.label} · ${integration.url}',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar integración',
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 21,
                  color: context.textSecondary,
                ),
              ),
              IconButton(
                tooltip: 'Eliminar integración',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 21,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _calendarProviderIcon(CalendarProviderType provider) {
  return switch (provider) {
    CalendarProviderType.calendly => Icons.calendar_month_outlined,
    CalendarProviderType.googleCalendar => Icons.event_available_outlined,
    CalendarProviderType.microsoftTeams => Icons.video_call_outlined,
    CalendarProviderType.custom => Icons.add_link_rounded,
  };
}

String _calendarProviderSubtitle(CalendarProviderType provider) {
  return switch (provider) {
    CalendarProviderType.calendly => 'Agenda reuniones',
    CalendarProviderType.googleCalendar => 'Reservas con Google',
    CalendarProviderType.microsoftTeams => 'Reuniones por Teams',
    CalendarProviderType.custom => 'Etiqueta y enlace libres',
  };
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String hint;
  const _EmptyState({required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Text(
              message,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: GoogleFonts.dmSans(fontSize: 12, color: context.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditInputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String? error;
  final int? maxLength;

  const _EditInputField({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
    this.error,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
            if (maxLength != null)
              Text(
                '${controller.text.length}/$maxLength',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: controller.text.length > maxLength!
                      ? Colors.red
                      : context.textMuted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled,
          maxLines: maxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.dmSans(
              fontSize: 13,
              color: context.textMuted,
            ),
            filled: true,
            fillColor: context.isDark ? const Color(0xFF171717) : Colors.white,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 12 : 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? Colors.red : context.borderStrongSoft,
                width: hasError ? 1.5 : 1,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderStrongSoft),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError
                    ? Colors.red
                    : AppColors.primary.withValues(alpha: 0.85),
                width: 1.4,
              ),
            ),
            counterText: '',
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.red,
            ),
          ),
        ],
      ],
    );
  }
}

InputDecoration _corporateInputDecoration(
  BuildContext context,
  String hint, {
  String? error,
}) {
  final hasError = error != null && error.isNotEmpty;
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.dmSans(fontSize: 13, color: context.textMuted),
    filled: true,
    fillColor: context.isDark ? const Color(0xFF171717) : Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: hasError ? Colors.red : context.borderStrongSoft,
        width: hasError ? 1.2 : 1,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: hasError ? Colors.red : AppColors.primary,
        width: 1.4,
      ),
    ),
  );
}
