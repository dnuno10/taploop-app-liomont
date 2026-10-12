import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class MetricsRealtimeSubscription {
  final VoidCallback onRefresh;
  final Duration debounce;
  final Duration pollInterval;
  final RealtimeChannel _channel;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _closed = false;

  MetricsRealtimeSubscription._({
    required this.onRefresh,
    required this.debounce,
    required this.pollInterval,
    required RealtimeChannel channel,
  }) : _channel = channel;

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
    Duration debounce = const Duration(milliseconds: 500),
    Duration pollInterval = const Duration(minutes: 2),
  }) {
    final subscription = MetricsRealtimeSubscription._(
      onRefresh: onRefresh,
      debounce: debounce,
      pollInterval: pollInterval,
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
      .._watchTable(table: 'visit_events')
      .._watchTable(table: 'contact_items')
      .._watchTable(table: 'social_links')
      .._watchTable(
        table: 'leads',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'org_id',
          value: orgId,
        ),
      )
      .._watchTable(table: 'lead_actions')
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

  void _watchTable({required String table, PostgresChangeFilter? filter}) {
    _channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: filter,
      callback: (_) => _scheduleRefresh(),
    );
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
