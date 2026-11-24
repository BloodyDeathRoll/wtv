import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/google_sign_in.dart';
import 'package:wtv/data/session.dart';

void main() {
  test('reads each Google answer', () {
    expect((pollResult(200, {'id_token': 'abc', 'access_token': 'x'}) as PollToken).idToken, 'abc');
    expect(pollResult(428, {'error': 'authorization_pending'}), isA<PollPending>());
    expect(pollResult(403, {'error': 'slow_down'}), isA<PollSlowDown>());
    expect((pollResult(403, {'error': 'access_denied'}) as PollFailed).reason, 'Sign-in was declined on the phone');
    expect((pollResult(400, {'error': 'expired_token'}) as PollFailed).reason, 'The code expired');
    // A success without an ID token (no openid scope) is a failure, not a token.
    expect((pollResult(200, {'access_token': 'x'}) as PollFailed).reason, 'Google sign-in failed (HTTP 200)');
  });

  // Time moves only when the sign-in waits.
  var clock = DateTime(2026);
  final waits = <int>[];
  GoogleSignIn google(List<http.Response Function()> answers, {String clientId = 'client'}) {
    var next = 0;
    return GoogleSignIn(
      MockClient((request) async {
        expect(request.url.host, 'oauth2.googleapis.com');
        return answers[next++]();
      }),
      clientId: clientId,
      clientSecret: 'secret',
      now: () => clock,
      wait: (time) async {
        waits.add(time.inSeconds);
        clock = clock.add(time);
      },
    );
  }

  http.Response json(int status, Map<String, Object?> body) => http.Response(jsonEncode(body), status);
  http.Response pending() => json(428, {'error': 'authorization_pending'});
  GoogleCode code({int expiresIn = 1800}) => GoogleCode(
    userCode: 'ABCD-EFGH',
    url: 'https://www.google.com/device',
    deviceCode: 'device',
    intervalSeconds: 5,
    expiresAt: clock.add(Duration(seconds: expiresIn)),
  );

  setUp(() {
    clock = DateTime(2026);
    waits.clear();
  });

  test('asks Google for a code to show', () async {
    final started = await google([
      () => json(200, {'user_code': 'ABCD-EFGH', 'verification_url': 'https://www.google.com/device', 'device_code': 'device', 'interval': 5, 'expires_in': 600}),
    ]).start();
    expect(started.userCode, 'ABCD-EFGH');
    expect(started.intervalSeconds, 5);
    expect(started.expiresAt, clock.add(const Duration(minutes: 10)));
    await expectLater(google([() => json(403, {})]).start(), throwsA(isA<ApiException>()));
    await expectLater(
      google([], clientId: '').start(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('GOOGLE_TV_CLIENT_ID'))),
    );
  });

  test('waits for the phone, slower when Google asks', () async {
    final sign = google([pending, () => json(403, {'error': 'slow_down'}), () => json(200, {'id_token': 'abc'})]);
    expect(await sign.awaitIdToken(code(), cancelled: () => false), 'abc');
    expect(waits, [5, 5, 10]);
  });

  test('a short network drop does not end the sign-in; a long one does', () async {
    http.Response offline() => throw http.ClientException('offline');
    final sign = google([offline, offline, () => json(200, {'id_token': 'abc'})]);
    expect(await sign.awaitIdToken(code(), cancelled: () => false), 'abc');
    await expectLater(
      google(List.filled(6, offline)).awaitIdToken(code(), cancelled: () => false),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'No connection to Google')),
    );
  });

  test('a Google server error does not end the sign-in; six in a row do', () async {
    http.Response errorPage() => http.Response('<html>Service unavailable</html>', 503);
    final sign = google([errorPage, () => json(500, {'error': 'internal_failure'}), () => json(200, {'id_token': 'abc'})]);
    expect(await sign.awaitIdToken(code(), cancelled: () => false), 'abc');
    await expectLater(
      google(List.filled(6, errorPage)).awaitIdToken(code(), cancelled: () => false),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Google sign-in failed (HTTP 503)')),
    );
    // An error Google names is final at once.
    await expectLater(
      google([() => json(400, {'error': 'invalid_grant'})]).awaitIdToken(code(), cancelled: () => false),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Google sign-in failed (invalid_grant)')),
    );
  });

  test('declined, expired and cancelled', () async {
    await expectLater(
      google([() => json(403, {'error': 'access_denied'})]).awaitIdToken(code(), cancelled: () => false),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Sign-in was declined on the phone')),
    );
    await expectLater(
      google([pending, pending]).awaitIdToken(code(expiresIn: 10), cancelled: () => false),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'The code expired')),
    );
    // Cancelled while waiting: no further call to Google.
    expect(await google([]).awaitIdToken(code(), cancelled: () => true), isNull);
  });
}
