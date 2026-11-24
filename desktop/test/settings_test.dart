import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:wtv/config.dart';
import 'package:wtv/data/provider_login.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/services.dart';
import 'package:wtv/ui/components/chips.dart';
import 'package:wtv/ui/settings/settings_screen.dart';

import 'fakes.dart';

/// A keyring that refuses to store.
class _NoWrite extends FlutterSecureStorage {
  const _NoWrite();

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) =>
      throw Exception('locked');
}

/// Settings: the provider login, Live TV's switch and hidden items, WTW, About.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  // What the database holds; each test sets what it needs.
  var hiddenChannels = <int>[];
  var hiddenGroups = <int>[];
  var failing = <String>[];

  setUp(() {
    hiddenChannels = [];
    hiddenGroups = [];
    failing = [];
  });

  Object? database(String read) {
    if (failing.any(read.startsWith)) return http.Response('', 500);
    if (read.startsWith('channel_prefs?select=channel_id&hidden')) return [for (final id in hiddenChannels) {'channel_id': id}];
    if (read.startsWith('live_group_prefs?')) return [for (final id in hiddenGroups) {'category_id': id}];
    if (read.startsWith('user_settings?')) return const [];
    if (read.startsWith('channels?')) {
      return [
        for (final (id, name) in const [(1, 'Channel one'), (2, 'Channel two')])
          {'id': id, 'ext_id': id, 'name': name, 'num': id, 'logo_url': null, 'archive_days': 0, 'is_radio': false, 'category_ids': const [5]},
      ];
    }
    if (read.startsWith('categories?')) {
      return [
        {'ext_id': 5, 'name': 'News', 'name_en': 'News', 'name_he': null},
      ];
    }
    return const [];
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  /// A click on an item, scrolled into view first.
  Future<void> click(WidgetTester tester, Finder item) async {
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  /// Enter in a text field, as the keyboard sends it.
  Future<void> next(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
  }

  bool focused(WidgetTester tester, Finder item) => Focus.of(tester.element(item)).hasPrimaryFocus;
  T? focusedIn<T extends Widget>() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<T>();
  String? focusedChip() => focusedIn<OptionChip>()?.label;

  /// The text field next to `label`.
  Finder field(String label) => find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first, matching: find.byType(TextField));
  bool inField(WidgetTester tester, String label) => focusedIn<TextField>() == tester.widget<TextField>(field(label));
  Future<String?> keyring() => const FlutterSecureStorage().read(key: 'provider_login');

  testWidgets('Down goes row by row, also to a row whose items lie to the side', (tester) async {
    await startApp(tester, rest: database);
    await openSettings(tester);
    expect(focusedChip(), en.languageEnglish);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.signInGoogle)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedChip(), en.settingOn);
    // No login yet: the provider's fields are open.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(inField(tester, en.providerServer), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
    expect(inField(tester, en.providerPassword), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.save)), isTrue);
    // About takes the focus, so the arrow keys bring it into view.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.aboutTmdb)), isTrue);
    expect(find.text(en.aboutVersion(appVersion)), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    expect(inField(tester, en.providerPassword), isTrue);
  });

  test('About names the version of pubspec.yaml', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('\nversion: $appVersion+'));
  });

  testWidgets('the provider login: all three fields, kept in the keyring, closed behind Edit once saved', (tester) async {
    await startApp(tester, rest: database);
    await openSettings(tester);
    await tester.enterText(field(en.providerServer), ' tv.example.com ');
    // Enter goes on to the next field.
    await next(tester);
    expect(inField(tester, en.providerUser), isTrue);
    await tester.enterText(field(en.providerUser), ' me ');
    await click(tester, find.text(en.save));
    expect(find.text(en.providerIncomplete), findsOneWidget);
    expect(await keyring(), isNull);

    // Typing takes the message away. The password shows as dots.
    await tester.enterText(field(en.providerPassword), ' secret ');
    await tester.pump();
    expect(find.text(en.providerIncomplete), findsNothing);
    expect(tester.widget<TextField>(field(en.providerPassword)).obscureText, isTrue);
    await click(tester, find.text(en.save));

    // Server and user name are trimmed, the password is kept as typed.
    expect(jsonDecode((await keyring())!), {'server': 'tv.example.com', 'user': 'me', 'password': ' secret '});
    expect(services.provider.login!.server, 'tv.example.com');
    expect(find.text(en.saved), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(focused(tester, find.text(en.edit)), isTrue);

    // Edit opens the fields again, on the first one, with what was typed.
    await press(tester, LogicalKeyboardKey.enter);
    expect(inField(tester, en.providerServer), isTrue);
    expect(tester.widget<TextField>(field(en.providerUser)).controller!.text, ' me ');

    // The next time Settings opens the login is behind Edit.
    await press(tester, LogicalKeyboardKey.escape);
    await openSettings(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(en.edit), findsOneWidget);
  });

  test('the login store: a refused keyring saves nothing; a stored value that is no login counts as none', () async {
    FlutterSecureStorage.setMockInitialValues({'provider_login': 'not json'});
    final store = ProviderLoginStore();
    await store.load();
    expect(store.login, isNull);
    expect(await store.save(const ProviderLogin('s', 'u', 'p')), isTrue);
    final again = ProviderLoginStore();
    await again.load();
    expect((again.login!.server, again.login!.user, again.login!.password), ('s', 'u', 'p'));

    final refused = ProviderLoginStore(const _NoWrite());
    expect(await refused.save(const ProviderLogin('s', 'u', 'p')), isFalse);
    expect(refused.login, isNull);
  });

  testWidgets('opened by Play with no login, the page is on the server field', (tester) async {
    final first = FocusNode();
    addTearDown(first.dispose);
    await showScreen(tester, SettingsScreen(firstFocus: first, providerFirst: true), rest: database);
    first.requestFocus();
    await tester.pumpAndSettle();
    expect(inField(tester, en.providerServer), isTrue);
  });

  testWidgets('radio channels: the switch is saved at once, and put back if the save fails', (tester) async {
    await startApp(tester, rest: database);
    await openSettings(tester);
    expect(find.text(en.settingHiddenNone), findsOneWidget);
    OptionChip chip(String label) => tester.widget<OptionChip>(find.widgetWithText(OptionChip, label));
    expect(chip(en.settingOn).selected, isTrue);
    await click(tester, find.text(en.settingOff));
    expect(writes.last, 'POST user_settings?on_conflict=user_id {"show_radio":false}');
    expect(chip(en.settingOff).selected, isTrue);

    failing = ['POST user_settings?'];
    await click(tester, find.text(en.settingOn));
    expect(chip(en.settingOff).selected, isTrue);
  });

  testWidgets('hidden groups and channels are named; selecting one shows it again, and the focus moves to a neighbour', (tester) async {
    hiddenGroups = [5];
    hiddenChannels = [1, 2];
    await startApp(tester, rest: database);
    await openSettings(tester);
    expect(find.text(en.settingHiddenNone), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown, times: 3);
    expect(focusedChip(), 'News');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedChip(), 'Channel one');
    await press(tester, LogicalKeyboardKey.enter);
    expect(writes.last, startsWith('POST channel_prefs?on_conflict=user_id,channel_id '));
    expect(jsonDecode(writes.last.split(' ').last), containsPair('hidden', false));
    expect(find.text('Channel one'), findsNothing);
    expect(focusedChip(), 'Channel two');
    await press(tester, LogicalKeyboardKey.enter);
    expect(focusedChip(), 'News');
    await press(tester, LogicalKeyboardKey.enter);
    expect(writes.last, startsWith('POST live_group_prefs?on_conflict=user_id,category_id '));
    // Nothing is hidden any more: the radio switch has the focus.
    expect(find.text(en.settingHiddenNone), findsOneWidget);
    expect(focusedChip(), en.settingOn);
  });

  testWidgets('WTW: Connect asks first, then signs in to WTW with the same Google code; signing out ends both', (tester) async {
    await startApp(tester, rest: database);
    await openSettings(tester);
    // Signed out, WTW is not offered.
    expect(find.text(en.connectWtw), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    googleAnswers = [
      {'id_token': 'id-token'},
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(services.session.email, 'me@example.com');

    await openSettings(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.signOut)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.connectWtw)), isTrue);
    // The first press only asks; the second starts the sign-in.
    await press(tester, LogicalKeyboardKey.enter);
    expect(focused(tester, find.text(en.connectWtwConfirm)), isTrue);
    expect(calls.where((call) => call.startsWith('wtw.test')), isEmpty);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(calls.last, 'wtw.test/auth/v1/token?grant_type=id_token');
    expect(services.wtw.email, 'me@example.com');

    await openSettings(tester);
    expect(find.text(en.wtwConnected('me@example.com')), findsOneWidget);
    expect(find.text(en.signOutWtw), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect(services.session.email, isNull);
    expect(services.wtw.email, isNull);
    expect(calls, contains('wtw.test/auth/v1/logout?scope=local'));
  });
}
