import 'package:flutter/foundation.dart';

import '../../services/supabase_service.dart';
import '../../utils/request_deduper.dart';
import '../../utils/visitor_info.dart';
import '../../../features/analytics/models/analytics_summary_model.dart';
import '../../../features/analytics/models/visit_event_model.dart';
import '../../../features/analytics/models/link_stat_model.dart';
import '../../../features/card/models/contact_item_model.dart';
import '../../../features/card/models/social_link_model.dart';

class _ResolvedLinkReference {
  final String label;
  final String platform;

  const _ResolvedLinkReference({required this.label, required this.platform});
}

class AnalyticsRepository {
  AnalyticsRepository._();

  static final _db = SupabaseService.client;
  static const _visitorInfoTimeout = Duration(milliseconds: 700);

  static const _profileVisitSources = {'nfc', 'qr', 'link'};
  static const _clickSources = {
    'contact',
    'social',
    'downloaded_contact',
    'share',
  };

  static bool _isProfileVisitSource(String? source) =>
      _profileVisitSources.contains(source);

  static bool _isClickSource(String? source) => _clickSources.contains(source);

  static Future<Map<String, String?>> _safeVisitorInfo() async {
    try {
      return await collectVisitorInfo().timeout(
        _visitorInfoTimeout,
        onTimeout: () => <String, String?>{},
      );
    } catch (_) {
      return <String, String?>{};
    }
  }

  // ─── Analytics summary for a card ────────────────────────────────────────

  static Future<AnalyticsSummaryModel> fetchSummary(
    String cardId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return _fetchSummaryForCardIds([cardId], from: from, to: to);
  }

  static Future<AnalyticsSummaryModel> fetchSummaryForCards(
    List<String> cardIds, {
    DateTime? from,
    DateTime? to,
  }) async {
    return _fetchSummaryForCardIds(cardIds, from: from, to: to);
  }

  static Future<AnalyticsSummaryModel> _fetchSummaryForCardIds(
    List<String> cardIds, {
    DateTime? from,
    DateTime? to,
  }) {
    // The dashboard summary (and its realtime-triggered refresh) can be
    // requested for the same cards+range from more than one place at once —
    // coalesce overlapping calls into a single round trip.
    final sortedIds = [...cardIds]..sort();
    final key =
        'fetchSummary:${sortedIds.join(',')}:${from?.toIso8601String()}:${to?.toIso8601String()}';
    return RequestDeduper.run(key, () => _fetchSummaryForCardIdsUncached(cardIds, from: from, to: to));
  }

  static Future<AnalyticsSummaryModel> _fetchSummaryForCardIdsUncached(
    List<String> cardIds, {
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();
    final rangeEnd = to != null
        ? DateTime(to.year, to.month, to.day, 23, 59, 59, 999, 999)
        : now;
    final rangeStart = from != null
        ? DateTime(from.year, from.month, from.day)
        : now.subtract(const Duration(days: 6));
    final rangeDuration = rangeEnd.difference(rangeStart);
    final prevStart = rangeStart.subtract(rangeDuration);
    final uniqueCardIds = cardIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (uniqueCardIds.isEmpty) {
      return const AnalyticsSummaryModel(
        totalVisits: 0,
        totalTaps: 0,
        totalQrScans: 0,
        totalClicks: 0,
        totalInteractions: 0,
        visitsThisWeek: 0,
        visitsLastWeek: 0,
        tapsThisPeriod: 0,
        tapsLastPeriod: 0,
        clicksThisPeriod: 0,
        clicksLastPeriod: 0,
        interactionsThisPeriod: 0,
        interactionsLastPeriod: 0,
        linkStats: [],
        recentEvents: [],
        visitsByDay: [0, 0, 0, 0, 0, 0, 0],
      );
    }

    // Only events from prevStart onward are ever used below (current period
    // + the previous period used for the week-over-week comparison), so
    // bound the query instead of downloading the card's entire history
    // every time the dashboard loads.
    final prevStartIso = prevStart.toIso8601String();
    final allEvents = uniqueCardIds.length == 1
        ? await _db
              .from('visit_events')
              .select()
              .eq('card_id', uniqueCardIds.first)
              .gte('timestamp', prevStartIso)
              .order('timestamp', ascending: false)
        : await _db
              .from('visit_events')
              .select()
              .inFilter('card_id', uniqueCardIds)
              .gte('timestamp', prevStartIso)
              .order('timestamp', ascending: false);

    final events = (allEvents as List)
        .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // Filter to selected range
    final rangeEvents = events
        .where(
          (e) =>
              !e.timestamp.isBefore(rangeStart) &&
              !e.timestamp.isAfter(rangeEnd),
        )
        .toList();
    final hydratedRangeEvents = await hydrateEvents(rangeEvents);
    final visitEvents = hydratedRangeEvents
        .where((e) => _isProfileVisitSource(e.source))
        .toList();
    final tapEvents = hydratedRangeEvents
        .where((e) => e.source == 'nfc')
        .toList();
    final qrEvents = hydratedRangeEvents
        .where((e) => e.source == 'qr')
        .toList();
    final clickEvents = hydratedRangeEvents
        .where((e) => _isClickSource(e.source))
        .toList();
    final previousRangeEvents = events
        .where(
          (e) =>
              !e.timestamp.isBefore(prevStart) &&
              e.timestamp.isBefore(rangeStart),
        )
        .toList();
    final previousVisitCount = previousRangeEvents
        .where((e) => _isProfileVisitSource(e.source))
        .length;
    final previousTapCount = previousRangeEvents
        .where((e) => e.source == 'nfc')
        .length;
    final previousClickCount = previousRangeEvents
        .where((e) => _isClickSource(e.source))
        .length;

    final totalVisits = visitEvents.length;
    final totalTaps = tapEvents.length;
    final totalQrScans = qrEvents.length;
    final totalClicks = clickEvents.length;
    final totalInteractions = hydratedRangeEvents.length;
    final visitsThisWeek = totalVisits;
    final visitsLastWeek = previousVisitCount;

    // Visits by day (7 days ending at rangeEnd)
    final visitsByDay = List.generate(7, (i) {
      final day = rangeEnd.subtract(Duration(days: 6 - i));
      return visitEvents
          .where(
            (e) =>
                e.timestamp.year == day.year &&
                e.timestamp.month == day.month &&
                e.timestamp.day == day.day,
          )
          .length;
    });
    final groupedClicks = <String, int>{};
    final groupedLabels = <String, String>{};
    final groupedPlatforms = <String, String>{};

    for (final event in clickEvents) {
      final resolved = _resolveLinkReference(event: event);
      final key = _eventLinkKey(event, fallbackLabel: resolved.label);
      groupedClicks[key] = (groupedClicks[key] ?? 0) + 1;
      groupedLabels[key] = resolved.label;
      groupedPlatforms[key] = resolved.platform;
    }

    final linkStats =
        groupedClicks.entries
            .map(
              (entry) => LinkStatModel(
                linkId: entry.key,
                label: groupedLabels[entry.key] ?? 'Enlace',
                platform: groupedPlatforms[entry.key] ?? '',
                clicks: entry.value,
                percentage: totalClicks > 0 ? entry.value / totalClicks : 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.clicks.compareTo(a.clicks));

    // Recent 10 events within range
    final recentEvents = hydratedRangeEvents.take(10).toList();

    return AnalyticsSummaryModel(
      totalVisits: totalVisits,
      totalTaps: totalTaps,
      totalQrScans: totalQrScans,
      totalClicks: totalClicks,
      totalInteractions: totalInteractions,
      visitsThisWeek: visitsThisWeek,
      visitsLastWeek: visitsLastWeek,
      tapsThisPeriod: totalTaps,
      tapsLastPeriod: previousTapCount,
      clicksThisPeriod: totalClicks,
      clicksLastPeriod: previousClickCount,
      interactionsThisPeriod: totalInteractions,
      interactionsLastPeriod: previousRangeEvents.length,
      linkStats: linkStats,
      recentEvents: recentEvents,
      visitsByDay: visitsByDay,
    );
  }

  static Future<List<VisitEventModel>> fetchRecentEventsForCards(
    List<String> cardIds, {
    int limit = 20,
  }) {
    final sortedIds = [...cardIds]..sort();
    final key = 'fetchRecentEventsForCards:${sortedIds.join(',')}:$limit';
    return RequestDeduper.run(
      key,
      () => _fetchRecentEventsForCardsUncached(cardIds, limit: limit),
    );
  }

  static Future<List<VisitEventModel>> _fetchRecentEventsForCardsUncached(
    List<String> cardIds, {
    int limit = 20,
  }) async {
    final uniqueCardIds = cardIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueCardIds.isEmpty) return const [];

    final rows = uniqueCardIds.length == 1
        ? await _db
              .from('visit_events')
              .select()
              .eq('card_id', uniqueCardIds.first)
              .order('timestamp', ascending: false)
              .limit(limit)
        : await _db
              .from('visit_events')
              .select()
              .inFilter('card_id', uniqueCardIds)
              .order('timestamp', ascending: false)
              .limit(limit);

    final events = (rows as List)
        .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return hydrateEvents(events);
  }

  // ─── Record a visit (fire-and-forget) ────────────────────────────────────

  /// source: 'nfc' | 'qr' | 'link'
  static Future<void> recordVisit(String cardId, String source) async {
    try {
      final info = await _safeVisitorInfo();
      await _recordCardVisit(cardId: cardId, source: source, info: info);
    } catch (e) {
      debugPrint('[Analytics] recordVisit error: $e');
    }
  }

  // ─── Record an interaction (contact tap / social tap / form fill) ─────────

  /// source: 'contact' | 'social' | 'form' | 'downloaded_contact' | 'share'
  /// label: displayLabel / platform name / form title
  static Future<void> recordInteraction({
    required String cardId,
    required String source,
    String? contactItemId,
    String? socialLinkId,
    String? smartFormId,
  }) async {
    try {
      final info = await _safeVisitorInfo();
      await _recordCardVisit(
        cardId: cardId,
        source: source,
        contactItemId: contactItemId,
        socialLinkId: socialLinkId,
        smartFormId: smartFormId,
        info: info,
      );
    } catch (e) {
      debugPrint('[Analytics] recordInteraction error: $e');
    }
  }

  static Future<void> _recordCardVisit({
    required String cardId,
    required String source,
    String? contactItemId,
    String? socialLinkId,
    String? smartFormId,
    required Map<String, String?> info,
  }) async {
    Object? lastError;
    final attempts = <Map<String, dynamic>>[
      {
        'p_card_id': cardId,
        'p_source': source,
        'p_device': info['device'],
        'p_ip': info['ip'],
        'p_city': info['city'],
        'p_country': info['country'],
        'p_contact_item_id': contactItemId,
        'p_social_link_id': socialLinkId,
        'p_smart_form_id': smartFormId,
      },
      {
        'p_card_id': cardId,
        'p_source': source,
        'p_device': info['device'],
        'p_ip': info['ip'],
        'p_city': info['city'],
        'p_country': info['country'],
        'p_contact_item_id': null,
        'p_social_link_id': null,
        'p_smart_form_id': null,
      },
    ];

    for (final params in attempts) {
      try {
        await _db.rpc('record_card_visit', params: params);
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      'record_card_visit failed for source=$source card=$cardId: $lastError',
    );
  }

  // ─── Recent visit events (last N) ────────────────────────────────────────

  static Future<List<VisitEventModel>> fetchRecentEvents(
    String cardId, {
    int limit = 20,
  }) async {
    final rows = await _db
        .from('visit_events')
        .select()
        .eq('card_id', cardId)
        .order('timestamp', ascending: false)
        .limit(limit);
    final events = (rows as List)
        .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return hydrateEvents(events);
  }

  static Future<List<VisitEventModel>> hydrateEvents(
    List<VisitEventModel> events,
  ) async {
    if (events.isEmpty) return const [];
    final currentLinksByRef = await _fetchCurrentLinksByRef(
      contactItemIds: events
          .map((event) => event.contactItemId)
          .whereType<String>()
          .toSet()
          .toList(),
      socialLinkIds: events
          .map((event) => event.socialLinkId)
          .whereType<String>()
          .toSet()
          .toList(),
      smartFormIds: events
          .map((event) => event.smartFormId)
          .whereType<String>()
          .toSet()
          .toList(),
    );
    return events.map((event) {
      final resolved = _resolveLinkReference(
        event: event,
        currentLinksByRef: currentLinksByRef,
      );
      if (resolved.label.isEmpty) return event;
      return event.copyWith(label: resolved.label);
    }).toList();
  }

  static String _eventLinkKey(
    VisitEventModel event, {
    required String fallbackLabel,
  }) {
    if ((event.contactItemId?.trim().isNotEmpty ?? false)) {
      return 'contact:${event.contactItemId!.trim()}';
    }
    if ((event.socialLinkId?.trim().isNotEmpty ?? false)) {
      return 'social:${event.socialLinkId!.trim()}';
    }
    return 'legacy:${event.source ?? ''}:$fallbackLabel';
  }

  static _ResolvedLinkReference _resolveLinkReference({
    required VisitEventModel event,
    Map<String, _ResolvedLinkReference> currentLinksByRef = const {},
  }) {
    if ((event.contactItemId?.trim().isNotEmpty ?? false)) {
      final key = 'contact:${event.contactItemId!.trim()}';
      final resolved = currentLinksByRef[key];
      if (resolved != null) return resolved;
    }
    if ((event.socialLinkId?.trim().isNotEmpty ?? false)) {
      final key = 'social:${event.socialLinkId!.trim()}';
      final resolved = currentLinksByRef[key];
      if (resolved != null) return resolved;
    }
    if ((event.smartFormId?.trim().isNotEmpty ?? false)) {
      final key = 'form:${event.smartFormId!.trim()}';
      final resolved = currentLinksByRef[key];
      if (resolved != null) return resolved;
    }
    final hydratedLabel = event.label?.trim();
    if (hydratedLabel != null && hydratedLabel.isNotEmpty) {
      return _ResolvedLinkReference(
        label: hydratedLabel,
        platform: event.source ?? '',
      );
    }
    final fallbackLabel = switch (event.source) {
      'contact' => 'Contacto',
      'social' => 'Red social',
      'form' => 'Formulario',
      'downloaded_contact' => 'Guardó contacto',
      'share' => 'Compartió perfil',
      'link' => 'Abrió perfil',
      _ => '',
    };
    return _ResolvedLinkReference(
      label: fallbackLabel,
      platform: event.source ?? '',
    );
  }

  static Future<Map<String, _ResolvedLinkReference>> _fetchCurrentLinksByRef({
    required List<String> contactItemIds,
    required List<String> socialLinkIds,
    required List<String> smartFormIds,
  }) async {
    final resolved = <String, _ResolvedLinkReference>{};

    if (contactItemIds.isNotEmpty) {
      final contactRows = await _db
          .from('contact_items')
          .select('id, type, label')
          .inFilter('id', contactItemIds);
      for (final row in (contactRows as List).cast<Map<String, dynamic>>()) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final item = ContactItemModel.fromJson(row);
        resolved['contact:$id'] = _ResolvedLinkReference(
          label: item.displayLabel,
          platform: item.type.name,
        );
      }
    }

    if (socialLinkIds.isNotEmpty) {
      final socialRows = await _db
          .from('social_links')
          .select('id, platform, custom_label')
          .inFilter('id', socialLinkIds);
      for (final row in (socialRows as List).cast<Map<String, dynamic>>()) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final link = SocialLinkModel.fromJson(row);
        resolved['social:$id'] = _ResolvedLinkReference(
          label: link.label,
          platform: link.platform.name,
        );
      }
    }

    if (smartFormIds.isNotEmpty) {
      final formRows = await _db
          .from('smart_forms')
          .select('id, name')
          .inFilter('id', smartFormIds);
      for (final row in (formRows as List).cast<Map<String, dynamic>>()) {
        final id = row['id'] as String?;
        if (id == null) continue;
        resolved['form:$id'] = _ResolvedLinkReference(
          label: row['name'] as String? ?? 'Formulario',
          platform: 'form',
        );
      }
    }

    return resolved;
  }
}
