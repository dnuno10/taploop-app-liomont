import 'package:flutter/foundation.dart';

import '../../services/supabase_service.dart';
import '../../utils/request_deduper.dart';
import '../../../features/analytics/models/lead_model.dart';
import '../../../features/analytics/models/visit_event_model.dart';
import 'analytics_repository.dart';

class _VisitorSession {
  final String signature;
  final String? clientId;
  final List<VisitEventModel> events;

  const _VisitorSession({
    required this.signature,
    required this.clientId,
    required this.events,
  });

  DateTime get start => events.first.timestamp;
  DateTime get end => events.last.timestamp;
}

class LeadRepository {
  LeadRepository._();

  static final _db = SupabaseService.client;

  // ─── Fetch leads for a card ───────────────────────────────────────────────

  static Future<List<LeadModel>> fetchLeadsForCard(String cardId) {
    // PipelineView and SalesOutcomeView both call this for the same card
    // and both stay mounted once visited, so a single realtime event can
    // trigger both at once — coalesce overlapping calls.
    return RequestDeduper.run(
      'fetchLeadsForCard:$cardId',
      () => _fetchLeadsForCardUncached(cardId),
    );
  }

  static Future<List<LeadModel>> _fetchLeadsForCardUncached(
    String cardId,
  ) async {
    final rows = await _db
        .from('leads')
        .select()
        .eq('card_id', cardId)
        .order('last_seen', ascending: false);
    final leads = (rows as List)
        .map((e) => LeadModel.fromJson(e as Map<String, dynamic>))
        .toList();

    List<VisitEventModel> visitEvents = const [];
    try {
      final rows = await _db
          .from('visit_events')
          .select()
          .eq('card_id', cardId)
          .order('timestamp', ascending: true)
          .limit(800);
      visitEvents = (rows as List)
          .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
          .toList();
      visitEvents = await AnalyticsRepository.hydrateEvents(visitEvents);
    } catch (_) {
      visitEvents = const [];
    }

    final inferredByLead = _inferActionsByLead(leads, visitEvents);

    // Enrich each lead with DB actions and inferred visit-event actions.
    Map<String, List<LeadActionEvent>> dbActionsByLead = const {};
    try {
      dbActionsByLead = await _fetchActionsForLeads(
        leads.map((lead) => lead.id).toList(),
      );
    } catch (_) {
      dbActionsByLead = const {};
    }

    return leads.map((lead) {
      final dbActions = dbActionsByLead[lead.id] ?? const <LeadActionEvent>[];
      final inferredActions = inferredByLead[lead.id] ?? const [];
      final merged = _mergeActions(dbActions, inferredActions);
      return lead.copyWith(actions: merged);
    }).toList();
  }

  static Future<List<LeadModel>> fetchDashboardLeadsForCard(
    String cardId, {
    int limit = 6,
  }) {
    return RequestDeduper.run(
      'fetchDashboardLeadsForCard:$cardId:$limit',
      () => _fetchDashboardLeadsForCardUncached(cardId, limit: limit),
    );
  }

  static Future<List<LeadModel>> _fetchDashboardLeadsForCardUncached(
    String cardId, {
    int limit = 6,
  }) async {
    final rows = await _db
        .from('leads')
        .select()
        .eq('card_id', cardId)
        .order('last_seen', ascending: false)
        .limit(limit * 3);

    final leads = (rows as List)
        .map((e) => LeadModel.fromJson(e as Map<String, dynamic>))
        .toList();

    leads.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return b.lastSeen.compareTo(a.lastSeen);
    });

    return leads.take(limit).toList();
  }

  static Future<Map<String, List<LeadModel>>> fetchLeadsForCards(
    List<String> cardIds,
  ) async {
    if (cardIds.isEmpty) return const {};

    final rows = await _db
        .from('leads')
        .select()
        .inFilter('card_id', cardIds)
        .order('last_seen', ascending: false);
    final leads = (rows as List)
        .map((e) => LeadModel.fromJson(e as Map<String, dynamic>))
        .toList();

    List<VisitEventModel> visitEvents = const [];
    try {
      final visitRows = await _db
          .from('visit_events')
          .select()
          .inFilter('card_id', cardIds)
          .order('timestamp', ascending: true)
          .limit(5000);
      visitEvents = (visitRows as List)
          .map((e) => VisitEventModel.fromJson(e as Map<String, dynamic>))
          .toList();
      visitEvents = await AnalyticsRepository.hydrateEvents(visitEvents);
    } catch (_) {
      visitEvents = const [];
    }

    final byCard = <String, List<LeadModel>>{};
    for (final lead in leads) {
      final cardId = lead.cardId;
      if (cardId == null) continue;
      byCard.putIfAbsent(cardId, () => []).add(lead);
    }

    final eventsByCard = <String, List<VisitEventModel>>{};
    for (final event in visitEvents) {
      final cardId = event.cardId;
      if (cardId == null || cardId.isEmpty) continue;
      eventsByCard.putIfAbsent(cardId, () => []).add(event);
    }

    Map<String, List<LeadActionEvent>> dbActionsByLead = const {};
    try {
      dbActionsByLead = await _fetchActionsForLeads(
        leads.map((lead) => lead.id).toList(),
      );
    } catch (_) {
      dbActionsByLead = const {};
    }

    final result = <String, List<LeadModel>>{};
    for (final entry in byCard.entries) {
      final cardLeads = entry.value;
      final cardEvents = eventsByCard[entry.key] ?? const <VisitEventModel>[];
      final inferredByLead = _inferActionsByLead(cardLeads, cardEvents);
      result[entry.key] = cardLeads.map((lead) {
        final dbActions =
            dbActionsByLead[lead.id] ?? const <LeadActionEvent>[];
        final inferredActions = inferredByLead[lead.id] ?? const [];
        final merged = _mergeActions(dbActions, inferredActions);
        return lead.copyWith(actions: merged);
      }).toList();
    }

    return result;
  }

  // ─── Fetch lead actions (timeline) ───────────────────────────────────────

  static Future<List<LeadActionEvent>> fetchActions(String leadId) async {
    final rows = await _db
        .from('lead_actions')
        .select()
        .eq('lead_id', leadId)
        .order('timestamp');
    return (rows as List)
        .map((e) => LeadActionEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Batched version of [fetchActions]: resolves the action timeline for
  /// every lead in [leadIds] with a single query instead of one query per
  /// lead.
  static Future<Map<String, List<LeadActionEvent>>> _fetchActionsForLeads(
    List<String> leadIds,
  ) async {
    final ids = leadIds.toSet().toList();
    if (ids.isEmpty) return const {};

    final rows = await _db
        .from('lead_actions')
        .select()
        .inFilter('lead_id', ids)
        .order('timestamp');

    final byLead = <String, List<LeadActionEvent>>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final leadId = row['lead_id'] as String?;
      if (leadId == null) continue;
      byLead.putIfAbsent(leadId, () => []).add(LeadActionEvent.fromJson(row));
    }
    return byLead;
  }

  static Map<String, List<LeadActionEvent>> _inferActionsByLead(
    List<LeadModel> leads,
    List<VisitEventModel> visitEvents,
  ) {
    if (leads.isEmpty || visitEvents.isEmpty) return {};

    final sessions = _buildSessions(visitEvents);
    final sortedLeads = [...leads]
      ..sort((a, b) => a.firstSeen.compareTo(b.firstSeen));
    final usedSessionIndexes = <int>{};
    final result = <String, List<LeadActionEvent>>{};

    for (final lead in sortedLeads) {
      final leadClientId = _leadClientId(lead);

      if (leadClientId != null && leadClientId.isNotEmpty) {
        final allEventsForClient =
            sessions
                .where((s) => s.clientId == leadClientId)
                .expand((s) => s.events)
                .toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        result[lead.id] = allEventsForClient
            .map(_visitEventToLeadAction)
            .whereType<LeadActionEvent>()
            .toList();
        continue;
      }

      final idx = _bestSessionIndex(
        lead: lead,
        leadClientId: leadClientId,
        sessions: sessions,
        excluded: usedSessionIndexes,
      );

      if (idx == null) {
        result[lead.id] = const [];
        continue;
      }

      usedSessionIndexes.add(idx);
      final actions = sessions[idx].events
          .map(_visitEventToLeadAction)
          .whereType<LeadActionEvent>()
          .toList();
      result[lead.id] = actions;
    }

    return result;
  }

  static List<_VisitorSession> _buildSessions(List<VisitEventModel> events) {
    final bySignature = <String, List<VisitEventModel>>{};

    for (final e in events) {
      final signature = _signatureFor(e);
      bySignature.putIfAbsent(signature, () => []).add(e);
    }

    final sessions = <_VisitorSession>[];
    const splitGap = Duration(minutes: 45);

    for (final entry in bySignature.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      List<VisitEventModel> current = [];

      for (final ev in sorted) {
        if (current.isEmpty) {
          current = [ev];
          continue;
        }

        final gap = ev.timestamp.difference(current.last.timestamp);
        if (gap > splitGap) {
          sessions.add(
            _VisitorSession(
              signature: entry.key,
              clientId: _extractClientId(current.first.device),
              events: current,
            ),
          );
          current = [ev];
        } else {
          current.add(ev);
        }
      }

      if (current.isNotEmpty) {
        sessions.add(
          _VisitorSession(
            signature: entry.key,
            clientId: _extractClientId(current.first.device),
            events: current,
          ),
        );
      }
    }

    sessions.sort((a, b) => a.start.compareTo(b.start));
    return sessions;
  }

  static String _signatureFor(VisitEventModel e) {
    final clientId = _extractClientId(e.device);
    final ip = e.ip?.trim();
    final device = e.device?.trim();
    final city = e.city?.trim();
    final country = e.country?.trim();

    if (clientId != null && clientId.isNotEmpty) {
      return 'cid:$clientId';
    }

    final parts = [
      ip,
      device,
      city,
      country,
    ].whereType<String>().where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) return 'unknown:${e.id}';
    return parts.join('|');
  }

  static int? _bestSessionIndex({
    required LeadModel lead,
    required String? leadClientId,
    required List<_VisitorSession> sessions,
    required Set<int> excluded,
  }) {
    if (leadClientId != null && leadClientId.isNotEmpty) {
      final exact = <int>[];
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].clientId == leadClientId) exact.add(i);
      }
      if (exact.isNotEmpty) {
        final unused = exact.where((i) => !excluded.contains(i)).toList();
        final pool = unused.isNotEmpty ? unused : exact;
        pool.sort((a, b) {
          final da = _sessionDistance(lead, sessions[a]);
          final db = _sessionDistance(lead, sessions[b]);
          return da.compareTo(db);
        });
        return pool.first;
      }
    }

    double? bestScore;
    int? bestIdx;

    for (var i = 0; i < sessions.length; i++) {
      if (excluded.contains(i)) continue;
      final s = sessions[i];
      final score = _sessionDistance(lead, s);
      if (bestScore == null || score < bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }

    if (bestIdx != null) return bestIdx;

    for (var i = 0; i < sessions.length; i++) {
      final score = _sessionDistance(lead, sessions[i]);
      if (bestScore == null || score < bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }

    return bestIdx;
  }

  static String? _leadClientId(LeadModel lead) {
    final data = lead.formData;
    if (data == null) return null;
    final direct = data['_client_device_id'] ?? data['client_device_id'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    final nested = data['_meta'];
    if (nested is Map<String, dynamic>) {
      final v = nested['client_device_id'];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static String? _extractClientId(String? deviceField) {
    if (deviceField == null || deviceField.isEmpty) return null;
    final match = RegExp(r'cid:([^|]+)').firstMatch(deviceField);
    return match?.group(1)?.trim();
  }

  static double _sessionDistance(LeadModel lead, _VisitorSession s) {
    final leadStart = lead.firstSeen.subtract(const Duration(minutes: 30));
    final leadEnd = lead.lastSeen.add(const Duration(minutes: 30));
    final overlaps = !s.end.isBefore(leadStart) && !s.start.isAfter(leadEnd);
    if (overlaps) return 0;

    final d1 = (s.start.difference(lead.firstSeen)).inSeconds.abs();
    final d2 = (s.end.difference(lead.lastSeen)).inSeconds.abs();
    return d1 < d2 ? d1.toDouble() : d2.toDouble();
  }

  static LeadActionEvent? _visitEventToLeadAction(VisitEventModel e) {
    final source = (e.source ?? '').toLowerCase();
    final label = e.label?.trim();

    if (source == 'nfc' || source == 'qr') {
      return LeadActionEvent(
        action: LeadAction.visitedProfile,
        timestamp: e.timestamp,
        customLabel: 'Escaneó NFC',
      );
    }

    if (source == 'form') {
      return LeadActionEvent(
        action: LeadAction.filledForm,
        timestamp: e.timestamp,
        customLabel: label?.isNotEmpty == true ? label : 'Llenó formulario',
      );
    }

    if (source == 'downloaded_contact') {
      return LeadActionEvent(
        action: LeadAction.downloadedContact,
        timestamp: e.timestamp,
        customLabel: label?.isNotEmpty == true ? label : 'Guardó contacto',
      );
    }

    if (source == 'share') {
      return LeadActionEvent(
        action: LeadAction.clickedWebsite,
        timestamp: e.timestamp,
        customLabel: label?.isNotEmpty == true ? label : 'Compartió perfil',
      );
    }

    if (source == 'contact' || source == 'social' || source == 'link') {
      final lower = (label ?? '').toLowerCase();
      if (lower.contains('whatsapp')) {
        return LeadActionEvent(
          action: LeadAction.clickedWhatsApp,
          timestamp: e.timestamp,
          customLabel: label?.isNotEmpty == true ? label : 'Abrió WhatsApp',
        );
      }
      if (lower.contains('linkedin')) {
        return LeadActionEvent(
          action: LeadAction.clickedLinkedIn,
          timestamp: e.timestamp,
          customLabel: label?.isNotEmpty == true ? label : 'Click en LinkedIn',
        );
      }

      final isProfileOpen =
          source == 'link' && (label == null || label.isEmpty);
      if (isProfileOpen) {
        return LeadActionEvent(
          action: LeadAction.visitedProfile,
          timestamp: e.timestamp,
          customLabel: 'Abrió perfil',
        );
      }

      return LeadActionEvent(
        action: LeadAction.clickedWebsite,
        timestamp: e.timestamp,
        customLabel: label?.isNotEmpty == true
            ? label
            : 'Interacción en enlace',
      );
    }

    return null;
  }

  static List<LeadActionEvent> _mergeActions(
    List<LeadActionEvent> dbActions,
    List<LeadActionEvent> inferredActions,
  ) {
    if (dbActions.isEmpty) {
      return [...inferredActions]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    if (inferredActions.isEmpty) {
      return [...dbActions]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    final merged = [...dbActions, ...inferredActions];
    final dedup = <String, LeadActionEvent>{};
    for (final a in merged) {
      final key =
          '${a.action.name}|${a.timestamp.millisecondsSinceEpoch}|${a.label}';
      dedup[key] = a;
    }
    final out = dedup.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return out;
  }

  // ─── Update pipeline stage ────────────────────────────────────────────────

  static Future<void> updatePipelineStage(String leadId, String stage) async {
    await _db.from('leads').update({'pipeline_stage': stage}).eq('id', leadId);
  }

  // ─── Mark as converted ────────────────────────────────────────────────────

  static Future<void> markConverted(String leadId, bool value) async {
    await _db.from('leads').update({'is_converted': value}).eq('id', leadId);
  }

  // ─── Submit form lead (called from public card) ───────────────────────────

  static Future<void> submitFormLead({
    required String cardId,
    required String formType,
    required String name,
    String? email,
    String? phone,
    String? company,
    required Map<String, String> formData,
  }) async {
    final errors = <String>[];
    final attempts = <Map<String, dynamic>>[
      {
        'p_card_id': cardId,
        'p_form_id': formType,
        'p_name': name,
        'p_email': email,
        'p_phone': phone,
        'p_company': company,
        'p_form_data': formData,
      },
      {
        'p_card_id': cardId,
        'p_form_type': formType,
        'p_name': name,
        'p_email': email,
        'p_phone': phone,
        'p_company': company,
        'p_form_data': formData,
      },
    ];

    for (final params in attempts) {
      try {
        await _db.rpc('submit_card_form', params: params);
        return;
      } catch (error) {
        errors.add('params=${params.keys.join(",")}: $error');
      }
    }

    final message = 'submit_card_form failed: ${errors.join(' | ')}';
    debugPrint('[LeadRepository] $message');
    throw Exception(message);
  }
}
