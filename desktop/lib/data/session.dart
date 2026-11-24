import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart' as config;

/// A failure with a message for the user.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The auth API refused the request itself (not passing trouble).
class _AuthRejected extends ApiException {
  _AuthRejected(int code, this.errorCode) : super('Sign-in refused (HTTP $code)');

  final String? errorCode;
}

/// No answer within this long counts as no connection.
const callTimeout = Duration(seconds: 20);

/// A signed-in session with one Supabase project (a port of the TV app's
/// `data/Session.kt`). For WTV (`anonymous`) a device starts as an anonymous
/// user, created on first use and kept, and becomes the user's Google account
/// at sign-in. The catalog is readable only with a session.
///
/// The session is kept in the system keyring, not in a plain file.
class Session {
  Session(
    this._http, {
    this.name = 'session',
    this.url = config.supabaseUrl,
    this.key = config.supabaseKey,
    this.anonymous = true,
    this.settingNames = 'SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY',
    this._storage = const FlutterSecureStorage(),
    this._now = DateTime.now,
  });

  final http.Client _http;
  final String name;
  final String url;
  final String key;
  final bool anonymous;

  /// Named in the error when this build lacks the URL or key.
  final String settingNames;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  bool _loaded = false;
  String? _access;
  String? _refresh;
  int _expiresAt = 0;
  String? _email;

  // One sign-in, refresh or sign-out at a time: each waits for the one before.
  Future<void> _last = Future.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _last.then((_) => body());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  int get _nowSeconds => _now().millisecondsSinceEpoch ~/ 1000;

  /// The Google account's email, or null while not signed in with Google (or before [load]).
  String? get email => _email;

  /// Reads the stored session. Called once at the start, so [email] is known; every other call loads by itself.
  Future<void> load() => _locked(_load);

  /// A keyring that cannot be read is an error, never "no session": a new
  /// anonymous user would leave the user's data behind on the old one.
  Future<void> _load() async {
    if (_loaded) return;
    final String? text;
    try {
      text = await _storage.read(key: name);
    } catch (e) {
      throw ApiException('The system keyring could not be read');
    }
    final stored = text == null ? null : _json(text);
    _access = stored?['access_token'] as String?;
    _refresh = stored?['refresh_token'] as String?;
    _expiresAt = stored?['expires_at'] as int? ?? 0;
    _email = stored?['email'] as String?;
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      if (_refresh == null) {
        await _storage.delete(key: name);
      } else {
        await _storage.write(
          key: name,
          value: jsonEncode({
            'access_token': _access,
            'refresh_token': _refresh,
            'expires_at': _expiresAt,
            'email': _email,
          }),
        );
      }
    } catch (e) {
      // Said, not swallowed: the next start would not find this session.
      throw ApiException('The session could not be saved in the system keyring');
    }
  }

  /// A valid access token (good for at least `minSeconds` more), refreshed or created as needed.
  Future<String> token({int minSeconds = 60}) => _locked(() async {
    requireConfigured(url, key, settingNames);
    await _load();
    final token = _current(minSeconds) ?? await _refreshed();
    if (token != null) return token;
    if (!anonymous) throw ApiException('Not signed in');
    return _auth('signup', {});
  });

  /// Signs in with a Google ID token. With `link`, a device still on its
  /// anonymous user becomes that Google user and keeps its data (favourites,
  /// ratings, positions). When the Google account is already in use on
  /// another device, this device signs in to that account instead and moves
  /// its anonymous data into it.
  Future<String> signInWithGoogle(String idToken, {required bool link}) => _locked(() async {
    requireConfigured(url, key, settingNames);
    await _load();
    Map<String, Object?> body() => {'provider': 'google', 'id_token': idToken};
    final bearer = link && _email == null ? _current() ?? await _refreshed() : null;
    if (bearer != null) {
      try {
        return await _auth('token?grant_type=id_token', {...body(), 'link_identity': true}, bearer: bearer);
      } on _AuthRejected catch (e) {
        if (e.errorCode != 'identity_already_exists') rethrow;
      }
    }
    // Switching to an account used elsewhere: the ticket carries this device's anonymous data across.
    final ticket = bearer == null ? null : await _bestEffort(() => _rpc('create_merge_ticket', {}, bearer));
    final access = await _auth('token?grant_type=id_token', body());
    if (ticket != null) {
      // Best effort: a failure leaves the data on the old anonymous user, as before.
      // The move is one transaction on the server; a timed-out call may still have done it.
      await _bestEffort(() => _rpc('redeem_merge_ticket', {'p_ticket': ticket.replaceAll('"', '')}, access));
    }
    return access;
  });

  /// Forgets the session at once (WTV starts again as a new anonymous user),
  /// then ends it on the server in the background, best effort. Only this
  /// device's session ends: the user stays signed in elsewhere.
  Future<void> signOut() => _locked(() async {
    await _load();
    final stored = _access;
    final fresh = isFresh(_expiresAt, _nowSeconds);
    final refresh = _refresh;
    _access = _refresh = _email = null;
    _expiresAt = 0;
    await _save();
    if (stored == null) return;
    unawaited(
      _bestEffort(() async {
        // The server refuses an expired access token, which would leave the session alive there.
        final token = fresh ? stored : (refresh == null ? null : await _freshToken(refresh));
        if (token == null) return;
        await _post('auth/v1/logout?scope=local', null, bearer: token);
      }),
    );
  });

  /// The server refused `rejected`: forget it, so the next call refreshes. A
  /// token another request has stored meanwhile is kept, so parallel 401s
  /// cause one refresh, not one each.
  Future<void> invalidate(String rejected) => _locked(() async {
    if (_access != rejected) return;
    _access = null;
    await _save();
  });

  String? _current([int minSeconds = 60]) =>
      _access != null && isFresh(_expiresAt, _nowSeconds, minSeconds) ? _access : null;

  /// A new access token from the refresh token, or null when there is none or
  /// the server rejects it (revoked, expired, user gone): only then is a new
  /// user made. A network error is thrown, not treated as a rejection: signing
  /// up again would leave the user's data behind on the old account.
  Future<String?> _refreshed() async {
    final refresh = _refresh;
    if (refresh == null) return null;
    try {
      return await _auth('token?grant_type=refresh_token', {'refresh_token': refresh});
    } on _AuthRejected {
      return null;
    }
  }

  /// A new access token for `refresh`, not stored (for the logout after the device has forgotten it).
  Future<String?> _freshToken(String refresh) async {
    final (_, text) = await _post('auth/v1/token?grant_type=refresh_token', {'refresh_token': refresh});
    final token = _json(text)?['access_token'];
    return token is String && token.isNotEmpty ? token : null;
  }

  Future<String> _rpc(String name, Map<String, Object?> args, String bearer) async {
    final (code, text) = await _post('rest/v1/rpc/$name', args, bearer: bearer);
    if (code < 200 || code > 299) throw ApiException('$name failed (HTTP $code)');
    return text;
  }

  /// Calls the auth API (as `bearer` when given), stores the new session, returns its access token.
  Future<String> _auth(String path, Map<String, Object?> body, {String? bearer}) async {
    final (code, text) = await _post('auth/v1/$path', body, bearer: bearer);
    final answer = _json(text);
    if (isRejection(code)) throw _AuthRejected(code, answer?['error_code'] as String?);
    // Anything else, 429 and 5xx included, is passing trouble: never a reason to make a new user.
    if (code < 200 || code > 299) throw ApiException('Sign-in failed (HTTP $code)');
    final access = answer?['access_token'];
    final refresh = answer?['refresh_token'];
    final expiresAt = answer?['expires_at'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty || expiresAt is! int || expiresAt == 0) {
      throw ApiException('Sign-in answer could not be read');
    }
    // Anonymous users have an empty email.
    final user = answer?['user'];
    final email = user is Map ? user['email'] : null;
    _access = access;
    _refresh = refresh;
    _expiresAt = expiresAt;
    _email = email is String && email.isNotEmpty ? email : null;
    await _save();
    return access;
  }

  /// POSTs JSON to the project; the status and the answer's text.
  Future<(int, String)> _post(String path, Map<String, Object?>? body, {String? bearer}) async {
    try {
      final response = await _http
          .post(
            Uri.parse('$url/$path'),
            headers: {
              'apikey': key,
              'Content-Type': 'application/json',
              if (bearer != null) 'Authorization': 'Bearer $bearer',
            },
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(callTimeout);
      return (response.statusCode, response.body);
    } on Exception {
      throw ApiException('No connection to the server');
    }
  }
}

/// Null on failure.
Future<T?> _bestEffort<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on Exception {
    return null;
  }
}

Map<String, Object?>? _json(String text) {
  try {
    final value = jsonDecode(text);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}

/// The auth answers that mean "this refresh token is no good" (Supabase uses
/// 400 for an invalid one). Anything else, 429 and 5xx included, is passing
/// trouble and never a reason to make a new user.
bool isRejection(int code) => const {400, 401, 403, 404, 422}.contains(code);

/// An access token is used until a minute (or `marginSeconds`) before it expires.
bool isFresh(int expiresAtSeconds, int nowSeconds, [int marginSeconds = 60]) =>
    nowSeconds < expiresAtSeconds - marginSeconds;

/// A build without the database settings fails with a clear message, not a crash.
void requireConfigured(String url, String key, String names) {
  if (url.trim().isEmpty || key.trim().isEmpty) {
    throw ApiException('This build has no database settings ($names in desktop/.env)');
  }
}
