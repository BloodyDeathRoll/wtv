import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/epg.dart';
import 'package:wtv/data/json.dart';
import 'package:wtv/data/provider_login.dart';
import 'package:wtv/data/session.dart';

String b64(String s) => base64.encode(utf8.encode(s));

JsonObject listing(String title, int start, int end, [String? description]) => {
  'title': title,
  'description': description ?? '',
  'start_timestamp': '$start',
  'stop_timestamp': '$end',
};

String guide(List<JsonObject> listings) => jsonEncode({'epg_listings': listings});

void main() {
  test('titles are decoded from base64, plain text kept, bad rows skipped, sorted by start', () {
    final list = programmes(
      guide([
        listing(b64('מבזק חדשות'), 200, 300, b64('עדכון')),
        listing('News', 100, 200),
        {'title': b64('no times')},
        listing('', 300, 400),
      ]),
    );
    expect([for (final p in list) p.title], ['News', 'מבזק חדשות']);
    expect(list[1].description, 'עדכון');
    expect(list[0].description, isNull);
    expect(list[0].start, 100);
  });

  test('no guide or a broken answer gives nothing', () {
    expect(programmes('{"epg_listings":[]}'), isEmpty);
    expect(programmes('[]'), isEmpty);
    expect(programmes('not json'), isEmpty);
  });

  test('now and next, also between programmes and after the last', () {
    const a = Programme('A', null, 100, 200);
    const b = Programme('B', null, 200, 300);
    const c = Programme('C', null, 400, 500);
    const list = [a, b, c];
    expect(nowAndNext(list, 150), (a, b));
    expect(nowAndNext(list, 200), (b, c));
    expect(nowAndNext(list, 350), (null, c));
    expect(nowAndNext(list, 600), (null, null));
  });

  test('plain titles that look like base64 are kept, and empty programmes dropped', () {
    final json = guide([
      listing('AAAA', 100, 200), // decodes to control characters
      listing('abc', 200, 300), // unpadded
      listing(b64('x'), 300, 300), // no length
    ]);
    expect([for (final p in programmes(json)) p.title], ['AAAA', 'abc']);
  });

  test('the server address gets https when it has no scheme, and loses a trailing slash', () {
    expect(serverBase(const ProviderLogin('tv.example:8080/', 'u', 'p')), 'https://tv.example:8080');
    expect(serverBase(const ProviderLogin(' http://tv.example ', 'u', 'p')), 'http://tv.example');
  });

  test("archive flags and the provider's start text are read", () {
    final json = guide([
      {...listing(b64('יום'), 1794985800, 1794987600), 'has_archive': '1', 'start': '2026-11-18 07:10:00'},
      {...listing(b64('עכשיו'), 1794987600, 1794990000), 'has_archive': '0', 'start': '2026-11-18 07:40:00'},
    ]);
    final [archived, live] = programmes(json);
    expect(archived.archived, isTrue);
    expect(archived.providerStart, '2026-11-18 07:10:00');
    expect(live.archived, isFalse);
  });

  test("the catch-up address uses the provider's start text and whole minutes", () {
    const login = ProviderLogin('http://tv.example:80/', 'u ser', 'p/w');
    Programme p(String? providerStart) => Programme('x', null, 1794985800, 1794987600 + 30, providerStart: providerStart);
    expect(timeshiftUrl(login, 42, p('2026-11-18 07:10:00')), 'http://tv.example:80/timeshift/u%20ser/p%2Fw/31/2026-11-18:07-10/42.ts');
    expect(timeshiftUrl(login, 42, p(null)), isNull);
    expect(timeshiftUrl(login, 42, p('yesterday')), isNull);
  });

  test('playable - archived, over, with a usable start, one per start, newest first', () {
    Programme p(int start, {bool archived = true, String? text = '2026-11-18 07:10:00'}) =>
        Programme('p$start', null, start, start + 100, archived: archived, providerStart: text);
    final list = [p(100), p(300), p(300), p(500), p(200, archived: false), p(400, text: 'soon'), p(1000)];
    expect([for (final p in playable(list, 1000)) p.start], [500, 300, 100]);
  });

  test('guide leads with what is on, then what is still to come, one per start', () {
    Programme p(int start) => Programme('p$start', null, start, start + 100);
    final list = [p(100), p(200), p(300), p(300), p(400)];
    final (lead, after) = guideOf(list, null, 250);
    expect(lead?.start, 200);
    expect([for (final p in after) p.start], [300, 400]);
  });

  test('in catch-up the guide leads with the programme playing and lists only what has not aired', () {
    Programme p(int start) => Programme('p$start', null, start, start + 100);
    final list = [p(100), p(200), p(300), p(400)];
    final (lead, after) = guideOf(list, p(100), 350);
    expect(lead?.start, 100);
    expect([for (final p in after) p.start], [400]);
  });

  // Not in the TV app's tests: the calls, which the port had to write anew.

  test('the guide is asked with the login, the action and the channel; an error never holds the login', () async {
    final urls = <String>[];
    late http.Response Function(http.Request) answer;
    final client = MockClient((request) async {
      urls.add(request.url.toString());
      return answer(request);
    });
    const login = ProviderLogin('tv.example:8080/', ' u ser ', 'p/w&x');
    const asked = 'https://tv.example:8080/player_api.php?username=u+ser&password=p%2Fw%26x';

    // Plain text in UTF-8, from a server that names no charset.
    answer = (_) => http.Response.bytes(utf8.encode(guide([listing('חדשות ערב', 100, 200)])), 200);
    expect((await shortEpg(client, login, 42)).single.title, 'חדשות ערב');
    expect(urls.last, '$asked&action=get_short_epg&stream_id=42&limit=4');

    answer = (_) => http.Response(
      guide([
        {...listing('Old', 100, 200), 'has_archive': '1', 'start': '2026-11-18 07:10:00'},
        {...listing('Live', 200, 300), 'has_archive': '1', 'start': '2026-11-18 07:40:00'},
      ]),
      200,
    );
    expect([for (final p in await archive(client, login, 42, 250)) p.title], ['Old']);
    expect(urls.last, '$asked&action=get_simple_data_table&stream_id=42');

    answer = (_) => http.Response('', 404);
    await expectLater(shortEpg(client, login, 42), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Guide: HTTP 404')));
    answer = (request) => throw http.ClientException('offline', request.url);
    await expectLater(
      shortEpg(client, login, 42),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Guide: no connection')),
    );
  });
}
