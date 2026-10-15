import '../../services/metrics_realtime_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/request_deduper.dart';
import 'card_repository.dart';
import 'linked_admin_gateway.dart';
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

  // Short-lived cache so switching between Administración, Equipo,
  // Analíticas and Leads reuses the same result instead of recomputing it.
  // Entries older than the org's last realtime change are refetched.
  static const _teamMembersCacheTtl = Duration(seconds: 45);
  static final Map<
    String,
    ({DateTime fetchedAt, Future<List<TeamMemberModel>> future})
  >
  _teamMembersCache = {};

  static void invalidateTeamMembers([String? orgId]) {
    if (orgId == null) {
      _teamMembersCache.clear();
    } else {
      _teamMembersCache.remove(orgId);
    }
  }

  static Future<List<TeamMemberModel>> fetchTeamMembers(
    String orgId, {
    bool forceRefresh = false,
  }) {
    final cached = _teamMembersCache[orgId];
    final lastChange = MetricsRealtimeSubscription.lastOrgChangeAt(orgId);
    final now = DateTime.now();
    final cacheIsFresh =
        cached != null &&
        now.difference(cached.fetchedAt) < _teamMembersCacheTtl &&
        (lastChange == null || cached.fetchedAt.isAfter(lastChange));
    if (!forceRefresh && cacheIsFresh) {
      return cached.future.then(List.of);
    }

    // Dashboard, analytics, lead-intelligence and team-performance screens
    // all call this for the same org within milliseconds of each other —
    // coalesce overlapping calls into a single round trip.
    final future = RequestDeduper.run(
      'fetchTeamMembers:$orgId',
      () => _fetchTeamMembersUncached(orgId),
    );
    _teamMembersCache[orgId] = (fetchedAt: now, future: future);
    future.then(
      (members) => MetricsRealtimeSubscription.registerOrgCards(
        orgId,
        members.expand((m) => m.cardIds),
      ),
      onError: (Object _) {
        if (identical(_teamMembersCache[orgId]?.future, future)) {
          _teamMembersCache.remove(orgId);
        }
      },
    );
    // Callers sort/mutate the list they get; hand each one its own copy.
    return future.then(List.of);
  }

  /// Grouped visit_events counts per card/source/link/day (see
  /// add_liomont_team_stats_rpcs.sql). Falls back to downloading the raw
  /// events when the RPC isn't installed.
  static Future<List<Map<String, dynamic>>> _fetchVisitStatRows(
    List<String> cardIds,
    DateTime rangeStart,
  ) async {
    try {
      final result = await _db.rpc(
        'liomont_team_visit_stats',
        params: {
          'p_card_ids': cardIds,
          'p_since': rangeStart.toUtc().toIso8601String(),
        },
      );
      return (result as List).cast<Map<String, dynamic>>();
    } catch (_) {
      final rows = await _db
          .from('visit_events')
          .select('card_id, source, timestamp, contact_item_id, social_link_id')
          .inFilter('card_id', cardIds);
      return (rows as List).cast<Map<String, dynamic>>();
    }
  }

  /// Lead totals per card as `{card_id, lead_count, converted_count}`.
  static Future<List<Map<String, dynamic>>> _fetchLeadStatRows(
    List<String> cardIds,
  ) async {
    try {
      final result = await _db.rpc(
        'liomont_team_lead_stats',
        params: {'p_card_ids': cardIds},
      );
      return (result as List).cast<Map<String, dynamic>>();
    } catch (_) {
      final rows = await _db
          .from('leads')
          .select('card_id, is_converted')
          .inFilter('card_id', cardIds);
      return [
        for (final row in (rows as List).cast<Map<String, dynamic>>())
          {
            'card_id': row['card_id'],
            'lead_count': 1,
            'converted_count': (row['is_converted'] as bool? ?? false) ? 1 : 0,
          },
      ];
    }
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

    final cardRows = await _fetchAllIn(
      table: 'digital_cards',
      column: 'user_id',
      values: userIds,
      orderColumn: 'created_at',
      columns: 'id, user_id, profile_photo_url, created_at',
    );
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
        _fetchVisitStatRows(allCardIds, rangeStart),
        _fetchLeadStatRows(allCardIds),
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
        // Grouped RPC rows carry event_count/day_bucket; raw fallback rows
        // are one event each with a timestamp.
        final n = (row['event_count'] as num?)?.toInt() ?? 1;
        int? bucket = (row['day_bucket'] as num?)?.toInt();
        if (!row.containsKey('event_count')) {
          final timestamp = DateTime.tryParse(
            row['timestamp'] as String? ?? '',
          );
          bucket = timestamp != null && !timestamp.isBefore(rangeStart)
              ? timestamp.difference(rangeStart).inDays
              : null;
        }
        if (_profileVisitSources.contains(source)) {
          profileViewsByCard[cardId] = (profileViewsByCard[cardId] ?? 0) + n;
        }
        if (source == 'nfc') {
          tapsByCard[cardId] = (tapsByCard[cardId] ?? 0) + n;
        }
        if (source == 'qr') {
          qrScansByCard[cardId] = (qrScansByCard[cardId] ?? 0) + n;
        }
        if (source == 'downloaded_contact') {
          contactsSavedByCard[cardId] = (contactsSavedByCard[cardId] ?? 0) + n;
        }
        if (_clickSources.contains(source)) {
          totalClicksByCard[cardId] = (totalClicksByCard[cardId] ?? 0) + n;
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
            clicks: (current?.clicks ?? 0) + n,
          );
        }
        if (bucket != null) {
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
              viewsSeries[bucket] += n;
            }
            if (source == 'nfc') {
              tapsSeries[bucket] += n;
            }
            if (_clickSources.contains(source)) {
              clicksSeries[bucket] += n;
            }
          }
        }
      }

      for (final row in leadRows) {
        final cardId = row['card_id'] as String?;
        if (cardId == null) continue;
        final leadCount = (row['lead_count'] as num?)?.toInt() ?? 0;
        final convertedCount = (row['converted_count'] as num?)?.toInt() ?? 0;
        leadsByCard[cardId] = (leadsByCard[cardId] ?? 0) + leadCount;
        if (convertedCount > 0) {
          conversionsByCard[cardId] =
              (conversionsByCard[cardId] ?? 0) + convertedCount;
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

  // ─── Liomont / Promofarma shared directory ────────────────────────────────

  // Only these two orgs share the administration listing. Their members are
  // read through the `get_liomont_promofarma_directory` RPC (read-only,
  // SECURITY DEFINER) so no RLS policy shared with other apps changes.
  static const _linkedDirectoryOrgIds = {
    '293f05a3-9115-4b72-a4ac-2c4d3a8af83e', // LIOMONT
    '4a7357d3-5222-4555-aaa9-f5cbe7b1d81d', // PROMOFARMA
  };

  static bool usesLinkedDirectory(String orgId) =>
      _linkedDirectoryOrgIds.contains(orgId);

  /// Members of Liomont and Promofarma with their org name, NFC serials and
  /// primary card. Returns an empty list if the RPC is missing or the caller
  /// is not an admin of either org.
  static Future<List<LinkedDirectoryEntry>> fetchLinkedDirectory() async {
    try {
      final result = await _db.rpc('get_liomont_promofarma_directory');
      final rows = (result as List? ?? const []).cast<Map<String, dynamic>>();
      await Future.wait(
        _linkedDirectoryOrgIds.map(CardRepository.fetchOrganizationLogoUrl),
      );
      return await Future.wait(rows.map(LinkedDirectoryEntry._fromJson));
    } catch (_) {
      return const [];
    }
  }

  // ─── Reports: NFC reference + leads directory ─────────────────────────────

  /// Serial NFC ↔ collaborator rows. Liomont/Promofarma admins get both orgs
  /// via `lp_admin_nfc_reference`; otherwise (or if the RPC is missing) it is
  /// built from [orgId]'s own team with the existing RLS.
  static Future<List<NfcReferenceRow>> fetchNfcReference(String orgId) async {
    if (usesLinkedDirectory(orgId)) {
      try {
        final result = await _db.rpc('lp_admin_nfc_reference');
        return (result as List)
            .cast<Map<String, dynamic>>()
            .map(NfcReferenceRow.fromJson)
            .toList();
      } catch (_) {
        // Fall through to the own-org fallback below.
      }
    }

    final results = await Future.wait<Object?>([
      fetchTeamMembers(orgId),
      fetchOrg(orgId),
    ]);
    final members = results[0] as List<TeamMemberModel>;
    final orgName = (results[1] as Map<String, dynamic>?)?['name'] as String?;
    final serialsByCard = await fetchNfcSerialsByCard(
      members.expand((m) => m.cardIds).toList(),
    );
    final rows =
        <NfcReferenceRow>[
          for (final member in members)
            for (final cardId in member.cardIds)
              for (final serial in serialsByCard[cardId] ?? const <String>[])
                NfcReferenceRow(
                  serial: serial,
                  userId: member.id,
                  userName: member.name,
                  userEmail: member.email,
                  company: orgName ?? '',
                  orgId: orgId,
                  orgName: orgName ?? '',
                ),
        ]..sort(
          (a, b) =>
              a.userName.toLowerCase().compareTo(b.userName.toLowerCase()),
        );
    return rows;
  }

  /// Leads for the export. With [userId] only that collaborator's leads;
  /// otherwise every collaborator of Liomont + Promofarma (or of [orgId]'s
  /// own team when the org isn't linked / the RPC is missing).
  static Future<List<Map<String, dynamic>>> fetchLeadsDirectory(
    String orgId, {
    String? userId,
  }) async {
    if (usesLinkedDirectory(orgId)) {
      try {
        final result = await _db.rpc(
          'lp_admin_leads_directory',
          params: {'p_user_id': userId},
        );
        return (result as List).cast<Map<String, dynamic>>();
      } catch (_) {
        // Fall through to the own-org fallback below.
      }
    }

    final results = await Future.wait<Object?>([
      fetchTeamMembers(orgId),
      fetchOrg(orgId),
    ]);
    final members = (results[0] as List<TeamMemberModel>)
        .where((m) => userId == null || m.id == userId)
        .toList();
    final orgName = (results[1] as Map<String, dynamic>?)?['name'] as String?;
    final memberByCard = {
      for (final m in members)
        for (final cardId in m.cardIds) cardId: m,
    };
    if (memberByCard.isEmpty) return const [];
    final leads = await _fetchAllIn(
      table: 'leads',
      column: 'card_id',
      values: memberByCard.keys.toList(),
      orderColumn: 'last_seen',
    );
    return [
      for (final lead in leads)
        {
          ...lead,
          'last_seen': lead['last_seen'] ?? lead['created_at'],
          'collaborator_id': memberByCard[lead['card_id']]?.id,
          'collaborator_name': memberByCard[lead['card_id']]?.name,
          'collaborator_email': memberByCard[lead['card_id']]?.email,
          'org_name': orgName,
        },
    ]..sort(
      (a, b) => ((b['last_seen'] as String?) ?? '').compareTo(
        (a['last_seen'] as String?) ?? '',
      ),
    );
  }

  /// NFC serials per digital card, as allowed by the existing RLS policies.
  static Future<Map<String, List<String>>> fetchNfcSerialsByCard(
    List<String> cardIds,
  ) async {
    if (cardIds.isEmpty) return const {};
    try {
      final rows = await _db
          .from('nfc_cards')
          .select('serial, digital_card_id')
          .inFilter('digital_card_id', cardIds);
      final result = <String, List<String>>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final cardId = row['digital_card_id'] as String?;
        final serial = (row['serial'] as String?)?.trim();
        if (cardId == null || serial == null || serial.isEmpty) continue;
        result.putIfAbsent(cardId, () => []).add(serial);
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Every row of [table] whose [column] is in [values], without hitting
  /// PostgREST's per-request row cap: values are split into chunks (also
  /// keeping URLs short) and each chunk is paged until exhausted. Rows are
  /// ordered by [orderColumn] (then id) within each chunk.
  static Future<List<Map<String, dynamic>>> _fetchAllIn({
    required String table,
    required String column,
    required List<String> values,
    required String orderColumn,
    String columns = '*',
  }) async {
    const chunkSize = 40;
    const pageSize = 500;

    Future<List<Map<String, dynamic>>> fetchChunk(List<String> chunk) async {
      final rows = <Map<String, dynamic>>[];
      for (var from = 0; ; from += pageSize) {
        final page = await _db
            .from(table)
            .select(columns)
            .inFilter(column, chunk)
            .order(orderColumn)
            .order('id')
            .range(from, from + pageSize - 1);
        final pageRows = (page as List).cast<Map<String, dynamic>>();
        rows.addAll(pageRows);
        if (pageRows.length < pageSize) break;
      }
      return rows;
    }

    final chunks = [
      for (var i = 0; i < values.length; i += chunkSize)
        values.sublist(i, (i + chunkSize).clamp(0, values.length)),
    ];
    final results = await Future.wait(chunks.map(fetchChunk));
    return [for (final rows in results) ...rows];
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
  ///
  /// [orgIdByUserId] fills `org_id` on cards that don't store it, so building
  /// each card doesn't need its own `users` lookup to find the org's logo.
  static Future<Map<String, DigitalCardModel>> fetchCardsForUsers(
    List<String> userIds, {
    Map<String, String> orgIdByUserId = const {},
  }) async {
    final result = <String, DigitalCardModel>{};
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return result;

    final cardsList = await _fetchAllIn(
      table: 'digital_cards',
      column: 'user_id',
      values: ids,
      orderColumn: 'created_at',
    );
    if (cardsList.isEmpty) return result;

    // Keep at most one card per user: the oldest, same as the member's own
    // app (CardRepository.fetchCardsForUser orders by created_at).
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

    // The three child tables are independent — fetch them in parallel.
    // Fetched in chunks/pages: a single request for a whole team is capped
    // by PostgREST's max rows and silently dropped members' items.
    final childRows = await Future.wait<dynamic>([
      _fetchAllIn(
        table: 'contact_items',
        column: 'card_id',
        values: cardIds,
        orderColumn: 'sort_order',
      ),
      _fetchAllIn(
        table: 'social_links',
        column: 'card_id',
        values: cardIds,
        orderColumn: 'sort_order',
      ),
      _fetchAllIn(
        table: 'smart_forms',
        column: 'card_id',
        values: cardIds,
        orderColumn: 'created_at',
      ),
    ]);
    final contactsRows = childRows[0];
    final socialsRows = childRows[1];
    final formsRows = childRows[2];

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
      final storedOrgId = (entry.value['org_id'] as String?)?.trim();
      final knownOrgId = orgIdByUserId[entry.key];
      if ((storedOrgId == null || storedOrgId.isEmpty) && knownOrgId != null) {
        entry.value['org_id'] = knownOrgId;
      }
    }

    // Resolve each org's logo once up front; building the cards in parallel
    // afterwards then only hits the cache instead of one request per card.
    await Future.wait(
      cardJsonByUserId.values
          .map((row) => (row['org_id'] as String?)?.trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .map(CardRepository.fetchOrganizationLogoUrl),
    );

    final built = await Future.wait(
      cardJsonByUserId.entries.map((entry) async {
        final cardId = entry.value['id'] as String;
        final card = await CardRepository.buildCardModel(
          entry.value,
          contactItems: contactsByCard[cardId] ?? const [],
          socialLinks: socialsByCard[cardId] ?? const [],
          smartForms: formsByCard[cardId] ?? const [],
        );
        return MapEntry(entry.key, card);
      }),
    );
    result.addEntries(built);

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
      if (sharedLinksEnabled != null)
        'shared_links_enabled': sharedLinksEnabled,
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
            ((cardRow['users'] as Map<String, dynamic>?)?['org_id'] as String?)
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
    final cardIdSet = cardIds.toSet();
    // Chunked lookups by id: hundreds of ids in one URL made this slow or
    // fail. Rows are then limited to [cardIds] like the old card filter.
    final results = await Future.wait<List<Map<String, dynamic>>>([
      contactItemIds.isEmpty
          ? Future.value(const [])
          : _fetchAllIn(
              table: 'contact_items',
              column: 'id',
              values: contactItemIds,
              orderColumn: 'id',
              columns: 'id, card_id, type, label',
            ),
      socialLinkIds.isEmpty
          ? Future.value(const [])
          : _fetchAllIn(
              table: 'social_links',
              column: 'id',
              values: socialLinkIds,
              orderColumn: 'id',
              columns: 'id, card_id, platform, custom_label',
            ),
    ]);
    bool inCards(Map<String, dynamic> row) =>
        cardIdSet.contains(row['card_id'] as String?);

    for (final row in results[0].where(inCards)) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final item = ContactItemModel.fromJson(row);
      resolved['contact:$id'] = _ResolvedLinkReference(
        label: item.displayLabel,
        platform: item.type.name,
      );
    }

    for (final row in results[1].where(inCards)) {
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
    if (LinkedAdminGateway.handlesCard(cardId)) {
      await LinkedAdminGateway.updateCard(cardId, {
        'is_active': isActive,
        'deactivated_at': isActive ? null : DateTime.now().toIso8601String(),
        'deactivation_reason': isActive ? null : reason,
        'deactivated_by': isActive ? null : currentUser?.id,
      });
      return;
    }
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

class LinkedDirectoryEntry {
  final TeamMemberModel member;
  final String orgId;
  final String orgName;
  final List<String> nfcSerials;
  final DigitalCardModel? card;

  const LinkedDirectoryEntry({
    required this.member,
    required this.orgId,
    required this.orgName,
    required this.nfcSerials,
    required this.card,
  });

  static Future<LinkedDirectoryEntry> _fromJson(
    Map<String, dynamic> json,
  ) async {
    final cardJson = json['card'] as Map<String, dynamic>?;
    final memberOrgId = json['org_id'] as String?;
    final cardOrgId = (cardJson?['org_id'] as String?)?.trim();
    if (cardJson != null &&
        (cardOrgId == null || cardOrgId.isEmpty) &&
        memberOrgId != null) {
      cardJson['org_id'] = memberOrgId;
    }
    List<Map<String, dynamic>> rows(String key) =>
        (cardJson?[key] as List? ?? const []).cast<Map<String, dynamic>>();

    final card = cardJson == null
        ? null
        : await CardRepository.buildCardModel(
            Map<String, dynamic>.from(cardJson)
              ..remove('contact_items')
              ..remove('social_links')
              ..remove('smart_forms'),
            contactItems: rows(
              'contact_items',
            ).map(ContactItemModel.fromJson).toList(),
            socialLinks: rows(
              'social_links',
            ).map(SocialLinkModel.fromJson).toList(),
            smartForms: rows(
              'smart_forms',
            ).map(SmartFormModel.fromJson).toList(),
          );

    return LinkedDirectoryEntry(
      member: TeamMemberModel(
        id: json['id'] as String,
        cardIds: card == null ? const [] : [card.id],
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        jobTitle: json['job_title'] as String? ?? '',
        role: json['role'] as String? ?? 'default',
        avatarUrl: card?.profilePhotoUrl ?? json['photo_url'] as String?,
        taps: 0,
        profileViews: 0,
        contactsSaved: 0,
      ),
      orgId: json['org_id'] as String? ?? '',
      orgName: json['org_name'] as String? ?? '',
      nfcSerials: (json['nfc_serials'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      card: card,
    );
  }
}

class NfcReferenceRow {
  final String serial;
  final String? userId;
  final String userName;
  final String userEmail;
  final String company;
  final String? orgId;
  final String orgName;
  final String? publicSlug;
  final DateTime? assignedAt;

  const NfcReferenceRow({
    required this.serial,
    this.userId,
    required this.userName,
    required this.userEmail,
    required this.company,
    this.orgId,
    required this.orgName,
    this.publicSlug,
    this.assignedAt,
  });

  factory NfcReferenceRow.fromJson(Map<String, dynamic> json) {
    return NfcReferenceRow(
      serial: json['serial'] as String? ?? '',
      userId: json['user_id'] as String?,
      userName: json['user_name'] as String? ?? '',
      userEmail: json['user_email'] as String? ?? '',
      company: json['company'] as String? ?? '',
      orgId: json['org_id'] as String?,
      orgName: json['org_name'] as String? ?? '',
      publicSlug: json['public_slug'] as String?,
      assignedAt: DateTime.tryParse(json['assigned_at'] as String? ?? ''),
    );
  }
}
