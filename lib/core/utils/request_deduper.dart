/// Coalesces concurrent identical async requests.
///
/// Several widgets in this app independently fetch the same data (e.g. the
/// dashboard, analytics and team-performance screens all call
/// `fetchTeamMembers` for the same org within milliseconds of each other).
/// [RequestDeduper.run] makes sure that when a request for a given [key] is
/// already in flight, callers awaiting it receive the result of that same
/// in-flight request instead of starting a brand-new round trip.
///
/// This is intentionally *not* a cache: once the in-flight request settles
/// (success or error), the key is cleared immediately, so the very next call
/// starts a fresh request. It only removes duplicate work for calls that
/// overlap in time; it never serves stale data.
class RequestDeduper {
  RequestDeduper._();

  static final Map<String, Future<Object?>> _inFlight = {};

  static Future<T> run<T>(String key, Future<T> Function() request) {
    final existing = _inFlight[key];
    if (existing != null) {
      return existing.then((value) => value as T);
    }

    final future = request();
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    });
    return future;
  }
}
