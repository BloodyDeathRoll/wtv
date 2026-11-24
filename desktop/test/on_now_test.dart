import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/epg.dart';
import 'package:wtv/data/on_now.dart';
import 'package:wtv/data/provider_login.dart';

void main() {
  const news = Programme('News', null, 1000, 2000);
  const film = Programme('Film', null, 2000, 5000);

  test('picks the programme running now', () {
    expect(onAt([news, film], 1500), news);
    // At the change-over the new programme is on.
    expect(onAt([news, film], 2000), film);
  });

  test('nothing before the first or after the last', () {
    expect(onAt([news, film], 999), isNull);
    expect(onAt([news, film], 5000), isNull);
    expect(onAt([], 1500), isNull);
  });

  // Not in the TV app's tests: the cache, which the port had to write anew.

  test('an answer is kept until its programme ends, no guide for ten minutes, a failed call for one', () async {
    var calls = 0;
    late http.Response answer;
    final client = MockClient((request) async {
      calls++;
      return answer;
    });
    const login = ProviderLogin('tv.example', 'u', 'p');

    answer = http.Response(
      jsonEncode({
        'epg_listings': [
          {'title': 'News', 'start_timestamp': '1000', 'stop_timestamp': '2000'},
        ],
      }),
      200,
    );
    expect(OnNow.cached(71, 1500), (false, null));
    expect((await OnNow.fetch(client, login, 71, 1500))?.title, 'News');
    expect((await OnNow.fetch(client, login, 71, 1999))?.title, 'News');
    expect(calls, 1);
    expect(OnNow.cached(71, 2000), (false, null));

    answer = http.Response('{"epg_listings":[]}', 200);
    expect(await OnNow.fetch(client, login, 72, 1000), isNull);
    expect(OnNow.cached(72, 1599), (true, null));
    expect(OnNow.cached(72, 1600), (false, null));

    answer = http.Response('', 500);
    expect(await OnNow.fetch(client, login, 73, 1000), isNull);
    expect(OnNow.cached(73, 1059), (true, null));
    expect(OnNow.cached(73, 1060), (false, null));
    expect(calls, 3);
  });
}
