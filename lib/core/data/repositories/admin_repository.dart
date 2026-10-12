import '../../services/supabase_service.dart';
import '../../utils/request_deduper.dart';
import 'card_repository.dart';
import '../../../features/analytics/models/team_member_model.dart';
import '../../../features/auth/models/user_model.dart';
import '../../../features/card/models/digital_card_model.dart';
import '../../../features/card/models/contact_item_model.dart';
import '../../../features/card/models/social_link_model.dart';
import '../../../features/card/models/smart_form_model.dart';

class _ResolvedLinkReference {
  final String label;
  final String platform;

  const _ResolvedLinkReference({required this.label, required this.platform});
}

class AdminRepository {
  AdminRepository._();

  static final _db = SupabaseService.client;
  static const _profileVisitSources = {'nfc', 'qr', 'link'};
  static const _clickSources = {
    'contact',
    'social',
    'downloaded_contact',
    'share',
  };

  // ─── Fetch org members ────────────────────────────────────────────────────

  static Future<List<TeamMemberModel>> fetchTeamMembers(String orgId) {
    // Dashboard, analytics, lead-intelligence and team-performance screens
    // all call this for the same org within milliseconds of each other —
    // coalesce overlapping calls into a single round trip.
    return RequestDeduper.run(
      'fetchTeamMembers:$orgId',
      () => _fetchTeamMembersUncached(orgId),
    );
  }

  static Future<List<TeamMemberModel>> _fetchTeamMembersUncached(
    String orgId,
  ) async {
    final now = DateTime.now();
    final rangeStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final users = await _db
        .from('users')
        .select('id, name, email, job_title, photo_url, role')
        .eq('org_id', orgId)
        .eq('is_active', true);

    final usersList = (users as List).cast<Map<String, dynamic>>();
    if (usersList.isEmpty) return const [];

    final userIds = usersList
        .map((u) => u['id'] as String?)
        .whereType<String>()
        .toList();

    if (userIds.isEmpty) return const [];

    final cards = await _db
        .from('digital_cards')
        .select('id, user_id, profile_photo_url')
        .inFilter('user_id', userIds);

    final cardRows = (cards as List).cast<Map<String, dynamic>>();
    final cardsByUser = <String, List<String>>{};
    final profilePhotosByUser = <String, String>{};
    final allCardIds = <String>[];

    for (final row in cardRows) {
      final cardId = row['id'] as String?;
      final userId = row['user_id'] as String?;
      if (cardId == null || userId == null) continue;
      cardsByUser.putIfAbsent(userId, () => []).add(cardId);
      final profilePhotoUrl = (row['profile_photo_url'] as String?)?.trim();
      if (profilePhotoUrl != null &&
          profilePhotoUrl.isNotEmpty &&
          !profilePhotosByUser.containsKey(userId)) {
        profilePhotosByUser[userId] = profilePhotoUrl;
      }
      allCardIds.add(cardId);
    }

    final profileViewsByCard = <String, int>{};
    final tapsByCard = <String, int>{};
    final qrScansByCard = <String, int>{};
    final leadsByCard = <String, int>{};
    final conversionsByCard = <String, int>{};
    final contactsSavedByCard = <String, int>{};
    final totalClicksByCard = <String, int>{};
    final viewsSeriesByCard = <String, List<int>>{};
    final tapsSeriesByCard = <String, List<int>>{};
    final clicksSeriesByCard = <String, List<int>>{};
    final linkStatsByCard = <String, Map<String, TeamMemberLinkStat>>{};

    if (allCardIds.isNotEmpty) {
      // visit_events and leads are independent of each other — fetch both
      // at once instead of one after the other.
      final fetched = await Future.wait<dynamic>([
        _db
            .from('visit_events')
            .select(
              'card_id, source, timestamp, contact_item_id, social_link_id',
            )
            .inFilter('card_id', allCardIds),
        _db
            .from('leads')
            .select('card_id, is_converted')
            .inFilter('card_id', allCardIds),
      ]);
      final rawVisitRows = (fetched[0] as List).cast<Map<String, dynamic>>();
      final leadRows = (fetched[1] as List).cast<Map<String, dynamic>>();
      final currentLinksByRef = await _fetchCurrentLinksByRef(
        cardIds: allCardIds,
        contactItemIds: rawVisitRows
            .map((row) => row['contact_item_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList(),
        socialLinkIds: rawVisitRows
            .map((row) => row['social_link_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList(),
      );
      for (final row in rawVisitRows) {
        final cardId = row['card_id'] as String?;
        if (cardId == null) continue;
        final source = row['source'] as String? ?? '';
        final timestamp = DateTime.tryParse(row['timestamp'] as String? ?? '');
        if (_profileVisitSources.contains(source)) {
          profileViewsByCard[cardId] = (profileViewsByCard[cardId] ?? 0) + 1;
        }
        if (source == 'nfc') {
          tapsByCard[cardId] = (tapsByCard[cardId] ?? 0) + 1;
        }
        if (source == 'qr') {
          qrScansByCard[cardId] = (qrScansByCard[cardId] ?? 0) + 1;
        }
        if (source == 'downloaded_contact') {
          contactsSavedByCard[cardId] = (contactsSavedByCard[cardId] ?? 0) + 1;
        }
        if (_clickSources.contains(source)) {
          totalClicksByCard[cardId] = (totalClicksByCard[cardId] ?? 0) + 1;
          final resolved = _resolveLinkReference(
            row: row,
            source: source,
            currentLinksByRef: currentLinksByRef,
          );
          final key = _eventLinkKey(
            row: row,
            source: source,
            fallbackLabel: resolved.label,
          );
          final cardLinkStats = linkStatsByCard.putIfAbsent(cardId, () => {});
          final current = cardLinkStats[key];
          cardLinkStats[key] = TeamMemberLinkStat(
            label: resolved.label,
            platform: resolved.platform,
            clicks: (current?.clicks ?? 0) + 1,
          );
        }
        if (timestamp != null && !timestamp.isBefore(rangeStart)) {
          final bucket = timestamp.difference(rangeStart).inDays;
          if (bucket >= 0 && bucket < 7) {
            final viewsSeries = viewsSeriesByCard.putIfAbsent(
              cardId,
              () => List.filled(7, 0),
            );
            final tapsSeries = tapsSeriesByCard.putIfAbsent(
              cardId,
              () => List.filled(7, 0),
            );
            final clicksSeries = clicksSeriesByCard.putIfAbsent(
              cardId,
              () => List.filled(7, 0),
            );
            if (_profileVisitSources.contains(source)) {
              viewsSeries[bucket] += 1;
            }
            if (source == 'nfc') {
              tapsSeries[bucket] += 1;
            }
            if (_clickSources.contains(source)) {
              clicksSeries[bucket] += 1;
            }
          }
        }
      }

      for (final row in leadRows) {
        final cardId = row['card_id'] as String?;
        if (cardId == null) continue;
        final converted = row['is_converted'] as bool? ?? false;
        leadsByCard[cardId] = (leadsByCard[cardId] ?? 0) + 1;
        if (converted) {
          conversionsByCard[cardId] = (conversionsByCard[cardId] ?? 0) + 1;
        }
      }
    }

    return usersList.map((userJson) {
      final userId = userJson['id'] as String;
      final userCardIds = cardsByUser[userId] ?? const <String>[];

      int profileViews = 0;
      int taps = 0;
      int qrScans = 0;
      int leads = 0;
      int conversions = 0;
      int contactsSaved = 0;
      int totalClicks = 0;
      final viewsByDay = List.filled(7, 0);
      final tapsByDay = List.filled(7, 0);
      final clicksByDay = List.filled(7, 0);
      final aggregatedLinks = <String, TeamMemberLinkStat>{};

      for (final cardId in userCardIds) {
        profileViews += profileViewsByCard[cardId] ?? 0;
        taps += tapsByCard[cardId] ?? 0;
        qrScans += qrScansByCard[cardId] ?? 0;
        leads += leadsByCard[cardId] ?? 0;
        conversions += conversionsByCard[cardId] ?? 0;
        contactsSaved += contactsSavedByCard[cardId] ?? 0;
        totalClicks += totalClicksByCard[cardId] ?? 0;
        final cardViews = viewsSeriesByCard[cardId] ?? const <int>[];
        final cardTaps = tapsSeriesByCard[cardId] ?? const <int>[];
        final cardClicks = clicksSeriesByCard[cardId] ?? const <int>[];
        for (var i = 0; i < 7; i++) {
          if (i < cardViews.length) viewsByDay[i] += cardViews[i];
          if (i < cardTaps.length) tapsByDay[i] += cardTaps[i];
          if (i < cardClicks.length) clicksByDay[i] += cardClicks[i];
        }
        for (final stat
            in (linkStatsByCard[cardId]?.values ??
                const <TeamMemberLinkStat>[])) {
          final key = '${stat.platform}:${stat.label}';
          final current = aggregatedLinks[key];
          aggregatedLinks[key] = TeamMemberLinkStat(
            label: stat.label,
            platform: stat.platform,
            clicks: (current?.clicks ?? 0) + stat.clicks,
          );
        }
      }

      return TeamMemberModel(
        id: userId,
        cardIds: userCardIds,
        name: userJson['name'] as String? ?? '',
        email: userJson['email'] as String? ?? '',
        jobTitle: userJson['job_title'] as String? ?? '',
        role: userJson['role'] as String? ?? 'default',
        avatarUrl:
            profilePhotosByUser[userId] ?? userJson['photo_url'] as String?,
        taps: taps,
        qrScans: qrScans,
        leads: leads,
        profileViews: profileViews,
        contactsSaved: contactsSaved,
        conversions: conversions,
        totalClicks: totalClicks,
        viewsByDay: viewsByDay,
        tapsByDay: tapsByDay,
        clicksByDay: clicksByDay,
        linkStats: aggregatedLinks.values.toList()
          ..sort((a, b) => b.clicks.compareTo(a.clicks)),
      );
    }).toList();
  }

  // ─── Fetch full user+card for member editing ──────────────────────────────

  static Future<UserModel> fetchUser(String userId) async {
    final data = await _db.from('users').select().eq('id', userId).single();
    return UserModel.fromJson(data);
  }

  static Future<DigitalCardModel?> fetchCardForUser(String userId) async {
    final rows = await _db
        .from('digital_cards')
        .select()
        .eq('user_id', userId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    final cardJson = rows.first;
    final cardId = cardJson['id'] as String;

    final contacts = await _db
        .from('contact_items')
        .select()
        .eq('card_id', cardId)
        .order('sort_order');
    final socials = await _db
        .from('social_links')
        .select()
        .eq('card_id', cardId)
        .order('sort_order');
    final forms = await _db
        .from('smart_forms')
        .select()
        .eq('card_id', cardId)
        .order('created_at');

    return CardRepository.buildCardModel(
      cardJson,
      contactItems: (contacts as List)
          .map((e) => ContactItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      socialLinks: (socials as List)
          .map((e) => SocialLinkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      smartForms: (forms as List)
          .map((e) => SmartFormModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Batched version of [fetchCardForUser]: resolves the primary card (plus
  /// its contact items, social links and smart forms) for every user in
  /// [userIds] using one query per table instead of 4 queries per user.
  static Future<Map<String, DigitalCardModel>> fetchCardsForUsers(
    List<String> userIds,
  ) async {
    final result = <String, DigitalCardModel>{};
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return result;

    final cardRows = await _db
        .from('digital_cards')
        .select()
        .inFilter('user_id', ids);
    final cardsList = (cardRows as List).cast<Map<String, dynamic>>();
    if (cardsList.isEmpty) return result;

    // Keep at most one card per user, same semantics as fetchCardForUser's
    // `.limit(1)`.
    final cardJsonByUserId = <String, Map<String, dynamic>>{};
    for (final row in cardsList) {
      final userId = row['user_id'] as String?;
      if (userId == null || cardJsonByUserId.containsKey(userId)) continue;
      cardJsonByUserId[userId] = row;
    }

    final cardIds = cardJsonByUserId.values
        .map((row) => row['id'] as String)
        .toList();
    if (cardIds.isEmpty) return result;

    final contactsRows = await _db
        .from('contact_items')
        .select()
        .inFilter('card_id', cardIds)
        .order('sort_order');
    final socialsRows = await _db
        .from('social_links')
        .select()
        .inFilter('card_id', cardIds)
        .order('sort_order');
    final formsRows = await _db
        .from('smart_forms')
        .select()
        .inFilter('card_id', cardIds)
        .order('created_at');

    final contactsByCard = <String, List<ContactItemModel>>{};
    for (final row in (contactsRows as List).cast<Map<String, dynamic>>()) {
      final cardId = row['card_id'] as String?;
      if (cardId == null) continue;
      contactsByCard
          .putIfAbsent(cardId, () => [])
          .add(ContactItemModel.fromJson(row));
    }

    final socialsByCard = <String, List<SocialLinkModel>>{};
    for (final row in (socialsRows as List).cast<Map<String, dynamic>>()) {
      final cardId = row['card_id'] as String?;
      if (cardId == null) continue;
      socialsByCard
          .putIfAbsent(cardId, () => [])
          .add(SocialLinkModel.fromJson(row));
    }

    final formsByCard = <String, List<SmartFormModel>>{};
    for (final row in (formsRows as List).cast<Map<String, dynamic>>()) {
      final cardId = row['card_id'] as String?;
      if (cardId == null) continue;
      formsByCard
          .putIfAbsent(cardId, () => [])
          .add(SmartFormModel.fromJson(row));
    }

    for (final entry in cardJsonByUserId.entries) {
      final cardId = entry.value['id'] as String;
      result[entry.key] = await CardRepository.buildCardModel(
        entry.value,
        contactItems: contactsByCard[cardId] ?? const [],
        socialLinks: socialsByCard[cardId] ?? const [],
        smartForms: formsByCard[cardId] ?? const [],
      );
    }

    return result;
  }

  // ─── Update member ────────────────────────────────────────────────────────

  static Future<void> updateUser(UserModel user) async {
    final payload = user.toJson()..remove('id');
    await _db.from('users').update(payload).eq('id', user.id);
  }

  static Future<void> saveAdminMember({
    required DigitalCardModel card,
    required List<ContactItemModel> contacts,
    required List<SocialLinkModel> socialLinks,
    required List<SmartFormModel> smartForms,
  }) async {
    await updateCard(card);
    await replaceContactItems(cardId: card.id, items: contacts);
    await replaceSocialLinks(cardId: card.id, links: socialLinks);
    await replaceSmartForms(cardId: card.id, forms: smartForms);
  }

  static Future<void> replaceContactItems({
    required String cardId,
    required List<ContactItemModel> items,
  }) async {
    await _db.from('contact_items').delete().eq('card_id', cardId);
    final payload = items
        .asMap()
        .entries
        .where((entry) => entry.value.value.trim().isNotEmpty)
        .map((entry) {
          return entry.value
              .copyWith(sortOrder: entry.key)
              .toJson(cardId: cardId);
        })
        .toList();
    if (payload.isNotEmpty) {
      await _db.from('contact_items').insert(payload);
    }
  }

  static Future<void> replaceSocialLinks({
    required String cardId,
    required List<SocialLinkModel> links,
  }) async {
    await _db.from('social_links').delete().eq('card_id', cardId);
    final payload = links
        .asMap()
        .entries
        .where((entry) => entry.value.url.trim().isNotEmpty)
        .map((entry) {
          return entry.value
              .copyWith(sortOrder: entry.key)
              .toJson(cardId: cardId);
        })
        .toList();
    if (payload.isNotEmpty) {
      try {
        await _db.from('social_links').insert(payload);
      } catch (error) {
        if (!_isMissingColumn(error, 'icon_key')) rethrow;
        final fallback = payload.map((item) {
          return Map<String, dynamic>.from(item)..remove('icon_key');
        }).toList();
        await _db.from('social_links').insert(fallback);
      }
    }
  }

  static Future<void> replaceSmartForms({
    required String cardId,
    required List<SmartFormModel> forms,
  }) async {
    final payload = forms
        .where((form) => form.name.trim().isNotEmpty)
        .map((form) => form.toJson())
        .toList();

    try {
      await _db.rpc(
        'replace_smart_forms',
        params: {'p_card_id': cardId, 'p_forms': payload},
      );
      return;
    } catch (error) {
      if (!_isMissingReplaceSmartFormsRpc(error)) rethrow;
    }

    final existing = await CardRepository.fetchSmartForms(cardId);
    for (final form in existing) {
      await CardRepository.deleteSmartForm(form.id);
    }
    if (payload.isNotEmpty) {
      await _db
          .from('smart_forms')
          .insert(payload.map((form) => {...form, 'card_id': cardId}).toList());
    }
  }

  static bool _isMissingReplaceSmartFormsRpc(Object error) {
    final message = error.toString();
    return message.contains('replace_smart_forms') ||
        message.contains('PGRST202') ||
        message.contains('Could not find the function');
  }

  /// Persists the 4 "shared template" toggles and/or which card acts as the
  /// org's template. Nothing is copied into member cards anymore — every
  /// reader resolves the effective design/forms/links/integrations at read
  /// time (see [CardRepository]'s shared-template resolution), so turning a
  /// toggle on/off is a single-row write regardless of team size, and a
  /// member's own configuration is never overwritten or lost.
  ///
  /// When [templateCardId] is provided, it is verified (defense in depth,
  /// on top of RLS) to belong to a `digital_cards` row owned by a user of
  /// [orgId] before being saved, so a template can never point at another
  /// organization's card.
  static Future<void> updateOrgConsistencySettings({
    required String orgId,
    bool? sharedDesignEnabled,
    bool? sharedFormsEnabled,
    bool? sharedIntegrationsEnabled,
    bool? sharedLinksEnabled,
    String? templateCardId,
  }) async {
    final payload = <String, dynamic>{
      if (sharedDesignEnabled != null)
        'shared_design_enabled': sharedDesignEnabled,
      if (sharedFormsEnabled != null)
        'shared_forms_enabled': sharedFormsEnabled,
      if (sharedIntegrationsEnabled != null)
        'shared_integrations_enabled': sharedIntegrationsEnabled,
      if (sharedLinksEnabled != null) 'shared_links_enabled': sharedLinksEnabled,
    };

    if (templateCardId != null) {
      final trimmed = templateCardId.trim();
      if (trimmed.isEmpty) {
        payload['shared_template_card_id'] = null;
      } else {
        final rows = await _db
            .from('digital_cards')
            .select('id, org_id, user_id, users:user_id(org_id)')
            .eq('id', trimmed)
            .limit(1);
        final cardRows = (rows as List).cast<Map<String, dynamic>>();
        if (cardRows.isEmpty) {
          throw Exception('La tarjeta plantilla no existe.');
        }
        final cardRow = cardRows.first;
        final cardOrgId = (cardRow['org_id'] as String?)?.trim();
        final ownerOrgId =
            ((cardRow['users'] as Map<String, dynamic>?)?['org_id']
                    as String?)
                ?.trim();
        if (cardOrgId != orgId && ownerOrgId != orgId) {
          throw Exception(
            'La tarjeta plantilla debe pertenecer a tu organización.',
          );
        }
        payload['shared_template_card_id'] = trimmed;
      }
    }

    if (payload.isEmpty) return;
    await _db.from('organizations').update(payload).eq('id', orgId);
  }

  static String _eventLinkKey({
    required Map<String, dynamic> row,
    required String source,
    required String fallbackLabel,
  }) {
    final contactItemId = (row['contact_item_id'] as String?)?.trim();
    if (contactItemId != null && contactItemId.isNotEmpty) {
      return 'contact:$contactItemId';
    }
    final socialLinkId = (row['social_link_id'] as String?)?.trim();
    if (socialLinkId != null && socialLinkId.isNotEmpty) {
      return 'social:$socialLinkId';
    }
    return 'legacy:$source:$fallbackLabel';
  }

  static _ResolvedLinkReference _resolveLinkReference({
    required Map<String, dynamic> row,
    required String source,
    required Map<String, _ResolvedLinkReference> currentLinksByRef,
  }) {
    final contactItemId = (row['contact_item_id'] as String?)?.trim();
    if (contactItemId != null && contactItemId.isNotEmpty) {
      final resolved = currentLinksByRef['contact:$contactItemId'];
      if (resolved != null) return resolved;
    }
    final socialLinkId = (row['social_link_id'] as String?)?.trim();
    if (socialLinkId != null && socialLinkId.isNotEmpty) {
      final resolved = currentLinksByRef['social:$socialLinkId'];
      if (resolved != null) return resolved;
    }
    final fallbackLabel = switch (source) {
      'contact' => 'Contacto',
      'social' => 'Red social',
      'downloaded_contact' => 'Guardó contacto',
      'share' => 'Compartió perfil',
      _ => 'Interacción',
    };
    return _ResolvedLinkReference(label: fallbackLabel, platform: source);
  }

  static Future<Map<String, _ResolvedLinkReference>> _fetchCurrentLinksByRef({
    required List<String> cardIds,
    required List<String> contactItemIds,
    required List<String> socialLinkIds,
  }) async {
    final resolved = <String, _ResolvedLinkReference>{};

    if (cardIds.isEmpty) return resolved;

    // contact_items and social_links are independent lookups — fetch both
    // at once instead of one after the other.
    final results = await Future.wait<dynamic>([
      contactItemIds.isEmpty
          ? Future.value(const [])
          : _db
                .from('contact_items')
                .select('id, card_id, type, label')
                .inFilter('card_id', cardIds)
                .inFilter('id', contactItemIds),
      socialLinkIds.isEmpty
          ? Future.value(const [])
          : _db
                .from('social_links')
                .select('id, card_id, platform, custom_label')
                .inFilter('card_id', cardIds)
                .inFilter('id', socialLinkIds),
    ]);

    for (final row in (results[0] as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final item = ContactItemModel.fromJson(row);
      resolved['contact:$id'] = _ResolvedLinkReference(
        label: item.displayLabel,
        platform: item.type.name,
      );
    }

    for (final row in (results[1] as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final link = SocialLinkModel.fromJson(row);
      resolved['social:$id'] = _ResolvedLinkReference(
        label: link.label,
        platform: link.platform.name,
      );
    }

    return resolved;
  }

  static Future<void> updateCard(DigitalCardModel card) async {
    final payload = card.toJson();
    try {
      await _db.from('digital_cards').update(payload).eq('id', card.id);
    } catch (error) {
      if (!_isMissingColumn(error, 'icon_color')) rethrow;
      final fallback = Map<String, dynamic>.from(payload)..remove('icon_color');
      await _db.from('digital_cards').update(fallback).eq('id', card.id);
    }
  }

  static bool _isMissingColumn(Object error, String column) {
    final message = error.toString();
    return message.contains(column) &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('PGRST204'));
  }

  static Future<void> updateCardActivation({
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

  static Future<void> deactivateUser(String userId) async {
    await _db.from('users').update({'is_active': false}).eq('id', userId);
  }

  // ─── Org info ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchOrg(String orgId) async {
    final data = await _db
        .from('organizations')
        .select()
        .eq('id', orgId)
        .single();
    return data as Map<String, dynamic>?;
  }

  static Future<void> updateOrgLogo({
    required String orgId,
    required String companyLogo,
  }) async {
    await _db
        .from('organizations')
        .update({'company_logo': companyLogo})
        .eq('id', orgId);
  }

  static Future<void> updateOrgName({
    required String orgId,
    required String name,
  }) async {
    await _db.from('organizations').update({'name': name}).eq('id', orgId);
  }
}
