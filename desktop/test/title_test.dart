import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:wtv/data/catalog.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/ui/components/actions.dart';
import 'package:wtv/ui/components/buttons.dart';
import 'package:wtv/ui/components/cards.dart';
import 'package:wtv/ui/components/chips.dart';
import 'package:wtv/ui/components/hero.dart';
import 'package:wtv/ui/components/title_menu.dart';
import 'package:wtv/ui/person/person_screen.dart';
import 'package:wtv/ui/title/title_screen.dart';

import 'fakes.dart';

/// A title row as the database gives it. No image addresses: a card then shows its name.
Map<String, Object?> row(int id, String name, {String kind = 'movie', int? year}) => {
  'id': id,
  'ext_id': id,
  'container_ext': 'mkv',
  'kind': kind,
  'name': name,
  'title_en': name,
  'year': year,
  'tmdb_genre_ids': kind == 'movie' ? [18] : const <int>[],
  'overview_en': 'About $name.',
  'certification': 'PG-13',
  'tmdb_runtime_min': 125,
  'director': 'Dana Director',
  'cast_names': 'Someone Else',
  'tmdb_rating': 7.46,
  'original_language': 'en',
  'group_id': id,
};

Map<String, Object?> episodeRow(int id, int season, int number, {String? name}) => {
  'id': id,
  'ext_id': id,
  'container_ext': 'mkv',
  'season': season,
  'episode': number,
  'name_en': name,
  'duration_secs': 1200,
};

/// A saved position on title `id`: a movie's, or (with a season and number) an episode's.
Map<String, Object?> saved(int id, int position, {int duration = 6000, (int, int)? episode}) => {
  'title_id': id,
  'position_secs': position,
  'duration_secs': duration,
  'episodes': episode == null ? null : {'season': episode.$1, 'episode': episode.$2},
  'titles': row(id, id == 7 ? 'Show' : 'Movie one', kind: id == 7 ? 'series' : 'movie'),
};

Map<String, Object?> castRow(int position, int person, String name) => {
  'position': position,
  'character': 'Role $position',
  'people': {'tmdb_id': person, 'name': name, 'profile': null},
};

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final movie = title(row(1, 'Movie one', year: 2020));
  final series = title(row(7, 'Show', kind: 'series', year: 2019));

  // What the database holds; each test sets what it needs.
  var copies = <Object?>[];
  var positions = <Object?>[];
  var episodes = <Object?>[];
  var cast = <Object?>[];
  var alsoLiked = <Object?>[];
  var listed = <Map<String, Object?>>[];
  String? rating;
  var failing = <String>[];

  setUp(() {
    copies = [];
    positions = [];
    episodes = [];
    cast = [];
    alsoLiked = [];
    listed = [];
    rating = null;
    failing = [];
  });

  Object? database(String read) {
    if (failing.any(read.startsWith)) return http.Response('', 500);
    // The writes change what is read next.
    if (read.startsWith('DELETE progress?')) positions = [];
    if (read.startsWith('DELETE watchlist?')) listed = [];
    if (read.startsWith('title_cast?select=position')) return cast;
    if (read.startsWith('title_cast?select=titles')) {
      return [
        {'titles': {...row(1, 'Movie one', year: 2020), 'is_primary': true, 'available': true}},
        {'titles': {...row(2, 'Movie two', year: 2021), 'is_primary': true, 'available': true}},
      ];
    }
    if (read.startsWith('titles?select=id,ext_id,container_ext,category_ids')) return copies;
    if (read.startsWith('categories?')) {
      return [
        {'ext_id': 12, 'name': 'Action', 'name_en': 'Action', 'name_he': null},
        {'ext_id': 99, 'name': 'Movies 4K', 'name_en': 'Movies 4K', 'name_he': null},
      ];
    }
    if (read.startsWith('genres?')) {
      return [
        {'kind': 'movie', 'id': 18, 'name_en': 'Drama', 'name_he': 'דרמה'},
      ];
    }
    if (read.startsWith('rpc/also_liked?')) return alsoLiked;
    if (read.startsWith('progress?')) return positions;
    if (read.startsWith('episodes?')) return episodes;
    if (read.startsWith('ratings?')) return [if (rating != null) {'rating': rating}];
    if (read.startsWith('watchlist?select=title_id')) return [if (listed.isNotEmpty) {'title_id': 1}];
    if (read.startsWith('watchlist?select=added_at')) return [for (final t in listed) {'added_at': '2026-11-01', 'titles': t}];
    if (read.startsWith('titles?')) return read.contains('kind=eq.movie') ? [row(1, 'Movie one', year: 2020), row(2, 'Movie two', year: 2021)] : const [];
    return const [];
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  Future<void> click(WidgetTester tester, Finder item) async {
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  T? focusedIn<T extends Widget>() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<T>();
  String? focusedCard() => focusedIn<ImageCard>()?.title;
  // By its name, which a card with no image shows twice: in place of the image, and as its label.
  Finder card(String name) => find.byWidgetPredicate((widget) => widget is ImageCard && widget.title == name);
  Finder action(String name) => find.bySemanticsLabel(name);
  Finder header(String text) => find.descendant(of: find.byType(HeroText), matching: find.text(text));

  /// What Play started: a copy's or an episode's id, and the second to start at.
  final played = <(int, int)>[];
  // The episodes handed over with the last episode played, for the next one.
  var handed = 0;
  final play = FocusNode();
  setUp(played.clear);
  tearDownAll(play.dispose);

  /// The title's page by itself, opened on Play as the app frame opens it.
  Future<void> open(WidgetTester tester, Title title, {bool autoPlay = false}) async {
    await showScreen(
      tester,
      FocusScope(
        // A page of its own each time, as in the app.
        key: UniqueKey(),
        child: TitleScreen(
          title,
          autoPlay: autoPlay,
          play: play,
          onPlay: (copy, start) => played.add((copy.id, start)),
          onPlayEpisode: (episode, start, all) {
            played.add((episode.id, start));
            handed = all.length;
          },
          onPerson: (_) {},
          onOpen: (_) {},
        ),
      ),
      rest: database,
    );
    play.requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets('a movie: its header, and Play from the start', (tester) async {
    cast = [castRow(0, 31, 'Ada Actor')];
    alsoLiked = [row(2, 'Movie two')];
    await open(tester, movie);
    for (final text in ['Movie one', '2020', '2 h 5 min', 'Drama', 'PG-13', 'About Movie one.']) {
      expect(header(text), findsOneWidget, reason: text);
    }
    expect(header('4K'), findsNothing);
    expect(find.text(en.rowEpisodes), findsNothing);
    expect([find.text(en.rowAlsoLiked), find.text(en.rowCast), card('Movie two'), card('Ada Actor')], everyElement(findsOneWidget));
    // Nothing watched: no Start over, nothing to take out of Continue watching.
    expect([action(en.startOver), action(en.removeFromContinue)], everyElement(findsNothing));
    expect(focusedIn<PlayButton>()?.label, en.play);
    await press(tester, LogicalKeyboardKey.enter);
    // The copies' read gave none: the title plays as its own copy.
    expect(played, [(1, 0)]);
  });

  testWidgets('a movie stopped part way: Resume, Start over, and out of Continue watching', (tester) async {
    positions = [saved(1, 600)];
    await open(tester, movie);
    expect(focusedIn<PlayButton>()?.label, en.resume);
    await press(tester, LogicalKeyboardKey.enter);
    await click(tester, action(en.startOver));
    expect(played, [(1, 600), (1, 0)]);

    await click(tester, action(en.removeFromContinue));
    expect(writes, ['DELETE progress?title_id=in.(1)']);
    // The button is gone, and the focus went to Play, not off the page.
    expect([action(en.removeFromContinue), action(en.startOver)], everyElement(findsNothing));
    expect(focusedIn<PlayButton>()?.label, en.play);
  });

  testWidgets('two copies: Play asks which, the 4K one first', (tester) async {
    copies = [
      {'id': 1, 'ext_id': 1, 'container_ext': 'mkv', 'category_ids': [12]},
      {'id': 5, 'ext_id': 5, 'container_ext': 'mp4', 'category_ids': [99]},
    ];
    await open(tester, movie);
    expect(header('4K'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text(en.chooseCopy), findsOneWidget);
    expect(focusedIn<ActionButton>()?.label, '4K');
    // Back closes it and plays nothing.
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text(en.chooseCopy), findsNothing);
    expect(played, isEmpty);

    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedIn<ActionButton>()?.label, 'HD');
    await press(tester, LogicalKeyboardKey.enter);
    expect(played, [(1, 0)]);
    expect(find.text(en.chooseCopy), findsNothing);
  });

  testWidgets('Play pressed before the page has loaded waits for the saved position', (tester) async {
    positions = [saved(1, 600)];
    await open(tester, movie, autoPlay: true);
    expect(played, [(1, 600)]);
  });

  testWidgets('a series: Play is the next episode; the header follows the focused episode; a season chip shows its season', (tester) async {
    episodes = [episodeRow(101, 1, 1, name: 'Pilot'), episodeRow(102, 1, 2), episodeRow(201, 2, 1, name: 'Return')];
    // Episode 1 was watched to the end, episode 2 part way.
    positions = [saved(7, 300, duration: 1200, episode: (1, 2)), saved(7, 1200, duration: 1200, episode: (1, 1))];
    await open(tester, series);
    expect([header('Show'), header('2 seasons'), header('2019')], everyElement(findsOneWidget));
    // A series has no length of its own.
    expect(header('2 h 5 min'), findsNothing);
    expect(focusedIn<PlayButton>()?.label, en.resume);
    await press(tester, LogicalKeyboardKey.enter);
    expect(played, [(102, 300)]);
    expect(handed, 3);

    // Season 1's episodes, each with how much was watched.
    expect([card('Pilot'), card('Episode 2')], everyElement(findsOneWidget));
    expect(card('Return'), findsNothing);
    expect([for (final name in ['Pilot', 'Episode 2']) tester.widget<ImageCard>(card(name)).progress], [1.0, 0.25]);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(), 'Pilot');
    expect([header('Pilot'), header('S1 E1'), header('20 min'), header('2019')], everyElement(findsOneWidget));
    expect(header('2 seasons'), findsNothing);
    // A finished episode plays from its start, an unfinished one from where it stopped.
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(header('Episode 2'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    expect(played.skip(1), [(101, 0), (102, 300)]);

    // Moving onto a season's chip shows that season; the header is the series' again.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedIn<OptionChip>()?.label, 'Season 1');
    expect(header('Show'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedIn<OptionChip>()?.label, 'Season 2');
    expect([card('Return'), card('Pilot')], [findsOneWidget, findsNothing]);
  });

  testWidgets('a series nothing was watched of plays its first episode; after a finished one, the next is named', (tester) async {
    episodes = [episodeRow(101, 1, 1), episodeRow(102, 1, 2)];
    await open(tester, series);
    expect(focusedIn<PlayButton>()?.label, en.play);
    // One season: no chips, and no count in the header.
    expect([find.byType(OptionChip), header('1 season')], everyElement(findsNothing));
    await press(tester, LogicalKeyboardKey.enter);
    expect(played, [(101, 0)]);

    positions = [saved(7, 1200, duration: 1200, episode: (1, 1))];
    await open(tester, series);
    expect(focusedIn<PlayButton>()?.label, 'Play S1 E2');
  });

  testWidgets('a rating shows at once and is saved; pressed again it is cleared; a failed save puts it back', (tester) async {
    rating = 'like';
    listed = [row(1, 'Movie one')];
    await open(tester, movie);
    bool chosen(String name) => tester.widget<ActionIcon>(find.ancestor(of: action(name), matching: find.byType(ActionIcon))).selected!;
    expect([chosen(en.rateLike), chosen(en.rateLove), chosen(en.removeFromWatchlist)], [true, false, true]);

    await click(tester, action(en.rateLove));
    expect([chosen(en.rateLove), chosen(en.rateLike)], [true, false]);
    await click(tester, action(en.rateLove));
    expect(chosen(en.rateLove), isFalse);
    await click(tester, action(en.removeFromWatchlist));
    expect(chosen(en.addToWatchlist), isFalse);
    expect(writes, [
      'POST ratings?on_conflict=user_id,title_id {"title_id":1,"rating":"love"}',
      'DELETE ratings?title_id=eq.1',
      'DELETE watchlist?title_id=eq.1',
    ]);

    failing = ['POST ratings'];
    await click(tester, action(en.rateDislike));
    expect(writes.last, 'POST ratings?on_conflict=user_id,title_id {"title_id":1,"rating":"dislike"}');
    expect(chosen(en.rateDislike), isFalse);
  });

  testWidgets('More info: the synopsis and the credits; Back closes it', (tester) async {
    cast = [castRow(0, 31, 'Ada Actor'), castRow(1, 32, 'Bo Player')];
    await open(tester, movie);
    await click(tester, action(en.moreInfo));
    for (final text in ['Director: Dana Director', 'Cast: Ada Actor, Bo Player', 'Original language: EN', 'Rating: 7.5 / 10 (TMDB)']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(focusedIn<ActionButton>()?.label, en.close);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Director: Dana Director'), findsNothing);
    expect(focusedIn<ActionIcon>()?.description, en.moreInfo);
  });

  group('in the app', () {
    /// Home, with a series under way and two new movies.
    Future<void> home(WidgetTester tester) async {
      positions = [saved(7, 600, duration: 1200, episode: (1, 2))];
      cast = [castRow(0, 31, 'Ada Actor')];
      await startApp(tester, rest: database);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
      expect(focusedCard(), 'Movie one');
    }

    testWidgets('a card opens its title on Play; a cast member opens their titles; Back returns card by card', (tester) async {
      await home(tester);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(TitleScreen), findsOneWidget);
      expect(focusedIn<PlayButton>(), isNotNull);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), 'Ada Actor');
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.descendant(of: find.byType(PersonScreen), matching: find.text('Ada Actor')), findsOneWidget);
      expect(find.text('2 titles on this service'), findsOneWidget);
      // Newest first; the first poster has the focus, and its name is under the header.
      expect(focusedCard(), 'Movie two');
      expect(find.text('Movie two   2021   PG-13'), findsOneWidget);

      // A title of theirs that is already open is gone back to, not opened twice.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(PersonScreen), findsNothing);
      expect(focusedCard(), 'Ada Actor');
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(TitleScreen), findsNothing);
      expect(focusedCard(), 'Movie one');
    });

    testWidgets('a card\'s menu: the Menu key, Shift+F10 or a right click', (tester) async {
      await home(tester);
      String? focusedItem() => focusedIn<MenuItem>()?.label;
      List<String> items() => [for (final item in tester.widgetList<MenuItem>(find.byType(MenuItem))) item.label];

      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(items(), [en.addToWatchlist, en.moreInfo, en.play, en.close]);
      expect(focusedItem(), en.play);
      await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
      await press(tester, LogicalKeyboardKey.enter);
      expect(writes, ['POST watchlist?on_conflict=user_id,title_id {"title_id":1}']);
      // The menu closed, and the focus is back on its card.
      expect(find.byType(TitleMenu), findsNothing);
      expect(focusedCard(), 'Movie one');

      // From Continue watching the menu can also take the title out of that row.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedCard(), 'Show');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(items(), contains(en.menuRemove));
      await click(tester, find.text(en.menuRemove));
      expect(writes.last, 'DELETE progress?title_id=in.(7)');
      expect(find.text(en.rowContinue), findsNothing);

      // More info opens the title's page.
      await tester.tap(card('Movie two'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(TitleMenu), matching: find.text('Movie two')), findsOneWidget);
      await click(tester, find.text(en.moreInfo));
      expect(find.descendant(of: find.byType(TitleScreen), matching: header('Movie two')), findsOneWidget);
    });

    testWidgets('the watchlist: posters, a choice of kind, and a title removed on its page is gone on Back', (tester) async {
      listed = [row(1, 'Movie one', year: 2020), row(7, 'Show', kind: 'series')];
      await startApp(tester, rest: database);
      await tester.pumpAndSettle();
      await click(tester, find.byIcon(Icons.bookmark_border_outlined));
      expect(focusedCard(), 'Movie one');
      expect([card('Movie one'), card('Show')], everyElement(findsOneWidget));

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIn<OptionChip>(), isNotNull);
      await click(tester, find.widgetWithText(OptionChip, en.tabSeries));
      expect([card('Movie one'), card('Show')], [findsNothing, findsOneWidget]);
      await click(tester, find.widgetWithText(OptionChip, en.filterAll));

      await click(tester, card('Movie one'));
      await click(tester, action(en.removeFromWatchlist));
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(TitleScreen), findsNothing);
      expect(find.text(en.nothingHere), findsOneWidget);
    });
  });
}
