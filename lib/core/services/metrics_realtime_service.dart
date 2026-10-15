import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class MetricsRealtimeSubscription {
  // Card ids known to belong to each org (filled by AdminRepository after
  // loading the team). The database is shared with other apps/orgs, so
  // org-wide subscriptions on card-scoped tables would otherwise refresh on
  // every visit to ANY card.
  static final Map<String, Set<String>> _orgCardIds = {};
  static final Map<String, DateTime> _lastOrgChangeAt = {};

  static void registerOrgCards(String orgId, Iterable<String> cardIds) {
    _orgCardIds[orgId] = cardIds.toSet();
  }

  /// When an org-wide subscription last detected a relevant change; cached
  /// org data fetched before this instant is stale.
  static DateTime? lastOrgChangeAt(String orgId) => _lastOrgChangeAt[orgId];

  final VoidCallback onRefresh;
  final Duration debounce;
  final Duration pollInterval;
  final RealtimeChannel _channel;
  final String? _orgId;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _closed = false;

  MetricsRealtimeSubscription._({
    required this.onRefresh,
    required this.debounce,
    required this.pollInterval,
    required RealtimeChannel channel,
    String? orgId,
  }) : _channel = channel,
       _orgId = orgId;

  factory MetricsRealtimeSubscription.forCard({
    required String cardId,
    required VoidCallback onRefresh,
    Duration debounce = const Duration(milliseconds: 450),
    Duration pollInterval = const Duration(minutes: 1),
  }) {
    final subscription = MetricsRealtimeSubscription._(
      onRefresh: onRefresh,
      debounce: debounce,
      pollInterval: pollInterval,
      channel: SupabaseService.client.channel(
        'metrics:card:$cardId:${DateTime.now().microsecondsSinceEpoch}',
      ),
    );

    subscription
      .._watchTable(
        table: 'visit_events',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'card_id',
          value: cardId,
        ),
      )
      .._watchTable(
        table: 'contact_items',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'card_id',
          value: cardId,
        ),
      )
      .._watchTable(
        table: 'social_links',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'card_id',
          value: cardId,
        ),
      )
      .._watchTable(
        table: 'leads',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'card_id',
          value: cardId,
        ),
      )
      .._watchTable(table: 'lead_actions')
      .._subscribe();

    return subscription;
  }

  factory MetricsRealtimeSubscription.forOrganization({
    required String orgId,
    required VoidCallback onRefresh,
    Duration debounce = const Duration(milliseconds: 1500),
    Duration pollInterval = const Duration(minutes: 2),
  }) {
    final subscription = MetricsRealtimeSubscription._(
      onRefresh: onRefresh,
      debounce: debounce,
      pollInterval: pollInterval,
      orgId: orgId,
      channel: SupabaseService.client.channel(
        'metrics:org:$orgId:${DateTime.now().microsecondsSinceEpoch}',
      ),
    );

    subscription
      // visit_events, contact_items, social_links and lead_actions have no
      // org_id column of their own (only card_id/lead_id), so they can't be
      // filtered server-side by org without risking missed events for cards
      // created after this subscription starts. `leads` does have org_id,
      // so filter that one the same way as users/digital_cards below.
      .._watchTable(table: 'visit_events', orgCardScoped: true)
      .._watchTable(table: 'contact_items', orgCardScoped: true)
      .._watchTable(table: 'social_links', orgCardScoped: true)
      .._watchTable(
        table: 'leads',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'org_id',
          value: orgId,
        ),
      )
      // lead_actions has no card/org column to filter on; watching it
      // org-wide meant refreshing on every lead action in the shared DB.
      // Lead changes still arrive through `leads` and the periodic poll.
      .._watchTable(
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'org_id',
          value: orgId,
        ),
      )
      .._watchTable(
        table: 'digital_cards',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'org_id',
          value: orgId,
        ),
      )
      .._subscribe();

    return subscription;
  }

  void _watchTable({
    required String table,
    PostgresChangeFilter? filter,
    bool orgCardScoped = false,
  }) {
    _channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: filter,
      callback: (payload) {
        if (orgCardScoped && !_isOrgCardPayload(payload)) return;
        _scheduleRefresh();
      },
    );
  }

  bool _isOrgCardPayload(PostgresChangePayload payload) {
    final orgId = _orgId;
    final known = orgId == null ? null : _orgCardIds[orgId];
    // Until the org's cards are known, don't drop anything.
    if (known == null || known.isEmpty) return true;
    final cardId =
        payload.newRecord['card_id'] as String? ??
        payload.oldRecord['card_id'] as String?;
    return cardId == null || known.contains(cardId);
  }

  void _subscribe() {
    _channel.subscribe();
    // No initial _scheduleRefresh() here: every caller already does its own
    // explicit load in initState() right alongside creating this
    // subscription, so an automatic refresh ~450-500ms later was just a
    // second, redundant fetch of the same data on every screen mount.
    _pollTimer = Timer.periodic(pollInterval, (_) => _scheduleRefresh());
  }

  void _scheduleRefresh() {
    if (_closed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (_closed) return;
      final orgId = _orgId;
      if (orgId != null) _lastOrgChangeAt[orgId] = DateTime.now();
      onRefresh();
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    unawaited(SupabaseService.client.removeChannel(_channel));
  }
}
