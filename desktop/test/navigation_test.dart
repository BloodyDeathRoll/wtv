import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wtv/app_language.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/ui/components/side_rail.dart';
import 'package:wtv/ui/theme.dart';

import 'fakes.dart';

/// The keyboard's and the mouse's Back and focus rules in `ui/wtv_app.dart`:
/// the TV app's `NavigationTest`, plus the mouse.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final he = lookupAppLocalizations(const Locale('he'));

  const start = startApp;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, Finder item) async {
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  bool focused(WidgetTester tester, Finder item) => Focus.of(tester.element(item)).hasPrimaryFocus;
  Finder rail(IconData icon) => find.byIcon(icon);
  const settings = Icons.settings_outlined;
  const categories = Icons.grid_view_outlined;

  testWidgets('starts on the Home tab; the arrow keys switch the section', (tester) async {
    await start(tester);
    expect(focused(tester, find.text(en.tabHome)), isTrue);
    // Categories lists movie or series tags, so it is offered on Movies only.
    expect(rail(categories), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester, find.text(en.tabMovies)), isTrue);
    expect(rail(categories), findsOneWidget);
  });

  testWidgets('Left and Right go along the tabs to Live TV and stop there; Left from the first tab is the rail', (tester) async {
    await start(tester);
    for (final tab in [en.tabMovies, en.tabSeries, en.tabLive, en.tabLive]) {
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(tester, find.text(tab)), isTrue, reason: tab);
    }
    for (final tab in [en.tabSeries, en.tabMovies, en.tabHome]) {
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(tester, find.text(tab)), isTrue, reason: tab);
    }
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SideRail>(), isNotNull);
  });

  testWidgets('a click on a tab switches the section; the pointer passing over one does not', (tester) async {
    await start(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text(en.tabSeries)));
    await tester.pumpAndSettle();
    expect(focused(tester, find.text(en.tabHome)), isTrue);
    await click(tester, find.text(en.tabSeries));
    expect(focused(tester, find.text(en.tabSeries)), isTrue);
    expect(rail(categories), findsOneWidget);
  });

  testWidgets('Back on the tabs asks before leaving', (tester) async {
    await start(tester);
    var left = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') left = true;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text(en.exitQuestion), findsOneWidget);
    expect(focused(tester, find.text(en.yes)), isTrue);
    // No (Back) keeps the app on the tabs.
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text(en.exitQuestion), findsNothing);
    expect(focused(tester, find.text(en.tabHome)), isTrue);
    expect(left, isFalse);
    // Yes (focused) leaves.
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.enter);
    expect(left, isTrue);
  });

  testWidgets('a page opens from the side rail and closes on Back, to the selected tab', (tester) async {
    await start(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await click(tester, rail(categories));
    expect(find.text(en.railCategories), findsWidgets);
    // The tabs are under the page: not drawn, and out of the keys' reach.
    expect(find.text(en.tabMovies), findsNothing);
    await press(tester, LogicalKeyboardKey.escape);
    // The selected tab, not the first one: focusing Home would switch the section.
    expect(focused(tester, find.text(en.tabMovies)), isTrue);
  });

  testWidgets('the mouse back button closes a page', (tester) async {
    await start(tester);
    await click(tester, rail(settings));
    expect(find.text(en.settingLanguage), findsOneWidget);
    final mouse = await tester.startGesture(const Offset(480, 400), kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text(en.settingLanguage), findsNothing);
  });

  testWidgets('Main menu closes every page and returns to the tabs', (tester) async {
    await start(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await click(tester, rail(categories));
    await click(tester, rail(settings));
    await click(tester, rail(Icons.home_outlined));
    expect(find.text(en.settingLanguage), findsNothing);
    expect(focused(tester, find.text(en.tabMovies)), isTrue);
  });

  testWidgets('a page already open is returned to, not opened twice', (tester) async {
    await start(tester);
    await click(tester, rail(settings));
    await click(tester, rail(Icons.bookmark_border_outlined));
    await click(tester, rail(settings));
    expect(find.text(en.settingLanguage), findsOneWidget);
    // One Back from Settings reaches the tabs: Watchlist is no longer over it, nor a second Settings.
    await press(tester, LogicalKeyboardKey.escape);
    expect(focused(tester, find.text(en.tabHome)), isTrue);
  });

  testWidgets('the rail and the page hand the focus to each other; the page gets back the item it had', (tester) async {
    await start(tester);
    await click(tester, rail(settings));
    // The page opens on the current language.
    expect(focused(tester, find.text(en.languageEnglish)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester, find.text(en.languageHebrew)), isTrue);
    // Nothing further that way: the focus stays.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester, find.text(en.languageHebrew)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    // The row of chips ends here. The account's button, lower and further left, is another row: not where Left goes.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    // On the rail, which opens and names its icons. The nearest icon has the focus, and shows it.
    expect(find.text(en.railWatchlist), findsOneWidget);
    expect(focused(tester, find.text(en.languageEnglish)), isFalse);
    expect(focused(tester, rail(Icons.search_outlined)), isTrue);
    expect(tester.widget<Icon>(rail(Icons.search_outlined)).color, WtvColors.background);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text(en.railWatchlist), findsNothing);
    expect(focused(tester, find.text(en.languageEnglish)), isTrue);
  });

  testWidgets('a page with no items still reaches the rail and closes on Back', (tester) async {
    await start(tester);
    await click(tester, rail(Icons.bookmark_border_outlined));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text(en.railSettings), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text(en.railSettings), findsNothing);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focused(tester, find.text(en.tabHome)), isTrue);
  });

  testWidgets('the pointer moves the focus: over the rail it opens, off it the page has the focus again', (tester) async {
    await start(tester);
    await click(tester, rail(settings));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(480, 400));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(rail(Icons.search_outlined)));
    await tester.pumpAndSettle();
    expect(find.text(en.railSearch), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text(en.languageHebrew)));
    await tester.pumpAndSettle();
    expect(find.text(en.railSearch), findsNothing);
    expect(focused(tester, find.text(en.languageHebrew)), isTrue);
  });

  testWidgets('Hebrew turns the layout around and is kept for the next start', (tester) async {
    await start(tester);
    await click(tester, rail(settings));
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text(he.settingLanguage), findsOneWidget);
    expect(tester.getCenter(rail(settings)).dx, greaterThan(900));
    expect((await SharedPreferences.getInstance()).getString('language'), 'he');
    // The chip pressed keeps the focus. The chips now run right to left, and the rail is past the first one.
    expect(focused(tester, find.text(he.languageHebrew)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(tester, find.text(he.languageEnglish)), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text(he.railWatchlist), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text(he.railWatchlist), findsNothing);
    expect(focused(tester, find.text(he.languageEnglish)), isTrue);
  });

  test('an unknown stored language is English', () {
    expect(AppLanguage.fromTag(null), AppLanguage.english);
    expect(AppLanguage.fromTag('fr'), AppLanguage.english);
    expect(AppLanguage.fromTag('he'), AppLanguage.hebrew);
  });
}
