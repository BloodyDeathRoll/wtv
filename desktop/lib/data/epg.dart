import 'dart:convert';

import 'package:flutter/foundation.dart' show mergeSort;
import 'package:http/http.dart' as http;

import 'json.dart';
import 'provider_login.dart';
import 'session.dart';

/// One programme of a channel's guide; times in Unix seconds. `archived`: it
/// can be played back (catch-up); `providerStart` is its start as the provider
/// writes it, in the server's own time, which the catch-up address needs.
class Programme {
  const Programme(this.title, this.description, this.start, this.end, {this.archived = false, this.providerStart});

  final String title;
  final String? description;
  final int start;
  final int end;
  final bool archived;
  final String? providerStart;
}

/// The next few programmes of a live channel from the provider's short guide
/// (`get_short_epg`). The provider's catalog API takes the client's own user
/// agent. Empty when the channel has no guide; throws when the call fails.
Future<List<Programme>> shortEpg(http.Client client, ProviderLogin login, int streamId, {int limit = 4}) async =>
    programmes(await _guideCall(client, login, 'get_short_epg', streamId, {'limit': '$limit'}));

/// The programmes of a catch-up channel that can be played back, newest first:
/// archived and already over at `now` (Unix seconds). The full guide
/// (`get_simple_data_table`) is a few hundred rows.
Future<List<Programme>> archive(http.Client client, ProviderLogin login, int streamId, int now) async =>
    playable(programmes(await _guideCall(client, login, 'get_simple_data_table', streamId)), now);

/// Archived, over at `now`, with a start a catch-up address can be made from; one per start, newest first.
List<Programme> playable(List<Programme> programmes, int now) {
  final seen = <int>{};
  return programmes
      .where((p) => p.archived && p.end <= now && providerStartParts(p.providerStart) != null)
      .where((p) => seen.add(p.start))
      .toList()
    ..sort((a, b) => b.start.compareTo(a.start));
}

/// "2026-11-18 07:40:00" as day, hour and minute; null when it is not that shape.
(String, String, String)? providerStartParts(String? text) {
  final match = text == null ? null : RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})').firstMatch(text);
  return match == null ? null : (match[1]!, match[2]!, match[3]!);
}

Future<String> _guideCall(
  http.Client client,
  ProviderLogin login,
  String action,
  int streamId, [
  Map<String, String> extra = const {},
]) async {
  final url = Uri.parse('${serverBase(login)}/player_api.php').replace(
    queryParameters: {
      'username': login.user.trim(),
      'password': login.password,
      'action': action,
      'stream_id': '$streamId',
      ...extra,
    },
  );
  // The URL holds the login: it never goes into an error message.
  final http.Response response;
  try {
    response = await client.get(url).timeout(callTimeout);
  } on Exception {
    throw ApiException('Guide: no connection');
  }
  if (response.statusCode < 200 || response.statusCode > 299) throw ApiException('Guide: HTTP ${response.statusCode}');
  // As the TV app reads it: UTF-8 unless the answer names another charset.
  final named = response.headers['content-type']?.contains('charset=') ?? false;
  return named ? response.body : utf8.decode(response.bodyBytes, allowMalformed: true);
}

/// Parses a short-guide answer. Titles and descriptions arrive base64-encoded; text that is not, is kept as it is.
List<Programme> programmes(String json) {
  final JsonArray? list;
  try {
    list = jsonObject(json).optArray('epg_listings');
  } on FormatException {
    return [];
  }
  final found = <Programme>[];
  for (final p in list ?? const []) {
    if (p is! JsonObject) continue;
    final title = _decode(p.optString('title'));
    final start = int.tryParse(p.optString('start_timestamp'), radix: 10);
    final end = int.tryParse(p.optString('stop_timestamp'), radix: 10);
    if (title == null || start == null || end == null || end <= start) continue;
    final providerStart = p.optString('start');
    found.add(
      Programme(
        title,
        _decode(p.optString('description')),
        start,
        end,
        archived: p.optString('has_archive') == '1',
        providerStart: providerStart.trim().isEmpty ? null : providerStart,
      ),
    );
  }
  // Programmes with the same start keep their order.
  mergeSort(found, compare: (a, b) => a.start.compareTo(b.start));
  return found;
}

final _base64Text = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');

String? _decode(String s) {
  final text = s.trim();
  if (text.isEmpty) return null;
  // The provider pads its base64; unpadded or invalid text was sent plain.
  if (text.length % 4 != 0 || !_base64Text.hasMatch(text)) return text;
  try {
    // Text that decodes to bytes that are not readable UTF-8 ("News"), or to control
    // characters ("AAAA"), was sent plain too.
    final decoded = utf8.decode(base64.decode(text)).trim();
    return decoded.isEmpty || decoded.codeUnits.any((c) => c <= 0x1F || (c >= 0x7F && c <= 0x9F)) ? text : decoded;
  } on FormatException {
    return text;
  }
}

/// What is on at `now` (Unix seconds), and what follows it.
(Programme?, Programme?) nowAndNext(List<Programme> programmes, int now) {
  final i = programmes.indexWhere((p) => now >= p.start && now < p.end);
  return i >= 0
      ? (programmes[i], programmes.elementAtOrNull(i + 1))
      : (null, programmes.where((p) => p.start > now).firstOrNull);
}

/// The guide panel's lead (the catch-up programme playing, else what is on at `now`) and what is
/// still to come after it: not yet over at `now`, one per start (providers repeat entries).
(Programme?, List<Programme>) guideOf(List<Programme> programmes, Programme? playing, int now) {
  final lead = playing ?? nowAndNext(programmes, now).$1;
  final end = lead?.end ?? now;
  final from = end > now ? end : now;
  final seen = <int>{};
  return (lead, programmes.where((p) => p.start >= from).where((p) => seen.add(p.start)).toList());
}
