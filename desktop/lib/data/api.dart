import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart' as config;
import 'json.dart';
import 'session.dart';

/// Reads from and writes to the WTV database's REST API with the session's token.
class Api {
  Api(this._session, this._http, {this.url = config.supabaseUrl, this.key = config.supabaseKey});

  final Session _session;
  final http.Client _http;
  final String url;
  final String key;

  /// `path` is a PostgREST path and query, e.g. `titles?select=id&limit=10`.
  Future<JsonArray> get(String path) async {
    final body = await _send(path, verb: 'load');
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }
    if (json is! JsonArray) throw ApiException('Could not read ${path.split('?').first}');
    return json;
  }

  /// POSTs a JSON `body` to `path`; `prefer` is PostgREST's Prefer header (upserts).
  Future<void> post(String path, String body, {required String prefer}) =>
      _send(path, post: body, prefer: prefer, verb: 'save');

  /// Calls the edge function `name` with a JSON `body`; returns its answer.
  Future<String> function(String name, String body) => _send(name, post: body, verb: 'run', base: 'functions/v1');

  /// Deletes the rows `path` (a PostgREST filter) matches.
  Future<void> delete(String path) => _send(path, verb: 'delete', delete: true);

  Future<String> _send(
    String path, {
    String? post,
    String? prefer,
    required String verb,
    bool delete = false,
    String base = 'rest/v1',
  }) async {
    final what = path.split('?').first;
    final token = await _session.token();
    var (code, body) = await _call(base, path, token, what, post, prefer, delete);
    if (code == 401) {
      // Expired or revoked: one retry with a fresh token.
      await _session.invalidate(token);
      (code, body) = await _call(base, path, await _session.token(), what, post, prefer, delete);
    }
    if (code < 200 || code > 299) throw ApiException('Could not $verb $what (HTTP $code)');
    return body;
  }

  Future<(int, String)> _call(
    String base,
    String path,
    String token,
    String what,
    String? post,
    String? prefer,
    bool delete,
  ) async {
    final uri = Uri.parse('$url/$base/$path');
    final headers = {'apikey': key, 'Authorization': 'Bearer $token', 'Prefer': ?prefer};
    try {
      final response = await (delete
              ? _http.delete(uri, headers: headers)
              : post == null
              ? _http.get(uri, headers: headers)
              : _http.post(uri, headers: {...headers, 'Content-Type': 'application/json'}, body: post))
          .timeout(callTimeout);
      return (response.statusCode, response.body);
    } on Exception {
      throw ApiException('No connection to the server ($what)');
    }
  }
}
