import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/services.dart';

import 'fakes.dart';

/// Settings → Account: Google sign-in by a code, and sign-out.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  bool focused(WidgetTester tester, Finder item) => Focus.of(tester.element(item)).hasPrimaryFocus;

  /// From the language chips down to the account's button, then Enter.
  Future<void> pressSignIn(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.signInGoogle)), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
  }

  testWidgets('sign in with the code, then sign out', (tester) async {
    await startApp(tester);
    await openSettings(tester);
    expect(find.text(en.accountSignedOut), findsOneWidget);
    await pressSignIn(tester);
    // The code, the address without its prefix, and the focus on Cancel.
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.text(en.signInCode('google.com/device')), findsOneWidget);
    expect(focused(tester, find.text(en.cancel)), isTrue);
    // Not yet approved on the phone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    googleAnswers = [
      {'id_token': 'id-token'},
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Signed in: the frame is new, on the tabs.
    expect(calls.last, 'db.test/auth/v1/token?grant_type=id_token');
    expect(services.session.email, 'me@example.com');
    expect(focused(tester, find.text(en.tabHome)), isTrue);
    await openSettings(tester);
    expect(find.text('me@example.com'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(tester, find.text(en.signOut)), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(calls.last, 'db.test/auth/v1/logout?scope=local');
    expect(services.session.email, isNull);
    await openSettings(tester);
    expect(find.text(en.signInGoogle), findsOneWidget);
  });

  testWidgets('Cancel ends the wait for the phone', (tester) async {
    await startApp(tester);
    await openSettings(tester);
    await pressSignIn(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('ABCD-EFGH'), findsNothing);
    expect(focused(tester, find.text(en.signInGoogle)), isTrue);
    // The wait that was under way wakes once more and asks Google nothing.
    final before = calls.length;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(calls.length, before);
  });

  testWidgets('leaving Settings ends the wait for the phone', (tester) async {
    await startApp(tester);
    await openSettings(tester);
    await pressSignIn(tester);
    await press(tester, LogicalKeyboardKey.escape);
    final before = calls.length;
    await tester.pump(const Duration(seconds: 5));
    expect(calls.length, before);
  });

  testWidgets('a sign-in declined on the phone says so', (tester) async {
    await startApp(tester);
    await openSettings(tester);
    googleAnswers = [
      {'error': 'access_denied'},
    ];
    await pressSignIn(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(en.signInFailed('Sign-in was declined on the phone')), findsOneWidget);
    expect(focused(tester, find.text(en.signInGoogle)), isTrue);
  });
}
