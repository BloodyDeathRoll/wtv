import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:wtv/app_language.dart';
import 'package:wtv/data/catalog.dart';
import 'package:wtv/data/progress.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/ui/browse/browse_screen.dart';
import 'package:wtv/ui/components/buttons.dart';
import 'package:wtv/ui/components/cards.dart';
import 'package:wtv/ui/components/chips.dart';

import 'fakes.dart';

/// A title row as the database gives it. No image addresses: a card then shows its name.
Map<String, Object?> row(int id, String name, {String kind = 'movie', String? he, int? year, List<int> genres = const [], String? overview}) => {
  'id': id,
  'ext_id': id,
  'kind': kind,
  'name': name,
  'title_en': name,
  'title_he': he,
  'year': year,
  'tmdb_genre_ids': genres,
  'overview_en': overview,
  'group_id': id,
};

List<Map<String, Object?>> rows(int from, int count, String name) => [for (var i = from; i < from + count; i++) row(i, '$name $i')];

Map<String, Object?> category(int id, String name) => {'ext_id': id, 'name': name, 'name_en': name, 'name_he': null};

bool inCategory(String read, int id) => read.contains('group_category_ids=cs.%7B$id%7D');

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  /// The name on the card that has the focus; null when the focus is elsewhere.
  String? focusedCard() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ImageCard>()?.title;

  /// The label of the chip that has the focus.
  String? focusedChip() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<OptionChip>()?.label;

  Finder card(String name) => find.widgetWithText(ImageCard, name);
  Finder header(String text) => find.descendant(of: find.byType(TitleHeader), matching: find.text(text));

  /// Home with a series under way, two new movies and one new series.
  Object? home(String read) {
    if (read.startsWith('progress?')) {
      return [
        {
          'title_id': 7,
          'position_secs': 600,
          'duration_secs': 1200,
          'episodes': {'season': 1, 'episode': 2},
          'titles': row(7, 'Show', kind: 'series'),
        },
      ];
    }
    if (read.startsWith('genres?')) {
      return [
        {'kind': 'movie', 'id': 18, 'name_en': 'Drama', 'name_he': 'דרמה'},
      ];
    }
    if (!read.startsWith('titles?')) return const [];
    return read.contains('kind=eq.movie')
        ? [row(1, 'Movie one', he: 'סרט אחד', year: 2020, genres: [18], overview: 'First.'), row(2, 'Movie two', year: 2021)]
        : [row(11, 'Series one', kind: 'series')];
  }

  /// A section with four categories of three titles each; category 12's full list has 65.
  Object? section(String read) {
    if (read.startsWith('categories?')) return [category(12, 'Action'), category(13, 'Comedy'), category(14, 'Drama'), category(15, 'Horror')];
    if (read.startsWith('rpc/category_counts?')) {
      return [
        {'tag': 'all', 'id': 0, 'n': 300},
        {'tag': 'category', 'id': 12, 'n': 65},
        {'tag': 'category', 'id': 13, 'n': 3},
      ];
    }
    if (read.startsWith('rpc/recommended_page?')) {
      if (!read.contains('p_category=12')) return rows(900, 2, 'Any');
      return read.contains('p_offset=0') ? rows(100, 60, 'Pick') : rows(160, 5, 'Pick');
    }
    if (!read.startsWith('titles?')) return const [];
    if (read.contains('order=year')) return rows(200, 8, 'Newest');
    for (final (id, name) in [(12, 'A'), (13, 'B'), (14, 'C'), (15, 'D')]) {
      if (inCategory(read, id)) return rows(id * 10, 3, name);
    }
    return const [];
  }

  Future<void> openMovies(WidgetTester tester) async {
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('Action'), findsOneWidget);
  }

  testWidgets('Home: its rows, and a header that follows the focus', (tester) async {
    await startApp(tester, rest: home);
    await tester.pumpAndSettle();
    expect(reads.first, 'auth/v1/signup');
    // The third row is under the screen's edge.
    for (final label in [en.rowContinue, en.rowRecentMovies, en.rowRecentSeries]) {
      expect(find.text(label, skipOffstage: false), findsOneWidget);
    }
    // Nothing finished yet: no Watch it again row.
    expect(find.text(en.rowWatchAgain), findsNothing);
    // Continue watching names the episode to resume; the header starts on its card.
    expect(find.descendant(of: card('Show'), matching: find.text('S1 E2')), findsOneWidget);
    expect(header('Show'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(), 'Show');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(), 'Movie one');
    for (final text in ['Movie one', '2020', 'Drama', 'First.']) {
      expect(header(text), findsOneWidget);
    }
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedCard(), 'Movie two');
    expect(header('2021'), findsOneWidget);
    // The row has ended: the focus stays, where the framework would jump to another row.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedCard(), 'Movie two');

    // Up from the first row is the tabs, and the page is back at its top.
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    expect(focusedCard(), isNull);
    expect(header('Show'), findsOneWidget);
  });

  testWidgets('Hebrew reads the rows again and shows the Hebrew names', (tester) async {
    await startApp(tester, rest: home);
    await tester.pumpAndSettle();
    final before = reads.length;
    appLanguage.value = AppLanguage.hebrew;
    await tester.pumpAndSettle();
    expect(reads.length, greaterThan(before));
    expect(card('סרט אחד'), findsOneWidget);
    // No Hebrew name: the English one.
    expect(card('Movie two'), findsOneWidget);
  });

  testWidgets('a section: the focused row lands at the top; the mouse moves the focus without scrolling', (tester) async {
    await startApp(tester, rest: section);
    await openMovies(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(), 'A 120');
    // Under the header (60 + 148), a row's card is 40 down, the room for its title.
    const top = 60 + 148 + 40.0;
    for (final name in ['B 130', 'C 140', 'D 150']) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), name);
      expect(tester.getTopLeft(card(name)).dy, top);
    }
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedCard(), 'C 140');
    expect(tester.getTopLeft(card('C 140')).dy, top);

    // The pointer over a card of the row below: the focus and the header follow, the page stays.
    final below = tester.getCenter(card('D 151'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(below);
    await tester.pumpAndSettle();
    expect(focusedCard(), 'D 151');
    expect(header('D 151'), findsOneWidget);
    expect(tester.getCenter(card('D 151')), below);
  });

  testWidgets('More opens the whole category: pages as the focus nears the end, a choice of order, Back to the row', (tester) async {
    await startApp(tester, rest: section);
    await openMovies(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    expect(focusedCard(), en.more);
    await press(tester, LogicalKeyboardKey.enter);

    // The first page takes the focus when it arrives.
    expect(reads.last, contains('rpc/recommended_page?'));
    expect(reads.last, endsWith('&p_kind=movie&p_category=12&p_offset=0&p_limit=60'));
    expect(focusedCard(), 'Pick 100');
    expect(header('Pick 100'), findsOneWidget);

    // Rows of four; the focused row is at the top of the two on screen.
    await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
    expect(focusedCard(), 'Pick 108');
    expect(tester.getTopLeft(card('Pick 108')).dy, 60 + 148 + 12.0);
    // Two rows from the end, the next page is read.
    expect(reads.where((read) => read.contains('p_offset=60')), isEmpty);
    await press(tester, LogicalKeyboardKey.arrowDown, times: 11);
    expect(focusedCard(), 'Pick 152');
    expect(reads.last, endsWith('&p_category=12&p_offset=60&p_limit=60'));
    await press(tester, LogicalKeyboardKey.arrowDown, times: 3);
    expect(focusedCard(), 'Pick 164');

    // Up from the first row is the order chips, wherever the card is.
    await press(tester, LogicalKeyboardKey.arrowUp, times: 16);
    expect(focusedCard(), 'Pick 100');
    await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedChip(), en.sortRecommended);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(focusedChip(), en.sortYear);
    await press(tester, LogicalKeyboardKey.enter);
    expect(reads.last, contains('&group_category_ids=cs.%7B12%7D&order=year.desc.nullslast,id&offset=0&limit=60'));
    // After a change of order the focus stays on the chips.
    expect(focusedChip(), en.sortYear);
    expect(card('Newest 200'), findsOneWidget);
    expect(card('Pick 100'), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(), startsWith('Newest'));

    // Back: the section again, on the card the category was opened from.
    await press(tester, LogicalKeyboardKey.escape);
    expect(focusedCard(), en.more);
  });

  testWidgets('a later page that fails: Down reaches the Retry under the grid, which reads the page again', (tester) async {
    var down = false;
    await startApp(tester, rest: (read) => down && read.contains('p_offset=60') ? http.Response('', 500) : section(read));
    await openMovies(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    await press(tester, LogicalKeyboardKey.enter);
    down = true;
    // 60 titles in rows of four: the fifteenth row is the last.
    await press(tester, LogicalKeyboardKey.arrowDown, times: 14);
    expect(focusedCard(), 'Pick 156');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ActionButton>()?.label, en.retry);
    down = false;
    await press(tester, LogicalKeyboardKey.enter);
    expect(card('Pick 160'), findsOneWidget);
  });

  testWidgets('Categories lists the tags with their numbers; a tag opens its titles', (tester) async {
    await startApp(tester, rest: section);
    await openMovies(tester);
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    // The tags arrive after the page opened: the first one takes the focus then.
    expect(focusedChip(), en.categoriesAllMovies);
    OptionChip chip(String label) => tester.widget(find.widgetWithText(OptionChip, label));
    expect(chip(en.categoriesAllMovies).detail, '300');
    expect(chip('Action').detail, '65');
    // A category the count leaves out has no titles: it is not listed.
    expect(find.widgetWithText(OptionChip, 'Drama'), findsNothing);

    await press(tester, LogicalKeyboardKey.enter);
    expect(reads.last, endsWith('&p_kind=movie&p_offset=0&p_limit=60'));
    expect(focusedCard(), 'Any 900');
    await press(tester, LogicalKeyboardKey.escape);
    expect(focusedChip(), en.categoriesAllMovies);
  });

  testWidgets('a page that fails to load says why; Retry reads it again', (tester) async {
    var down = true;
    await startApp(tester, rest: (read) => down ? http.Response('', 500) : home(read));
    await tester.pumpAndSettle();
    expect(find.text(en.loadFailed('Could not load titles (HTTP 500)')), findsOneWidget);
    down = false;
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect(card('Movie one'), findsOneWidget);
  });

  test('Continue watching: an episode under way is named; a finished one shows neither label nor bar', () {
    Title t(int id) => title(row(id, 'T$id', kind: 'series'));
    String label(int season, int episode) => 'S$season E$episode';
    expect(continueRow(const [], 'Continue', label), isNull);
    final got = continueRow(
      [
        ContinueItem(t(1), const Progress(1, 2, 3, 300, 1200)),
        ContinueItem(t(2), const Progress(2, 1, 1, 1190, 1200)),
        ContinueItem(t(3), const Progress(3, null, null, 60, null)),
      ],
      'Continue',
      label,
    )!;
    expect(got.titles.map((title) => title.id), [1, 2, 3]);
    expect(got.progress, {1: (0.25, 'S2 E3'), 2: (null, null), 3: (null, null)});
  });
}
