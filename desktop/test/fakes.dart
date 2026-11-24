import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wtv/app_language.dart';
import 'package:wtv/data/api.dart';
import 'package:wtv/data/catalog.dart';
import 'package:wtv/data/google_sign_in.dart';
import 'package:wtv/data/provider_login.dart';
import 'package:wtv/data/session.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/main.dart';
import 'package:wtv/player/engine.dart';
import 'package:wtv/services.dart';
import 'package:wtv/ui/browse/browse_screen.dart';
import 'package:wtv/ui/theme.dart';

/// Every call the app made to the server and to Google, as "host/path?query".
final calls = <String>[];

/// What the screens read by themselves: the anonymous start ("auth/v1/signup"),
/// then each database read as "path?query" (what follows "rest/v1/").
final reads = <String>[];

/// Each database write, as "POST path?query body" or "DELETE path?query".
final writes = <String>[];

/// Answers a database read with its rows, or with a whole response (a failure).
/// A write is asked as "POST path?query" or "DELETE path?query": it succeeds unless the answer is a response.
typedef Rest = Object? Function(String read);

/// The video engine of the tests: it records what it was asked, and plays what the test says.
class FakeEngine extends VideoEngine {
  /// Each stream opened, as (address, second to start at), and the numbers of those closed.
  final opened = <(String, int)>[];
  final closed = <int>[];
  final seeks = <Duration>[];

  /// The number of the stream open now; null for none.
  int? stream;

  @override
  Duration position = Duration.zero;
  @override
  Duration? length;
  @override
  bool paused = false;
  @override
  bool started = false;
  @override
  bool buffering = false;
  @override
  bool ended = false;
  @override
  String? failure;
  @override
  List<MediaTrack> audioTracks = const [];
  @override
  List<MediaTrack> subtitleTracks = const [];
  @override
  String? audioTrack;
  @override
  String? subtitleTrack;
  @override
  double speed = 1;

  /// What the stream does next; the screens are told.
  void now(void Function(FakeEngine e) change) {
    change(this);
    notifyListeners();
  }

  /// The stream opens and plays: `length` long, now at `at`.
  void plays({required Duration length, Duration? at}) => now((e) {
    e.started = true;
    e.length = length;
    if (at != null) e.position = at;
  });

  @override
  int open(String url, {int startSecs = 0}) {
    opened.add((url, startSecs));
    position = Duration(seconds: startSecs);
    length = null;
    paused = started = buffering = ended = false;
    failure = null;
    audioTracks = subtitleTracks = const [];
    audioTrack = subtitleTrack = null;
    speed = 1;
    return stream = opened.length;
  }

  @override
  void close(int stream) {
    closed.add(stream);
    // As the real one: a stream that was replaced is closed already.
    if (stream == this.stream) this.stream = null;
  }

  @override
  void play() => now((e) => e.paused = false);

  @override
  void pause() => now((e) => e.paused = true);

  @override
  void seek(Duration to) => now((e) {
    e.seeks.add(to);
    e.position = to;
  });

  @override
  void setSpeed(double speed) => now((e) => e.speed = speed);

  @override
  void setAudioTrack(String id) => now((e) => e.audioTrack = id);

  @override
  void setSubtitleTrack(String? id) => now((e) => e.subtitleTrack = id);

  @override
  Widget view() => const SizedBox.expand();
}

/// The engine of the test now running.
var engine = FakeEngine();

/// What Google's token endpoint answers while the code is on screen; the last answer repeats.
var googleAnswers = <Map<String, Object?>>[];

// As the server sends it: UTF-8 (Hebrew names), and said so.
http.Response _json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// The app's services in English, with an empty keyring and settings file, a server
/// that signs anyone in, and Google's answers from [googleAnswers]. The database is
/// empty unless `rest` answers its reads.
void fakeServices({Rest? rest}) {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  appLanguage.value = AppLanguage.english;
  calls.clear();
  reads.clear();
  writes.clear();
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
      if (request.method != 'GET') {
        final write = '${request.method} $read';
        writes.add(request.body.isEmpty ? write : '$write ${request.body}');
        final answer = rest?.call(write);
        return answer is http.Response ? answer : http.Response('', 201);
      }
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
      // WTW's own sign-in, with the same Google account.
      'wtw.test/auth/v1/token' => _json({
        'access_token': 'wtw-access',
        'refresh_token': 'wtw-refresh',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {'email': 'me@example.com'},
      }),
      'wtw.test/auth/v1/logout' => http.Response('', 204),
      _ => fail('unexpected call: $path'),
    };
  });
  final session = Session(client, url: 'https://db.test', key: 'public-key');
  engine = FakeEngine();
  services = Services(
    engine: () => engine,
    session: session,
    wtw: Session(client, name: 'wtw_session', url: 'https://wtw.test', key: 'wtw-key', anonymous: false),
    provider: ProviderLoginStore(),
    google: GoogleSignIn(client, clientId: 'client', clientSecret: 'secret'),
    catalog: Catalog(Api(session, client, url: 'https://db.test', key: 'public-key')),
  );
}

// The TV's screen, so positions here are the design's.
void _tvScreen(WidgetTester tester) {
  tester.view.physicalSize = DesignScale.screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Starts the app over [fakeServices], on the TV's screen size.
Future<void> startApp(WidgetTester tester, {Rest? rest}) async {
  fakeServices(rest: rest);
  _tvScreen(tester);
  await tester.pumpWidget(const WtvApp());
  await tester.pump();
}

/// Shows one screen by itself over [fakeServices], on the TV's screen size.
Future<void> showScreen(WidgetTester tester, Widget screen, {Rest? rest}) async {
  fakeServices(rest: rest);
  _tvScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: wtvTheme,
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(color: WtvColors.background, child: screen),
    ),
  );
  await tester.pump();
}
