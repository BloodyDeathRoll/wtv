import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/api.dart';
import 'package:wtv/data/session.dart';

void main() {
  // The calls to the REST API and the functions, and what the server answers them, in order.
  final calls = <http.Request>[];
  late List<http.Response Function()> answers;
  late Api api;

  Matcher fails(String message) => throwsA(isA<ApiException>().having((e) => e.message, 'message', message));

  setUp(() {
    final soon = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'session': jsonEncode({'access_token': 'a1', 'refresh_token': 'r1', 'expires_at': soon}),
    });
    calls.clear();
    final client = MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        return http.Response(jsonEncode({'access_token': 'a2', 'refresh_token': 'r2', 'expires_at': soon}), 200);
      }
      calls.add(request);
      return answers.removeAt(0)();
    });
    api = Api(Session(client, url: 'https://db.test', key: 'public-key'), client, url: 'https://db.test', key: 'public-key');
  });

  test('a read sends the key and the token and gives the rows', () async {
    answers = [() => http.Response('[{"id":1}]', 200)];
    expect(await api.get('titles?select=id&limit=10'), [
      {'id': 1},
    ]);
    final call = calls.single;
    expect((call.method, call.url.toString()), ('GET', 'https://db.test/rest/v1/titles?select=id&limit=10'));
    expect((call.headers['apikey'], call.headers['Authorization']), ('public-key', 'Bearer a1'));
    expect(call.headers.containsKey('Prefer'), isFalse);
  });

  test('a refused token is refreshed and the call made once more, not twice', () async {
    answers = [() => http.Response('', 401), () => http.Response('[]', 200)];
    expect(await api.get('titles?select=id'), isEmpty);
    expect([for (final c in calls) c.headers['Authorization']], ['Bearer a1', 'Bearer a2']);
    answers = [() => http.Response('', 401), () => http.Response('', 401)];
    await expectLater(api.get('titles?select=id'), fails('Could not load titles (HTTP 401)'));
    expect(calls, hasLength(4));
  });

  test('a failure says what could not be done', () async {
    answers = [
      () => http.Response('', 500),
      () => http.Response('{"message":"not rows"}', 200),
      () => http.Response('not json', 200),
      () => throw http.ClientException('offline'),
    ];
    await expectLater(api.get('titles?select=id'), fails('Could not load titles (HTTP 500)'));
    await expectLater(api.get('titles?select=id'), fails('Could not read titles'));
    await expectLater(api.get('titles'), fails('Could not read titles'));
    await expectLater(api.get('titles?select=id'), fails('No connection to the server (titles)'));
  });

  test('a write posts the JSON with the Prefer header; a delete and a function call', () async {
    answers = [() => http.Response('', 201), () => http.Response('', 204), () => http.Response('{"fresh":true}', 200)];
    await api.post('ratings?on_conflict=user_id,title_id', '{"title_id":7}', prefer: 'resolution=merge-duplicates,return=minimal');
    expect((calls[0].method, calls[0].url.toString()), ('POST', 'https://db.test/rest/v1/ratings?on_conflict=user_id,title_id'));
    expect((calls[0].body, calls[0].headers['Prefer']), ('{"title_id":7}', 'resolution=merge-duplicates,return=minimal'));
    expect(calls[0].headers['Content-Type'], 'application/json');

    await api.delete('ratings?title_id=eq.7');
    expect((calls[1].method, calls[1].url.toString()), ('DELETE', 'https://db.test/rest/v1/ratings?title_id=eq.7'));

    expect(await api.function('rank', '{"wtw_token":"t"}'), '{"fresh":true}');
    expect((calls[2].method, calls[2].url.toString(), calls[2].body), ('POST', 'https://db.test/functions/v1/rank', '{"wtw_token":"t"}'));

    answers = [() => http.Response('', 409), () => http.Response('', 403), () => http.Response('', 500)];
    await expectLater(api.post('ratings', '{}', prefer: ''), fails('Could not save ratings (HTTP 409)'));
    await expectLater(api.delete('ratings?title_id=eq.7'), fails('Could not delete ratings (HTTP 403)'));
    await expectLater(api.function('rank', '{}'), fails('Could not run rank (HTTP 500)'));
  });
}
