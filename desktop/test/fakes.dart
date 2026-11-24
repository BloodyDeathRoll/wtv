import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wtv/app_language.dart';
import 'package:wtv/data/api.dart';
import 'package:wtv/data/catalog.dart';
import 'package:wtv/data/google_sign_in.dart';
import 'package:wtv/data/session.dart';
import 'package:wtv/main.dart';
import 'package:wtv/services.dart';
import 'package:wtv/ui/browse/browse_screen.dart';
import 'package:wtv/ui/theme.dart';

/// Every call the app made to the server and to Google, as "host/path?query".
final calls = <String>[];

/// What the screens read by themselves: the anonymous start ("auth/v1/signup"),
/// then each database read as "path?query" (what follows "rest/v1/").
final reads = <String>[];

/// Answers a database read with its rows, or with a whole response (a failure).
typedef Rest = Object? Function(String read);

/// What Google's token endpoint answers while the code is on screen; the last answer repeats.
var googleAnswers = <Map<String, Object?>>[];

// As the server sends it: UTF-8 (Hebrew names), and said so.
http.Response _json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// Starts the app in English on the TV's screen size, with an empty keyring and
/// settings file, a server that signs anyone in, and Google's answers from [googleAnswers].
/// The database is empty unless `rest` answers its reads.
Future<void> startApp(WidgetTester tester, {Rest? rest}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  appLanguage.value = AppLanguage.english;
  calls.clear();
  reads.clear();
  forgetBrowseRows();
  googleAnswers = [
    {'error': 'authorization_pending'},
  ];
  final client = MockClient((request) async {
    final path = '${request.url.host}${request.url.path}';
    final call = request.url.hasQuery ? '$path?${request.url.query}' : path;
    if (path == 'db.test/auth/v1/signup') {
      reads.add('auth/v1/signup');
      return _json({
        'access_token': 'anonymous',
        'refresh_token': 'anonymous-refresh',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {'email': ''},
      });
    }
    if (path.startsWith('db.test/rest/v1/')) {
      final read = call.substring('db.test/rest/v1/'.length);
      reads.add(read);
      final answer = rest == null ? const <Object?>[] : rest(read);
      return answer is http.Response ? answer : _json(answer);
    }
    calls.add(call);
    return switch (path) {
      'oauth2.googleapis.com/device/code' => _json({
        'user_code': 'ABCD-EFGH',
        'verification_url': 'https://www.google.com/device',
        'device_code': 'device',
        'interval': 5,
        'expires_in': 1800,
      }),
      'oauth2.googleapis.com/token' => () {
        final answer = googleAnswers.length > 1 ? googleAnswers.removeAt(0) : googleAnswers.first;
        return _json(answer, answer.containsKey('id_token') ? 200 : 428);
      }(),
      'db.test/auth/v1/token' => _json({
        'access_token': 'access',
        'refresh_token': 'refresh',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {'email': 'me@example.com'},
      }),
      'db.test/auth/v1/logout' => http.Response('', 204),
      _ => fail('unexpected call: $path'),
    };
  });
  final session = Session(client, url: 'https://db.test', key: 'public-key');
  services = Services(
    session: session,
    google: GoogleSignIn(client, clientId: 'client', clientSecret: 'secret'),
    catalog: Catalog(Api(session, client, url: 'https://db.test', key: 'public-key')),
  );
  // The TV's screen, so positions here are the design's.
  tester.view.physicalSize = DesignScale.screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const WtvApp());
  await tester.pump();
}
