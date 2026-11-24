import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/api.dart';
import 'package:wtv/data/catalog.dart';
import 'package:wtv/data/json.dart';
import 'package:wtv/data/session.dart';
import 'package:wtv/data/wtw_scores.dart';

void main() {
  // What was asked of the server's wtw-scores function, and how many calls ran at once.
  final asked = <JsonObject>[];
  var running = 0, most = 0;
  // The server answers only once this is done.
  late Completer<void> release;
  late http.Response Function(JsonObject body) answer;
  late Catalog catalog;
  late Session wtw;
  late WtwScores scores;

  // WTW scores the even cards with their own id, and not the odd ones.
  http.Response scored(JsonObject body) => http.Response(
    jsonEncode({
      'scores': {for (final id in body['title_ids']! as List) '$id': (id as int).isEven ? id : null},
    }),
    200,
  );

  setUp(() async {
    final soon = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String session(String access, [String? email]) =>
        jsonEncode({'access_token': access, 'refresh_token': 'r', 'expires_at': soon, 'email': email});
    FlutterSecureStorage.setMockInitialValues({'session': session('a1'), 'wtw': session('w1', 'me@example.com')});
    asked.clear();
    running = most = 0;
    release = Completer();
    answer = scored;
    final client = MockClient((request) async {
      // Signing in to WTW with another Google account.
      if (request.url.host == 'wtw.test') {
        return http.Response(
          jsonEncode({'access_token': 'w2', 'refresh_token': 'r', 'expires_at': soon, 'user': {'email': 'other@example.com'}}),
          200,
        );
      }
      expect(request.url.toString(), 'https://db.test/functions/v1/wtw-scores');
      final body = jsonDecode(request.body) as JsonObject;
      asked.add(body);
      most = max(most, ++running);
      await release.future;
      running--;
      return answer(body);
    });
    catalog = Catalog(Api(Session(client, url: 'https://db.test', key: 'public-key'), client, url: 'https://db.test', key: 'public-key'));
    wtw = Session(client, name: 'wtw', url: 'https://wtw.test', key: 'wtw-key', anonymous: false);
    await wtw.load();
    scores = WtwScores(catalog, wtw);
  });

  test('asks six cards a call, two calls at once, each card once; listeners hear of the answers', () async {
    var told = 0;
    scores.addListener(() => told++);
    scores.request([for (var id = 1; id <= 15; id++) id]);
    scores.request([3, 4, 16]);
    await pumpEventQueue();
    expect(running, 2);
    expect(scores[2], isNull);
    release.complete();
    await pumpEventQueue();
    expect([for (final body in asked) body['title_ids']], [
      [1, 2, 3, 4, 5, 6],
      [7, 8, 9, 10, 11, 12],
      [13, 14, 15],
      [16],
    ]);
    expect(asked.first['wtw_token'], 'w1');
    expect(most, 2);
    expect((scores[2], scores[3], scores[16], scores[99]), (2, null, 16, null));
    expect(told, 4);
  });

  test('a call that fails leaves its cards to be asked again', () async {
    release.complete();
    answer = (_) => http.Response('', 500);
    scores.request([2]);
    await pumpEventQueue();
    expect(scores[2], isNull);
    answer = scored;
    scores.request([2]);
    await pumpEventQueue();
    expect(scores[2], 2);
    expect(asked, hasLength(2));
  });

  test("nothing is asked without WTW, and another account's answers are dropped", () async {
    release.complete();
    final notConnected = Session(MockClient((_) async => fail('no call expected')), name: 'none', anonymous: false);
    WtwScores(catalog, notConnected).request([2]);
    await pumpEventQueue();
    expect(asked, isEmpty);

    scores.request([2]);
    await pumpEventQueue();
    expect(scores[2], 2);
    await wtw.signInWithGoogle('id-token', link: false);
    expect(wtw.email, 'other@example.com');
    var told = 0;
    scores.addListener(() => told++);
    scores.request([]);
    expect((scores[2], told), (null, 1));
    scores.request([2]);
    await pumpEventQueue();
    expect((asked.last['wtw_token'], scores[2]), ('w2', 2));
  });
}
