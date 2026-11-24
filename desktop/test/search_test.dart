import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:wtv/app_language.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/ui/components/cards.dart';
import 'package:wtv/ui/components/pressable.dart';
import 'package:wtv/ui/person/person_screen.dart';
import 'package:wtv/ui/search/search_screen.dart';
import 'package:wtv/ui/title/title_screen.dart';

import 'fakes.dart';

/// A title row as the database gives it. No image addresses: a card then shows its name.
Map<String, Object?> row(int id, String name, {String kind = 'movie', String? he, int? year}) => {
  'id': id,
  'ext_id': id,
  'kind': kind,
  'name': name,
  'title_en': name,
  'title_he': he,
  'year': year,
  'tmdb_genre_ids': const <int>[],
  'group_id': id,
};

Map<String, Object?> person(int id, String name) => {'tmdb_id': id, 'name': name, 'profile': null};

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  // What the database finds; each test sets what it needs.
  var found = <Object?>[];
  var people = <Object?>[];
  var failing = <String>[];
  // What the screen alone was asked to open.
  var opened = <String>[];

  setUp(() {
    found = [row(1, 'Mad one', he: 'סרט אחד', year: 2020), row(2, 'Mad two', year: 2021)];
    people = [person(31, 'Mara Actor'), person(32, 'Mark Actor'), person(33, 'Mary Actor')];
    failing = [];
    opened = [];
  });

  Object? database(String read) {
    if (failing.any(read.startsWith)) return http.Response('', 500);
    if (read.startsWith('rpc/search_people?')) return people;
    // A search: the names that start with the query, and the names that hold it.
    if (read.startsWith('titles?') && read.contains('&or=')) return found;
    if (read.startsWith('title_cast?select=titles')) {
      return [
        {'titles': {...row(1, 'Mad one', year: 2020), 'is_primary': true, 'available': true}},
      ];
    }
    return const [];
  }

  Iterable<String> searches() => reads.where((read) => read.startsWith('titles?') && read.contains('&or='));
  Iterable<String> peopleSearches() => reads.where((read) => read.startsWith('rpc/search_people?'));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  /// Types `text` into the field and waits for its results.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(typingPause);
    await tester.pumpAndSettle();
  }

  /// Enter in the field, as the keyboard sends it to a text field.
  Future<void> enter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  T? focusedIn<T extends Widget>() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<T>();
  String? focusedCard() => focusedIn<ImageCard>()?.title;
  bool inField() => focusedIn<TextField>() != null;

  /// The text of the suggestion that has the focus.
  String? focusedSuggestion(WidgetTester tester) {
    final item = focusedIn<Pressable>();
    if (item == null || focusedIn<ImageCard>() != null) return null;
    return tester.widget<Text>(find.descendant(of: find.byWidget(item), matching: find.byType(Text)).first).data;
  }

  /// The search page by itself, its field focused.
  Future<void> search(WidgetTester tester, {SearchScope scope = SearchScope.all}) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    await showScreen(
      tester,
      SearchScreen(scope: scope, field: field, onOpen: (t) => opened.add(t.name), onPerson: (p) => opened.add(p.name)),
      rest: database,
    );
    field.requestFocus();
    await tester.pump();
  }

  testWidgets('a search waits for a pause in the typing; then the actors and the posters', (tester) async {
    await search(tester);
    expect(find.text(en.searchHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'm');
    await tester.pump(typingPause - const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField), 'ma');
    await tester.pump(typingPause - const Duration(milliseconds: 1));
    expect(searches(), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    // One search, of "ma" only: the names that start with it, the names that hold it, and the actors.
    expect(searches(), hasLength(2));
    expect(searches().every((read) => !read.contains('kind=eq.')), isTrue);
    expect(peopleSearches().single, 'rpc/search_people?p_query=ma');
    expect(find.byWidgetPredicate((w) => w is ImageCard && w.title == 'Mary Actor'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is ImageCard && w.title == 'Mad two'), findsOneWidget);

    // Emptied, the field shows nothing, and nothing is searched.
    await type(tester, '  ');
    expect(find.byType(ImageCard), findsNothing);
    expect(searches(), hasLength(2));
  });

  testWidgets('suggestions under the field: two actors, then titles with their year; Down reaches them, and picking one opens it', (tester) async {
    await search(tester);
    await type(tester, 'ma');
    expect(find.text(en.searchActor), findsNWidgets(2));
    expect(find.text('2020'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedSuggestion(tester), 'Mara Actor');
    await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
    expect(focusedSuggestion(tester), 'Mad one');
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['Mad one']);
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['Mad one', 'Mara Actor']);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(inField(), isTrue);

    // In the results the suggestions make room; Up from the top row is the field again.
    await press(tester, LogicalKeyboardKey.arrowDown, times: 5);
    expect(focusedCard(), isNotNull);
    expect(find.text(en.searchActor), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(inField(), isTrue);
    expect(find.text(en.searchActor), findsNWidgets(2));
  });

  testWidgets('Enter moves on to the results: at once when they are in, or when they arrive', (tester) async {
    await search(tester);
    await type(tester, 'ma');
    await enter(tester);
    expect(focusedCard(), 'Mara Actor');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedCard(), 'Mark Actor');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(), 'Mad one');

    // Typed on, and Enter before the pause is over: the earlier results are not this query's.
    await tester.enterText(find.byType(TextField), 'mad');
    await enter(tester);
    expect(inField(), isTrue);
    await tester.pump(typingPause);
    await tester.pumpAndSettle();
    expect(focusedCard(), 'Mara Actor');

    // Enter, then on to a suggestion before the results are in: they do not take the focus from it.
    await tester.enterText(find.byType(TextField), 'ma');
    await enter(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedSuggestion(tester), 'Mara Actor');
    await tester.pump(typingPause);
    await tester.pumpAndSettle();
    expect(focusedSuggestion(tester), 'Mara Actor');
  });

  testWidgets('nothing found says so; a failed search says why; without the actors the titles still show', (tester) async {
    await search(tester);
    found = [];
    people = [];
    await type(tester, 'zz');
    expect(find.text(en.noResults('zz')), findsOneWidget);
    // Enter with no results keeps the focus in the field.
    await enter(tester);
    expect(inField(), isTrue);

    failing = ['titles?'];
    await type(tester, 'zzz');
    expect(find.textContaining('Could not load'), findsOneWidget);

    failing = ['rpc/search_people?'];
    found = [row(1, 'Mad one', year: 2020)];
    await type(tester, 'ma');
    await enter(tester);
    expect(focusedCard(), 'Mad one');
  });

  group('in the app', () {
    Finder rail(IconData icon) => find.byIcon(icon);

    Future<void> click(WidgetTester tester, Finder item) async {
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    testWidgets('Search looks in the section on screen; the field has the focus; Back closes the page', (tester) async {
      await startApp(tester, rest: database);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight);
      await click(tester, rail(Icons.search_outlined));
      expect(find.text(en.searchHintMovies), findsOneWidget);
      expect(inField(), isTrue);

      // In an empty field Left has no text to move in: it goes to the side rail, and Right comes back.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text(en.railWatchlist), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(inField(), isTrue);

      await type(tester, 'ma');
      expect(searches().every((read) => read.contains('kind=eq.movie')), isTrue);
      expect(peopleSearches().single, 'rpc/search_people?p_query=ma&p_kind=movie');
      // With text in it, Left moves the cursor.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(inField(), isTrue);
      expect(find.text(en.railWatchlist), findsNothing);

      // An actor opens their page, a poster its title; Back returns to the search as it was.
      await enter(tester);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(PersonScreen), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(focusedCard(), 'Mara Actor');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(TitleScreen), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(focusedCard(), 'Mad one');

      await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
      expect(inField(), isTrue);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(SearchScreen), findsNothing);
    });

    testWidgets('in Hebrew the search is done again, by the Hebrew names', (tester) async {
      await startApp(tester, rest: database);
      await tester.pumpAndSettle();
      await click(tester, rail(Icons.search_outlined));
      expect(find.text(en.searchHint), findsOneWidget);
      await type(tester, 'ma');
      expect(searches().every((read) => read.contains('order=sort_name_en.asc')), isTrue);

      appLanguage.value = AppLanguage.hebrew;
      await tester.pump();
      await tester.pump(typingPause);
      await tester.pumpAndSettle();
      expect(searches(), hasLength(4));
      expect(searches().skip(2).every((read) => read.contains('order=sort_name_he.asc')), isTrue);
      expect(find.byWidgetPredicate((w) => w is ImageCard && w.title == 'סרט אחד'), findsOneWidget);
    });
  });
}
