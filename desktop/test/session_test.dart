import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/session.dart';

/// A keyring that cannot be read.
class _Broken extends FlutterSecureStorage {
  const _Broken();

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) =>
      throw Exception('locked');
}

void main() {
  const now = 1000000;
  final calls = <http.Request>[];
  // What the server answers, by the request's path and query.
  late Map<String, http.Response Function(http.Request)> server;

  String answer(String access, String refresh, {String email = '', int expiresAt = now + 3600}) => jsonEncode({
    'access_token': access,
    'refresh_token': refresh,
    'expires_at': expiresAt,
    'user': {'email': email},
  });

  Session session({int at = now, FlutterSecureStorage storage = const FlutterSecureStorage()}) => Session(
    MockClient((request) async {
      calls.add(request);
      final path = request.url.toString().replaceFirst('https://db.test/', '');
      final respond = server[path];
      if (respond == null) fail('unexpected call: $path');
      return respond(request);
    }),
    url: 'https://db.test',
    key: 'public-key',
    storage: storage,
    now: () => DateTime.fromMillisecondsSinceEpoch(at * 1000),
  );

  List<String> paths() => [for (final c in calls) c.url.toString().replaceFirst('https://db.test/', '')];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    calls.clear();
    server = {'auth/v1/signup': (_) => http.Response(answer('a1', 'r1'), 200)};
  });

  test('reads which auth answers are a rejection, and when a token is fresh', () {
    for (final code in [400, 401, 403, 404, 422]) {
      expect(isRejection(code), isTrue, reason: '$code');
    }
    for (final code in [408, 429, 500, 502, 503]) {
      expect(isRejection(code), isFalse, reason: '$code');
    }
    expect(isFresh(1000, 939), isTrue);
    expect(isFresh(1000, 940), isFalse);
    expect(isFresh(0, 1), isFalse);
  });

  test('the first token makes an anonymous user, once, and keeps it for the next start', () async {
    final first = session();
    expect(await Future.wait([first.token(), first.token()]), ['a1', 'a1']);
    expect(await first.token(), 'a1');
    expect(paths(), ['auth/v1/signup']);
    expect(calls.single.headers['apikey'], 'public-key');
    expect(first.email, isNull);
    // A new start reads the keyring and asks the server nothing.
    expect(await session().token(), 'a1');
    expect(paths(), ['auth/v1/signup']);
  });

  test('an expired token is refreshed, not replaced by a new user', () async {
    await session().token();
    server = {'auth/v1/token?grant_type=refresh_token': (_) => http.Response(answer('a2', 'r2', expiresAt: now + 9000), 200)};
    expect(await session(at: now + 3600).token(), 'a2');
    expect(jsonDecode(calls.last.body), {'refresh_token': 'r1'});
  });

  test('a rejected refresh token makes a new user; passing trouble does not', () async {
    await session().token();
    for (final trouble in [http.Response('', 500), http.Response('', 429)]) {
      server = {'auth/v1/token?grant_type=refresh_token': (_) => trouble};
      await expectLater(session(at: now + 3600).token(), throwsA(isA<ApiException>()));
    }
    server = {'auth/v1/token?grant_type=refresh_token': (_) => throw http.ClientException('offline')};
    await expectLater(
      session(at: now + 3600).token(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'No connection to the server')),
    );
    expect(paths().where((p) => p == 'auth/v1/signup'), hasLength(1));
    server = {
      'auth/v1/token?grant_type=refresh_token': (_) => http.Response('{"error_code":"refresh_token_not_found"}', 400),
      'auth/v1/signup': (_) => http.Response(answer('b1', 's1', expiresAt: now + 9000), 200),
    };
    expect(await session(at: now + 3600).token(), 'b1');
  });

  test('a keyring that cannot be read is an error, not a new user', () async {
    await expectLater(
      session(storage: const _Broken()).token(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'The system keyring could not be read')),
    );
    expect(calls, isEmpty);
  });

  test('a build without the database settings says so', () async {
    final unset = Session(MockClient((_) async => fail('no call expected')), url: '', key: '');
    await expectLater(unset.token(), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('SUPABASE_URL'))));
  });

  test('Google sign-in turns the anonymous user into the Google user', () async {
    final s = session();
    await s.token();
    server = {'auth/v1/token?grant_type=id_token': (_) => http.Response(answer('g1', 'gr1', email: 'me@example.com'), 200)};
    expect(await s.signInWithGoogle('id-token', link: true), 'g1');
    expect(calls.last.headers['Authorization'], 'Bearer a1');
    expect(jsonDecode(calls.last.body), {'provider': 'google', 'id_token': 'id-token', 'link_identity': true});
    expect(s.email, 'me@example.com');
    // Kept for the next start.
    final next = session();
    await next.load();
    expect(next.email, 'me@example.com');
  });

  test('a Google account already in use is signed in to, and the anonymous data moves into it', () async {
    final s = session();
    await s.token();
    server = {
      'auth/v1/token?grant_type=id_token': (request) => request.headers.containsKey('Authorization')
          ? http.Response('{"error_code":"identity_already_exists"}', 422)
          : http.Response(answer('g1', 'gr1', email: 'me@example.com'), 200),
      'rest/v1/rpc/create_merge_ticket': (_) => http.Response('"ticket-1"', 200),
      'rest/v1/rpc/redeem_merge_ticket': (_) => http.Response('', 204),
    };
    expect(await s.signInWithGoogle('id-token', link: true), 'g1');
    expect(paths().skip(1), [
      'auth/v1/token?grant_type=id_token',
      'rest/v1/rpc/create_merge_ticket',
      'auth/v1/token?grant_type=id_token',
      'rest/v1/rpc/redeem_merge_ticket',
    ]);
    // The ticket is made as the anonymous user and redeemed as the Google user.
    expect(calls[2].headers['Authorization'], 'Bearer a1');
    expect(calls[4].headers['Authorization'], 'Bearer g1');
    expect(jsonDecode(calls[4].body), {'p_ticket': 'ticket-1'});
    expect(s.email, 'me@example.com');
  });

  test('another refusal of the Google sign-in is an error and keeps the anonymous user', () async {
    final s = session();
    await s.token();
    server = {'auth/v1/token?grant_type=id_token': (_) => http.Response('{"error_code":"bad_jwt"}', 400)};
    await expectLater(s.signInWithGoogle('id-token', link: true), throwsA(isA<ApiException>()));
    expect(await s.token(), 'a1');
  });

  test('sign-out forgets the session at once and ends it on the server', () async {
    final s = session();
    await s.token();
    server = {'auth/v1/logout?scope=local': (_) => http.Response('', 204)};
    await s.signOut();
    await pumpEventQueue();
    expect(calls.last.headers['Authorization'], 'Bearer a1');
    expect(await const FlutterSecureStorage().read(key: 'session'), isNull);
    // The next use starts again as a new anonymous user.
    server = {'auth/v1/signup': (_) => http.Response(answer('n1', 'nr1'), 200)};
    expect(await s.token(), 'n1');
  });

  test('a refused token is forgotten, unless a newer one is already stored', () async {
    final s = session();
    await s.token();
    await s.invalidate('some-older-token');
    expect(await s.token(), 'a1');
    await s.invalidate('a1');
    server = {'auth/v1/token?grant_type=refresh_token': (_) => http.Response(answer('a2', 'r2'), 200)};
    expect(await s.token(), 'a2');
  });
}
