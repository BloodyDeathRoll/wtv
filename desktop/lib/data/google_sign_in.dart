import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart' as config;
import 'session.dart';

/// The code Google gives to show, and what is needed to wait for its approval.
class GoogleCode {
  const GoogleCode({
    required this.userCode,
    required this.url,
    required this.deviceCode,
    required this.intervalSeconds,
    required this.expiresAt,
  });

  final String userCode;
  final String url;
  final String deviceCode;
  final int intervalSeconds;
  final DateTime expiresAt;
}

/// Google sign-in by a code (OAuth device flow, a port of the TV app's
/// `data/GoogleSignIn.kt`, with the TV's client): the app shows a code, the
/// user enters it on a phone at google.com/device, and the app receives an ID
/// token. Only name and email are asked for.
class GoogleSignIn {
  GoogleSignIn(
    this._http, {
    this.clientId = config.googleClientId,
    this.clientSecret = config.googleClientSecret,
    this._now = DateTime.now,
    this._wait = _delay,
  });

  final http.Client _http;
  final String clientId;
  final String clientSecret;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  /// Asks Google for a code to show.
  Future<GoogleCode> start() async {
    if (clientId.trim().isEmpty) {
      throw ApiException('This build has no Google sign-in settings (GOOGLE_TV_CLIENT_ID in desktop/.env)');
    }
    final (status, json) = await _post('device/code', {'client_id': clientId, 'scope': 'openid email profile'});
    if (status < 200 || status > 299) throw ApiException('Google sign-in could not start (HTTP $status)');
    int number(String key, int fallback) => json[key] is int ? json[key]! as int : fallback;
    return GoogleCode(
      userCode: json['user_code'] as String? ?? '',
      url: json['verification_url'] as String? ?? '',
      deviceCode: json['device_code'] as String? ?? '',
      intervalSeconds: number('interval', 5).clamp(1, 1 << 31),
      expiresAt: _now().add(Duration(seconds: number('expires_in', 1800))),
    );
  }

  /// Waits until the user approves on the phone and returns the ID token.
  /// Throws when declined or expired. Returns null once `cancelled` says so.
  Future<String?> awaitIdToken(GoogleCode code, {required bool Function() cancelled}) async {
    var interval = code.intervalSeconds;
    var offline = 0;
    while (_now().isBefore(code.expiresAt)) {
      await _wait(Duration(seconds: interval));
      if (cancelled()) return null;
      // The user may take minutes on the phone: a short network drop must not end the sign-in.
      final int status;
      final Map<String, Object?> json;
      try {
        (status, json) = await _post('token', {
          'client_id': clientId,
          'client_secret': clientSecret,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        });
        offline = 0;
      } on ApiException {
        if (++offline >= 6) rethrow;
        continue;
      }
      switch (pollResult(status, json)) {
        case PollToken(:final idToken):
          return idToken;
        case PollPending():
          break;
        case PollSlowDown():
          interval += 5;
        case PollFailed(:final reason):
          throw ApiException(reason);
      }
    }
    throw ApiException('The code expired');
  }

  Future<(int, Map<String, Object?>)> _post(String path, Map<String, String> form) async {
    try {
      final response = await _http.post(Uri.parse('https://oauth2.googleapis.com/$path'), body: form).timeout(callTimeout);
      Object? json;
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        json = null;
      }
      return (response.statusCode, json is Map<String, Object?> ? json : <String, Object?>{});
    } on Exception {
      throw ApiException('No connection to Google');
    }
  }
}

Future<void> _delay(Duration time) => Future.delayed(time);

sealed class Poll {
  const Poll();
}

class PollToken extends Poll {
  const PollToken(this.idToken);

  final String idToken;
}

class PollPending extends Poll {
  const PollPending();
}

class PollSlowDown extends Poll {
  const PollSlowDown();
}

class PollFailed extends Poll {
  const PollFailed(this.reason);

  final String reason;
}

/// Reads one answer of Google's token endpoint while the user is on the phone.
Poll pollResult(int status, Map<String, Object?> json) {
  final idToken = json['id_token'];
  if (status >= 200 && status <= 299 && idToken is String && idToken.isNotEmpty) return PollToken(idToken);
  final error = json['error'] is String ? json['error']! as String : '';
  return switch (error) {
    'authorization_pending' => const PollPending(),
    'slow_down' => const PollSlowDown(),
    'access_denied' => const PollFailed('Sign-in was declined on the phone'),
    'expired_token' => const PollFailed('The code expired'),
    _ => PollFailed('Google sign-in failed (${error.isEmpty ? 'HTTP $status' : error})'),
  };
}
