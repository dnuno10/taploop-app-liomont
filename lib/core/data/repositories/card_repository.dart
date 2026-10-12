import '../../services/supabase_service.dart';
import '../../utils/request_deduper.dart';
import '../../../features/card/models/digital_card_model.dart';
import '../../../features/card/models/contact_item_model.dart';
import '../../../features/card/models/social_link_model.dart';
import '../../../features/card/models/smart_form_model.dart';

class CardRepository {
  CardRepository._();

  static final _db = SupabaseService.client;
  static final Map<String, String?> _organizationLogoUrlCache = {};
  static final Map<String, String?> _userOrganizationIdCache = {};

  // ─── Fetch card with contacts & social links ─────────────────────────────

  static Future<List<DigitalCardModel>> fetchCardsForUser(String userId) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .order('created_at');

    final cards = await Future.wait(
      (rows as List).cast<Map<String, dynamic>>().map(
        (row) => fetchCard(row['id'] as String),
      ),
    );

    return cards.whereType<DigitalCardModel>().toList();
  }

  static Future<DigitalCardModel?> fetchCard(String cardId) async {
    final cardFuture = _db
        .from('digital_cards')
        .select()
        .eq('id', cardId)
        .single();

    final contactsFuture = _db
        .from('contact_items')
        .select()
        .eq('card_id', cardId)
        .order('sort_order');

    final socialsFuture = _db
        .from('social_links')
        .select()
        .eq('card_id', cardId)
        .order('sort_order');

    final results = await Future.wait<dynamic>([
      cardFuture,
      contactsFuture,
      socialsFuture,
    ]);
    final cardData = results[0] as Map<String, dynamic>;
    final contacts = results[1] as List;
    final socials = results[2] as List;

    return buildCardModel(
      cardData,
      contactItems: contacts
          .map((e) => ContactItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      socialLinks: socials
          .map((e) => SocialLinkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ─── Fetch public card by slug (no auth required) ────────────────────────

  static Future<DigitalCardModel?> fetchBySlug(
    String slug, {
    bool includeOrganizationLogo = true,
  }) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('public_slug', slug)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return _fetchWithItems(
      rows.first,
      includeOrganizationLogo: includeOrganizationLogo,
    );
  }

  // ─── Fetch public card by user_id (permanent NFC URL) ────────────────────
  // This never breaks even if the user changes their slug.

  static Future<DigitalCardModel?> fetchByUserId(
    String userId, {
    bool includeOrganizationLogo = true,
  }) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .limit(1);

    if ((rows as List).isEmpty) return null;
    return _fetchWithItems(
      rows.first,
      includeOrganizationLogo: includeOrganizationLogo,
    );
  }

  // ─── Check NFC serial status ─────────────────────────────────────────────
  // Returns: 'assigned' | 'unassigned' | 'not_found'

  static Future<String> checkNfcSerial(String serial) async {
    final rows = await _db
        .from('nfc_cards')
        .select('is_assigned')
        .eq('serial', serial)
        .limit(1);
    if ((rows as List).isEmpty) return 'not_found';
    final assigned = rows.first['is_assigned'] as bool? ?? false;
    return assigned ? 'assigned' : 'unassigned';
  }

  // ─── Fetch public card by NFC serial (pre-manufactured cards) ────────────

  static Future<DigitalCardModel?> fetchByNfcSerial(
    String serial, {
    bool includeOrganizationLogo = true,
  }) async {
    final result = await _db.rpc(
      'get_digital_card_id_by_nfc_serial',
      params: {'p_serial': serial},
    );
    final cardId = (result as String?)?.trim();
    if (cardId == null || cardId.isEmpty) return null;
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('id', cardId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return _fetchWithItems(
      rows.first,
      includeOrganizationLogo: includeOrganizationLogo,
    );
  }

  /// Combines what [checkNfcSerial] + [fetchByNfcSerial] do into a single
  /// `nfc_cards` lookup (it already stores `digital_card_id`), skipping the
  /// separate status check and the `get_digital_card_id_by_nfc_serial` RPC
  /// round trip on the public-card hot path.
  static Future<({String status, DigitalCardModel? card})> resolveNfcSerial(
    String serial, {
    bool includeOrganizationLogo = true,
  }) async {
    final rows = await _db
        .from('nfc_cards')
        .select('is_assigned, digital_card_id')
        .eq('serial', serial)
        .limit(1);
    if ((rows as List).isEmpty) {
      return (status: 'not_found', card: null);
    }
    final row = rows.first;
    final isAssigned = row['is_assigned'] as bool? ?? false;
    final cardId = (row['digital_card_id'] as String?)?.trim();
    if (!isAssigned || cardId == null || cardId.isEmpty) {
      return (status: 'unassigned', card: null);
    }

    final cardRows = await _db
        .from('digital_cards')
        .select()
        .eq('id', cardId)
        .limit(1);
    if ((cardRows as List).isEmpty) {
      return (status: 'unassigned', card: null);
    }
    final card = await _fetchWithItems(
      cardRows.first,
      includeOrganizationLogo: includeOrganizationLogo,
    );
    return (status: 'assigned', card: card);
  }

  // ─── Activate NFC card (link serial → current user) ──────────────────────

  static Future<bool> activateNfcCard(
    String serial,
    String digitalCardId,
  ) async {
    final currentUser = _db.auth.currentUser;
    if (currentUser == null) return false;

    final cardRows = await _db
        .from('digital_cards')
        .select('id, user_id')
        .eq('id', digitalCardId)
        .limit(1);
    if ((cardRows as List).isEmpty) return false;
    final ownerId = cardRows.first['user_id'] as String?;
    if (ownerId == null || ownerId != currentUser.id) return false;

    final res = await _db
        .from('nfc_cards')
        .update({
          'user_id': currentUser.id,
          'digital_card_id': digitalCardId,
          'is_assigned': true,
          'assigned_at': DateTime.now().toIso8601String(),
        })
        .eq('serial', serial)
        .eq('is_assigned', false)
        .select();

    final activated = (res as List).isNotEmpty;
    return activated;
  }

  static Future<DigitalCardModel> ensureDigitalCardForUser(
    String userId,
  ) async {
    final card = await _ensureDigitalCardForUser(userId);
    if (card == null) {
      throw Exception(
        'No se pudo preparar una tarjeta digital para el usuario.',
      );
    }
    return card;
  }

  static Future<DigitalCardModel?> _ensureDigitalCardForUser(
    String userId,
  ) async {
    final existing = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .order('created_at')
        .limit(1);

    if (existing.isNotEmpty) {
      return _fetchWithItems(existing.first);
    }

    final userRows = await _db
        .from('users')
        .select('name, org_id')
        .eq('id', userId)
        .limit(1);

    final userJson = userRows.isNotEmpty
        ? userRows.first
        : const <String, dynamic>{};
    final resolvedName = (userJson['name'] as String?)?.trim();
    final orgId = userJson['org_id'] as String?;
    String companyName = '';
    if (orgId != null && orgId.isNotEmpty) {
      final orgRows = await _db
          .from('organizations')
          .select('name')
          .eq('id', orgId)
          .limit(1);
      if ((orgRows as List).isNotEmpty) {
        companyName = (orgRows.first['name'] as String?)?.trim() ?? '';
      }
    }
    final slug = _generateSlug(
      resolvedName == null || resolvedName.isEmpty ? 'usuario' : resolvedName,
      userId,
    );

    final created = await _insertDigitalCard({
      'user_id': userId,
      'org_id': orgId,
      'name': resolvedName ?? '',
      'job_title': '',
      'company': companyName,
      'bio': '',
      'public_slug': slug,
      'is_active': true,
      'theme_style': 'black',
      'layout_style': 'centered',
      'profile_design': 'classic',
      'primary_color': 0xFFEF6820,
      'icon_color': 0xFFEF6820,
      'bg_style': 'plain',
      'show_verified_badge': false,
    });

    return _fetchWithItems(created);
  }

  static Future<DigitalCardModel> createCardForUser({
    required String userId,
    String? orgId,
    String? fallbackName,
    String? fallbackJobTitle,
    String? fallbackCompany,
  }) async {
    final userRows = await _db
        .from('users')
        .select('name, job_title, org_id')
        .eq('id', userId)
        .limit(1);

    final userJson = userRows.isNotEmpty
        ? userRows.first
        : const <String, dynamic>{};
    final resolvedOrgId =
        (orgId ?? userJson['org_id'] as String?)?.trim().isNotEmpty == true
        ? (orgId ?? userJson['org_id'] as String?)!.trim()
        : null;
    final resolvedName =
        (fallbackName ?? userJson['name'] as String?)?.trim().isNotEmpty == true
        ? (fallbackName ?? userJson['name'] as String?)!.trim()
        : 'Nueva tarjeta';
    final resolvedJobTitle =
        (fallbackJobTitle ?? userJson['job_title'] as String?)?.trim() ?? '';

    var companyName = fallbackCompany?.trim() ?? '';
    if (companyName.isEmpty &&
        resolvedOrgId != null &&
        resolvedOrgId.isNotEmpty) {
      final orgRows = await _db
          .from('organizations')
          .select('name')
          .eq('id', resolvedOrgId)
          .limit(1);
      if ((orgRows as List).isNotEmpty) {
        companyName = (orgRows.first['name'] as String?)?.trim() ?? '';
      }
    }

    final slug = _generateSlug(
      resolvedName,
      '$userId-${DateTime.now().microsecondsSinceEpoch}',
    );

    final created = await _insertDigitalCard({
      'user_id': userId,
      'org_id': resolvedOrgId,
      'name': resolvedName,
      'job_title': resolvedJobTitle,
      'company': companyName,
      'bio': '',
      'public_slug': slug,
      'is_active': true,
      'theme_style': 'black',
      'layout_style': 'centered',
      'profile_design': 'classic',
      'primary_color': 0xFFEF6820,
      'icon_color': 0xFFEF6820,
      'bg_style': 'plain',
      'show_verified_badge': false,
    });

    return _fetchWithItems(created);
  }

  static Future<void> syncCardOrganizationCompany({
    required String cardId,
    required String company,
    String? orgId,
  }) async {
    await _db
        .from('digital_cards')
        .update({
          'company': company,
          if (orgId != null && orgId.isNotEmpty) 'org_id': orgId,
        })
        .eq('id', cardId);
  }

  static String _generateSlug(String name, String uid) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final normalized = base.isEmpty ? 'usuario' : base;
    final suffix = uid.substring(0, 6);
    return '$normalized-$suffix';
  }

  // ─── Public slug (the part of the share link after the domain) ───────────

  static final RegExp slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// `public_slug` has no DB-level unique constraint, so callers MUST check
  /// this before writing a user-chosen slug to avoid two cards silently
  /// sharing the same public link.
  static Future<bool> isSlugAvailable(
    String slug, {
    required String excludingCardId,
  }) async {
    final rows = await _db
        .from('digital_cards')
        .select('id')
        .eq('public_slug', slug)
        .limit(2);
    final matches = (rows as List).cast<Map<String, dynamic>>();
    return matches.every((row) => row['id'] == excludingCardId);
  }

  static Future<void> updateSlug({
    required String cardId,
    required String slug,
  }) async {
    await _db
        .from('digital_cards')
        .update({'public_slug': slug})
        .eq('id', cardId);
  }

  // ─── Shared template resolution (org-wide design/forms/integrations/links) ─
  //
  // An org can designate one member's card as a "template". While a given
  // toggle is on, every OTHER member's public card reads that aspect from
  // the template instead of their own row — nothing is ever copied into or
  // deleted from a member's own data, so turning a toggle off instantly
  // restores whatever that member had before, because it was never touched.
  //
  // This resolution only happens in [_fetchWithItems] (the public/display
  // fetch path: fetchBySlug/fetchByUserId/fetchByNfcSerial/resolveNfcSerial)
  // and in [fetchSmartFormsForDisplay]. It deliberately does NOT happen in
  // [buildCardModel]/[fetchCard]/[fetchCardsForUser], which is what feeds
  // `appState.currentCard` for the member's own editor — editors must always
  // see+edit the member's real stored data, never the template's.

  static const _sharedDesignColumns = [
    'theme_style',
    'layout_style',
    'profile_design',
    'primary_color',
    'icon_color',
    'background_color_start',
    'background_color_end',
    'bg_style',
    'bg_color',
    'bg_color_end',
    'show_verified_badge',
  ];

  static Future<Map<String, dynamic>?> _fetchSharedOrgSettings(
    String? orgId,
  ) async {
    final id = orgId?.trim();
    if (id == null || id.isEmpty) return null;
    return RequestDeduper.run('sharedOrgSettings:$id', () async {
      final rows = await _db
          .from('organizations')
          .select(
            'shared_design_enabled, shared_forms_enabled, '
            'shared_integrations_enabled, shared_links_enabled, '
            'shared_template_card_id',
          )
          .eq('id', id)
          .limit(1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      return list.isEmpty ? null : list.first;
    });
  }

  /// Public, read-only view of an org's shared-template settings, for
  /// editors (EditCardView, the admin's member dialog) to decide whether a
  /// tab should show as locked/"managed by your organization" instead of
  /// editable — it does not overlay/resolve anything on its own.
  static Future<
    ({
      bool designShared,
      bool formsShared,
      bool integrationsShared,
      bool linksShared,
      String? templateCardId,
    })?
  >
  fetchSharedTemplateSettings(String? orgId) async {
    final raw = await _fetchSharedOrgSettings(orgId);
    if (raw == null) return null;
    return (
      designShared: raw['shared_design_enabled'] as bool? ?? false,
      formsShared: raw['shared_forms_enabled'] as bool? ?? false,
      integrationsShared: raw['shared_integrations_enabled'] as bool? ?? false,
      linksShared: raw['shared_links_enabled'] as bool? ?? false,
      templateCardId: (raw['shared_template_card_id'] as String?)?.trim(),
    );
  }

  static Future<Map<String, dynamic>?> _fetchTemplateCardRow(
    String templateCardId,
  ) {
    return RequestDeduper.run('templateCardRow:$templateCardId', () async {
      final rows = await _db
          .from('digital_cards')
          .select()
          .eq('id', templateCardId)
          .limit(1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      return list.isEmpty ? null : list.first;
    });
  }

  /// Resolved version of [fetchSmartForms] for public/display use: if the
  /// card's org has shared forms enabled and this card isn't the template
  /// itself, returns the template's forms instead.
  static Future<List<SmartFormModel>> fetchSmartFormsForDisplay({
    required String cardId,
    String? orgId,
  }) async {
    final shared = await _fetchSharedOrgSettings(orgId);
    final templateCardId = (shared?['shared_template_card_id'] as String?)
        ?.trim();
    final formsShared = shared?['shared_forms_enabled'] as bool? ?? false;
    final effectiveCardId =
        formsShared &&
            templateCardId != null &&
            templateCardId.isNotEmpty &&
            templateCardId != cardId
        ? templateCardId
        : cardId;
    return fetchSmartForms(effectiveCardId);
  }

  // ─── Shared helper ────────────────────────────────────────────────────────

  static Future<DigitalCardModel> _fetchWithItems(
    Map<String, dynamic> cardJson, {
    bool includeOrganizationLogo = true,
  }) async {
    final cardId = cardJson['id'] as String;
    final orgId = (cardJson['org_id'] as String?)?.trim();

    var effectiveCardJson = cardJson;
    var linksCardId = cardId;

    final shared = await _fetchSharedOrgSettings(orgId);
    final templateCardId = (shared?['shared_template_card_id'] as String?)
        ?.trim();
    if (shared != null &&
        templateCardId != null &&
        templateCardId.isNotEmpty &&
        templateCardId != cardId) {
      final designShared = shared['shared_design_enabled'] as bool? ?? false;
      final integrationsShared =
          shared['shared_integrations_enabled'] as bool? ?? false;
      final linksShared = shared['shared_links_enabled'] as bool? ?? false;

      if (designShared || integrationsShared) {
        final templateRow = await _fetchTemplateCardRow(templateCardId);
        if (templateRow != null) {
          effectiveCardJson = Map<String, dynamic>.from(cardJson);
          if (designShared) {
            for (final key in _sharedDesignColumns) {
              effectiveCardJson[key] = templateRow[key];
            }
          }
          if (integrationsShared) {
            effectiveCardJson['calendar_enabled'] =
                templateRow['calendar_enabled'];
            effectiveCardJson['calendar_url'] = templateRow['calendar_url'];
          }
        }
      }
      if (linksShared) {
        linksCardId = templateCardId;
      }
    }

    final contactsFuture = _db
        .from('contact_items')
        .select()
        .eq('card_id', cardId)
        .eq('is_visible', true)
        .order('sort_order');

    final socialsFuture = _db
        .from('social_links')
        .select()
        .eq('card_id', linksCardId)
        .eq('is_visible', true)
        .order('sort_order');

    final results = await Future.wait<dynamic>([contactsFuture, socialsFuture]);
    final contacts = results[0] as List;
    final socials = results[1] as List;

    return buildCardModel(
      effectiveCardJson,
      includeOrganizationLogo: includeOrganizationLogo,
      contactItems: contacts
          .map((e) => ContactItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      socialLinks: socials
          .map((e) => SocialLinkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<DigitalCardModel> buildCardModel(
    Map<String, dynamic> cardJson, {
    bool includeOrganizationLogo = true,
    List<ContactItemModel> contactItems = const [],
    List<SocialLinkModel> socialLinks = const [],
    List<SmartFormModel> smartForms = const [],
  }) async {
    final hydratedJson = Map<String, dynamic>.from(cardJson);
    final storedLogo = resolveCompanyLogoUrl(
      (hydratedJson['company_logo'] ?? hydratedJson['company_logo_url'])
          as String?,
    );
    hydratedJson.remove('company_logo_url');
    final directOrgId = (hydratedJson['org_id'] as String?)?.trim();
    final resolvedOrgId = includeOrganizationLogo
        ? await resolveCardOrganizationId(hydratedJson)
        : directOrgId;
    if (resolvedOrgId != null && resolvedOrgId.isNotEmpty) {
      hydratedJson['org_id'] = resolvedOrgId;
    }
    if (storedLogo != null && storedLogo.isNotEmpty) {
      hydratedJson['company_logo'] = storedLogo;
    } else if (includeOrganizationLogo) {
      final orgLogoUrl = await fetchOrganizationLogoUrl(resolvedOrgId);
      if (orgLogoUrl != null && orgLogoUrl.isNotEmpty) {
        hydratedJson['company_logo'] = orgLogoUrl;
      } else {
        hydratedJson.remove('company_logo');
      }
    }

    return DigitalCardModel.fromJson(
      hydratedJson,
      contactItems: contactItems,
      socialLinks: socialLinks,
      smartForms: smartForms,
    );
  }

  static Future<String?> fetchOrganizationLogoUrl(String? orgId) async {
    if (orgId == null || orgId.isEmpty) return null;
    if (_organizationLogoUrlCache.containsKey(orgId)) {
      return _organizationLogoUrlCache[orgId];
    }
    try {
      final rows = await _db
          .from('organizations')
          .select('company_logo')
          .eq('id', orgId)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        final resolved = resolveCompanyLogoUrl(
          rows.first['company_logo'] as String?,
        );
        if (resolved != null && resolved.isNotEmpty) {
          _organizationLogoUrlCache[orgId] = resolved;
          return resolved;
        }
      }
    } catch (_) {}
    final fallback = await fetchOrganizationLogoUrlFromStorage(orgId);
    _organizationLogoUrlCache[orgId] = fallback;
    return fallback;
  }

  static Future<String?> fetchOrganizationLogoUrlFromStorage(
    String orgId,
  ) async {
    try {
      final files = await _db.storage.from('company-logos').list(path: orgId);
      final candidates = files.where((file) {
        return RegExp(
          r'^logo_.*\.(png|jpg|jpeg|webp|svg)$',
          caseSensitive: false,
        ).hasMatch(file.name);
      }).toList();
      if (candidates.isEmpty) return null;

      candidates.sort((a, b) {
        final aDate = DateTime.tryParse(a.updatedAt ?? a.createdAt ?? '');
        final bDate = DateTime.tryParse(b.updatedAt ?? b.createdAt ?? '');
        if (aDate != null && bDate != null) {
          return bDate.compareTo(aDate);
        }
        return b.name.compareTo(a.name);
      });

      return buildCompanyLogoPublicUrl('$orgId/${candidates.first.name}');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> resolveCardOrganizationId(
    Map<String, dynamic> cardJson,
  ) async {
    final directOrgId = (cardJson['org_id'] as String?)?.trim();
    if (directOrgId != null && directOrgId.isNotEmpty) {
      return directOrgId;
    }
    final userId = (cardJson['user_id'] as String?)?.trim();
    if (userId == null || userId.isEmpty) return null;
    if (_userOrganizationIdCache.containsKey(userId)) {
      return _userOrganizationIdCache[userId];
    }

    final rows = await _db
        .from('users')
        .select('org_id')
        .eq('id', userId)
        .limit(1);
    if ((rows as List).isEmpty) {
      _userOrganizationIdCache[userId] = null;
      return null;
    }
    final resolvedOrgId = (rows.first['org_id'] as String?)?.trim();
    _userOrganizationIdCache[userId] = resolvedOrgId;
    return resolvedOrgId;
  }

  static String? resolveCompanyLogoUrl(String? storedValue) {
    final value = storedValue
        ?.trim()
        .replaceAll(RegExp(r"""^['"]+|['"]+$"""), '')
        .replaceFirst(RegExp(r'^/+'), '');
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value.replaceFirst(
        '/storage/v1/object/public/logos/',
        '/storage/v1/object/public/company-logos/',
      );
    }
    final normalizedPath = value
        .replaceFirst(RegExp(r'^company-logos/'), '')
        .replaceFirst(RegExp(r'^logos/'), '');
    return buildCompanyLogoPublicUrl(normalizedPath);
  }

  static String? extractCompanyLogoStoragePath(String? storedValue) {
    final value = storedValue
        ?.trim()
        .replaceAll(RegExp(r"""^['"]+|['"]+$"""), '')
        .replaceFirst(RegExp(r'^/+'), '');
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      final marker = '/storage/v1/object/public/company-logos/';
      final path = uri.path;
      final markerIndex = path.indexOf(marker);
      if (markerIndex == -1) return null;
      return path.substring(markerIndex + marker.length);
    }
    return value
        .replaceFirst(RegExp(r'^company-logos/'), '')
        .replaceFirst(RegExp(r'^logos/'), '');
  }

  static String buildCompanyLogoPublicUrl(String storagePath) {
    final normalizedPath = storagePath
        .trim()
        .replaceAll(RegExp(r"""^['"]+|['"]+$"""), '')
        .replaceFirst(RegExp(r'^/+'), '');
    final encodedPath = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return '${SupabaseService.url}/storage/v1/object/public/company-logos/$encodedPath';
  }

  static Future<Map<String, dynamic>> _insertDigitalCard(
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _db.from('digital_cards').insert(payload).select().single();
    } catch (error) {
      if (!_isMissingColumn(error, 'icon_color')) rethrow;
      final fallback = Map<String, dynamic>.from(payload)..remove('icon_color');
      return await _db.from('digital_cards').insert(fallback).select().single();
    }
  }

  // ─── Save card fields ─────────────────────────────────────────────────────

  static Future<void> saveCard(DigitalCardModel card) async {
    final payload = card.toJson();
    try {
      await _db.from('digital_cards').update(payload).eq('id', card.id);
    } catch (error) {
      if (!_isMissingColumn(error, 'icon_color')) rethrow;
      final fallback = Map<String, dynamic>.from(payload)..remove('icon_color');
      await _db.from('digital_cards').update(fallback).eq('id', card.id);
    }
  }

  static Future<void> updateVerifiedBadge({
    required String cardId,
    required bool showVerifiedBadge,
  }) async {
    await _db
        .from('digital_cards')
        .update({'show_verified_badge': showVerifiedBadge})
        .eq('id', cardId);
  }

  static Future<void> updateProfilePhoto({
    required String cardId,
    required String profilePhotoUrl,
  }) async {
    await _db
        .from('digital_cards')
        .update({'profile_photo_url': profilePhotoUrl})
        .eq('id', cardId);
  }

  static Future<void> deleteCard(String cardId) async {
    await _db.from('digital_cards').delete().eq('id', cardId);
  }

  static Future<void> setCardActiveState({
    required String cardId,
    required bool isActive,
    String? reason,
  }) async {
    final currentUser = _db.auth.currentUser;
    await _db
        .from('digital_cards')
        .update({
          'is_active': isActive,
          'deactivated_at': isActive ? null : DateTime.now().toIso8601String(),
          'deactivation_reason': isActive ? null : reason,
          'deactivated_by': isActive ? null : currentUser?.id,
        })
        .eq('id', cardId);
  }

  // ─── Contact items ────────────────────────────────────────────────────────

  static Future<ContactItemModel> addContactItem(
    String cardId,
    ContactItemModel item,
  ) async {
    final last = await _db
        .from('contact_items')
        .select('sort_order')
        .eq('card_id', cardId)
        .order('sort_order', ascending: false)
        .limit(1);
    final nextOrder = (last as List).isEmpty
        ? 0
        : ((last.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    final data = await _db
        .from('contact_items')
        .insert(item.copyWith(sortOrder: nextOrder).toJson(cardId: cardId))
        .select()
        .single();
    return ContactItemModel.fromJson(data);
  }

  static Future<void> updateContactItem(ContactItemModel item) async {
    final updated = await _db
        .from('contact_items')
        .update(item.toJson())
        .eq('id', item.id)
        .select('id');
    if ((updated as List).isEmpty) {
      throw Exception('No se encontró el contacto para actualizar.');
    }
  }

  static Future<void> deleteContactItem(String itemId) async {
    try {
      await _db.rpc(
        'delete_contact_item',
        params: {'p_contact_item_id': itemId},
      );
      return;
    } catch (error) {
      if (!_isMissingDeleteContactItemRpc(error)) rethrow;
    }

    await _db
        .from('visit_events')
        .update({'contact_item_id': null})
        .eq('contact_item_id', itemId);
    final deleted = await _db
        .from('contact_items')
        .delete()
        .eq('id', itemId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw Exception('No se encontró el contacto para eliminar.');
    }
  }

  static Future<void> reorderContactItems(
    String cardId,
    List<ContactItemModel> items,
  ) async {
    if (items.isEmpty) return;
    final payload = [
      for (var i = 0; i < items.length; i++)
        {'id': items[i].id, ...items[i].toJson(cardId: cardId), 'sort_order': i},
    ];
    await _db.from('contact_items').upsert(payload);
  }

  // ─── Social links ─────────────────────────────────────────────────────────

  static Future<SocialLinkModel> addSocialLink(
    String cardId,
    SocialLinkModel link,
  ) async {
    final last = await _db
        .from('social_links')
        .select('sort_order')
        .eq('card_id', cardId)
        .order('sort_order', ascending: false)
        .limit(1);
    final nextOrder = (last as List).isEmpty
        ? 0
        : ((last.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

    final payload = link.copyWith(sortOrder: nextOrder).toJson(cardId: cardId);
    final data = await _insertSocialLink(payload);
    return SocialLinkModel.fromJson(data);
  }

  static Future<void> updateSocialLink(SocialLinkModel link) async {
    final updated = await _updateSocialLink(link.id, link.toJson());
    if (updated.isEmpty) {
      throw Exception('No se encontró el enlace para actualizar.');
    }
  }

  static Future<void> deleteSocialLink(String linkId) async {
    try {
      await _db.rpc('delete_social_link', params: {'p_social_link_id': linkId});
      return;
    } catch (error) {
      if (!_isMissingDeleteSocialLinkRpc(error)) rethrow;
    }

    await _db
        .from('visit_events')
        .update({'social_link_id': null})
        .eq('social_link_id', linkId);
    final deleted = await _db
        .from('social_links')
        .delete()
        .eq('id', linkId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw Exception('No se encontró el enlace para eliminar.');
    }
  }

  static Future<void> reorderSocialLinks(
    String cardId,
    List<SocialLinkModel> links,
  ) async {
    if (links.isEmpty) return;
    final payload = [
      for (var i = 0; i < links.length; i++)
        {'id': links[i].id, ...links[i].toJson(cardId: cardId), 'sort_order': i},
    ];
    await _db.from('social_links').upsert(payload);
  }

  static bool _isMissingDeleteContactItemRpc(Object error) {
    final message = error.toString();
    return message.contains('delete_contact_item') ||
        message.contains('PGRST202') ||
        message.contains('Could not find the function');
  }

  static bool _isMissingDeleteSocialLinkRpc(Object error) {
    final message = error.toString();
    return message.contains('delete_social_link') ||
        message.contains('PGRST202') ||
        message.contains('Could not find the function');
  }

  static Future<Map<String, dynamic>> _insertSocialLink(
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _db.from('social_links').insert(payload).select().single();
    } catch (error) {
      if (!_isMissingColumn(error, 'icon_key')) rethrow;
      final fallback = Map<String, dynamic>.from(payload)..remove('icon_key');
      return await _db.from('social_links').insert(fallback).select().single();
    }
  }

  static Future<List<dynamic>> _updateSocialLink(
    String linkId,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _db
          .from('social_links')
          .update(payload)
          .eq('id', linkId)
          .select('id');
    } catch (error) {
      if (!_isMissingColumn(error, 'icon_key')) rethrow;
      final fallback = Map<String, dynamic>.from(payload)..remove('icon_key');
      return await _db
          .from('social_links')
          .update(fallback)
          .eq('id', linkId)
          .select('id');
    }
  }

  static bool _isMissingColumn(Object error, String column) {
    final message = error.toString();
    return message.contains(column) &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('PGRST204'));
  }

  // ─── Smart forms ──────────────────────────────────────────────────────────

  static Future<List<SmartFormModel>> fetchSmartForms(String cardId) async {
    final formsRows = await _db
        .from('smart_forms')
        .select()
        .eq('card_id', cardId)
        .order('created_at');

    return (formsRows as List)
        .map((row) => SmartFormModel.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<SmartFormModel> createSmartForm(
    String cardId,
    SmartFormModel form,
  ) async {
    final data = await _db
        .from('smart_forms')
        .insert(form.toJson(cardId: cardId))
        .select()
        .single();
    return SmartFormModel.fromJson(data);
  }

  static Future<void> updateSmartForm(SmartFormModel form) async {
    await _db.from('smart_forms').update(form.toJson()).eq('id', form.id);
  }

  static Future<void> deleteSmartForm(String formId) async {
    try {
      await _db.rpc('delete_smart_form', params: {'p_form_id': formId});
      return;
    } catch (error) {
      if (!_isMissingDeleteSmartFormRpc(error)) rethrow;
    }

    await _db.from('form_submissions').delete().eq('form_id', formId);
    await _db
        .from('visit_events')
        .update({'smart_form_id': null})
        .eq('smart_form_id', formId);
    try {
      await _db.from('smart_form_fields').delete().eq('form_id', formId);
    } catch (error) {
      if (!_isMissingLegacySmartFormFieldsTable(error)) rethrow;
    }
    await _db.from('smart_forms').delete().eq('id', formId);
  }

  static bool _isMissingDeleteSmartFormRpc(Object error) {
    final message = error.toString();
    return message.contains('delete_smart_form') ||
        message.contains('PGRST202') ||
        message.contains('Could not find the function');
  }

  static bool _isMissingLegacySmartFormFieldsTable(Object error) {
    final message = error.toString();
    return message.contains('smart_form_fields') &&
        (message.contains('42P01') ||
            message.contains('does not exist') ||
            message.contains('Could not find the table'));
  }
}
