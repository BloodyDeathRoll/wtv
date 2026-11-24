import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wtv/app_language.dart';
import 'package:wtv/data/google_sign_in.dart';
import 'package:wtv/data/session.dart';
import 'package:wtv/main.dart';
import 'package:wtv/services.dart';
import 'package:wtv/ui/theme.dart';

/// Every call the app made to the server and to Google, as "host/path?query".
final calls = <String>[];

/// What Google's token endpoint answers while the code is on screen; the last answer repeats.
var googleAnswers = <Map<String, Object?>>[];

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status);

/// Starts the app in English on the TV's screen size, with an empty keyring and
/// settings file, a server that signs anyone in, and Google's answers from [googleAnswers].
Future<void> startApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  appLanguage.value = AppLanguage.english;
  calls.clear();
  googleAnswers = [
    {'error': 'authorization_pending'},
  ];
  final client = MockClient((request) async {
    final path = '${request.url.host}${request.url.path}';
    calls.add(request.url.hasQuery ? '$path?${request.url.query}' : path);
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
  services = Services(
    session: Session(client, url: 'https://db.test', key: 'public-key'),
    google: GoogleSignIn(client, clientId: 'client', clientSecret: 'secret'),
  );
  // The TV's screen, so positions here are the design's.
  tester.view.physicalSize = DesignScale.screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const WtvApp());
  await tester.pump();
}
