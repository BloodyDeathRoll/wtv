import 'package:http/http.dart' as http;

import 'epg.dart';
import 'provider_login.dart';
import 'semaphore.dart';

/// What is on now on each channel, for the channel grid: fetched for the cards
/// on screen, a few at a time, and kept until the programme ends (ten minutes
/// when the channel has no guide). Process-wide, so going back to Live TV
/// does not fetch again.
abstract final class OnNow {
  static final _cache = <int, ({Programme? programme, int validUntil})>{};
  // A screenful of cards is ~20: four calls at a time keeps the provider's limits.
  static final _calls = Semaphore(4);

  /// The cached answer, if still valid at `now` (Unix seconds); else null, and `known` is false.
  static (bool, Programme?) cached(int streamId, int now) {
    final entry = _cache[streamId];
    return entry != null && entry.validUntil > now ? (true, entry.programme) : (false, null);
  }

  /// The programme on now, from the provider's short guide; null when there is
  /// none, or when the call failed (then asked again a minute later at most,
  /// so cards scrolling past do not hammer a provider that is down).
  static Future<Programme?> fetch(http.Client client, ProviderLogin login, int streamId, int now) async {
    final (known, kept) = cached(streamId, now);
    if (known) return kept;
    final Programme? programme;
    try {
      programme = await _calls.withPermit(() async => onAt(await shortEpg(client, login, streamId, limit: 2), now));
    } on Exception {
      _cache[streamId] = (programme: null, validUntil: now + _failedSecs);
      return null;
    }
    _cache[streamId] = (programme: programme, validUntil: programme?.end ?? now + _noGuideSecs);
    return programme;
  }

  /// Drops every kept answer (for tests: the cache outlives a page).
  static void forget() => _cache.clear();

  static const _noGuideSecs = 600;
  static const _failedSecs = 60;
}

/// The programme running at `now`, if any.
Programme? onAt(List<Programme> programmes, int now) => programmes.where((p) => p.start <= now && now < p.end).firstOrNull;
