import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/ui/components/cards.dart';
import 'package:wtv/ui/components/chips.dart';
import 'package:wtv/ui/components/hero.dart';
import 'package:wtv/ui/grid/grid_screen.dart';
import 'package:wtv/ui/title/title_screen.dart';

import 'browse_test.dart' show row;
import 'fakes.dart';

/// A title row with the "% match" the server kept for it (null: not asked of WTW yet).
Map<String, Object?> _scored(int id, String name, int? match, {String kind = 'movie'}) => {...row(id, name, kind: kind), 'wtw_match': match};

/// What WTW answers for a title it is asked about; it does not score title 4.
int? _percent(int id) => id == 4 ? null : id % 50 + 40;

String _scores(List<int> ids) => 'wtw-scores {"wtw_token":"wtw-access","title_ids":[${ids.join(',')}]}';

/// WTW in the screens: the picks rows, the Recommended for You page, the "% match", and the ranking.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  String? focusedCard() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ImageCard>()?.title;
  int? matchOn(WidgetTester tester, String name) => tester.widget<ImageCard>(find.widgetWithText(ImageCard, name)).match;
  Finder headerMatch(int percent) => find.descendant(of: find.byType(HeaderMatch), matching: find.text(en.wtwMatch(percent)));
  Iterable<String> readsOf(String start) => reads.where((read) => read.startsWith(start));

  // Whether the server makes a new ranking when asked.
  var newRanking = false;
  setUp(() => newRanking = false);

  Object? database(String read) {
    if (read.startsWith('rpc/top_picks?')) return [_scored(1, 'Pick one', 91), _scored(2, 'Pick two', null)];
    if (read.startsWith('rpc/top_picks_page?')) {
      if (read.contains('p_kind=movie')) return [_scored(31, 'Movie pick', 77)];
      return read.contains('p_offset=0') ? [for (var i = 0; i < 50; i++) _scored(100 + i, 'Best $i', null)] : [_scored(160, 'Best last', null)];
    }
    if (read.startsWith('rpc/new_for_you?')) return [_scored(3, 'Fresh one', 64)];
    if (read.startsWith('rpc/watch_again?')) return [_scored(4, 'Loved one', null)];
    if (read.startsWith('rpc/finished_titles?')) return [_scored(5, 'Finished one', 50)];
    if (!read.startsWith('titles?')) return const [];
    return read.contains('kind=eq.movie') ? [_scored(6, 'Movie new', 55)] : [_scored(7, 'Series new', null, kind: 'series')];
  }

  Object? server(String name, Map<String, Object?> body) => name == 'rank'
      ? {'fresh': !newRanking}
      : {
          'scores': {for (final id in body['title_ids']! as List) '$id': _percent(id as int)},
        };

  Future<void> home(WidgetTester tester, {bool wtw = true}) async {
    await startApp(tester, rest: database, functions: server, wtw: wtw);
    await tester.pumpAndSettle();
  }

  testWidgets('Home with WTW: the picks rows, each card with its match, asked of WTW only for the rows near the focus', (tester) async {
    await home(tester);
    expect(ran.first, 'rank {"wtw_token":"wtw-access"}');
    expect([find.text(en.rowTopPicks), find.text(en.rowNewForYou)], everyElement(findsOneWidget));
    // Watch it again is what was Loved or Liked in WTW, not what was finished here.
    expect([readsOf('rpc/watch_again?').length, readsOf('rpc/finished_titles?').length], [1, 0]);
    // The server's ranking was still fresh: the rows were read once.
    expect(readsOf('rpc/top_picks?').length, 1);

    // The first three rows at once: only the card that came without a match is asked for.
    expect(ran.skip(1), [
      _scores([2]),
    ]);
    expect([matchOn(tester, 'Pick one'), matchOn(tester, 'Pick two'), matchOn(tester, 'Fresh one')], [91, 42, 64]);
    // The header shows the match of the title it shows.
    expect(headerMatch(91), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect([focusedCard(), headerMatch(42)], ['Pick two', findsOneWidget]);
    // Further down, the focused row and the one under it are asked for as the focus gets there.
    await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
    expect([focusedCard(), ran.last], ['Movie new', _scores([7])]);
    await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
    expect([focusedCard(), ran.last, ran.length], ['Loved one', _scores([4]), 4]);
    // WTW does not score it: no number, on the card or in the header.
    expect([matchOn(tester, 'Loved one'), find.byType(HeaderMatch)], [isNull, findsNothing]);
  });

  testWidgets('without WTW: no picks rows, no match on a card or a title\'s page, and nothing is asked of the server', (tester) async {
    await home(tester, wtw: false);
    expect([find.text(en.rowTopPicks), find.text(en.rowNewForYou), find.byType(HeaderMatch)], everyElement(findsNothing));
    expect([readsOf('rpc/top_picks').length, readsOf('rpc/watch_again?').length, readsOf('rpc/finished_titles?').length], [0, 0, 1]);
    // The match that came with a title is not shown.
    expect(matchOn(tester, 'Movie new'), isNull);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect([find.byType(TitleScreen), find.byType(HeaderMatch), ran], [findsOneWidget, findsNothing, isEmpty]);
  });

  testWidgets('a new ranking reads the rows again', (tester) async {
    newRanking = true;
    await home(tester);
    expect([readsOf('rpc/top_picks?').length, find.text(en.rowTopPicks)], [2, findsOneWidget]);
  });

  testWidgets('More on Top picks opens Recommended for You: 50 at a time, no choice of order, the match asked for the rows near the focus', (
    tester,
  ) async {
    await home(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(focusedCard(), en.more);
    await press(tester, LogicalKeyboardKey.enter);
    expect([find.byType(PosterGrid), find.text(en.rowRecommended), find.byType(OptionChip)], [findsOneWidget, findsOneWidget, findsNothing]);
    // Both kinds: no kind is named.
    expect(reads.last, allOf(startsWith('rpc/top_picks_page?'), contains('p_offset=0&p_limit=50'), isNot(contains('p_kind'))));
    // The two rows on screen and the one under them, six titles a call.
    expect(ran.skip(ran.length - 2), [
      _scores([100, 101, 102, 103, 104, 105]),
      _scores([106, 107, 108, 109, 110, 111]),
    ]);
    expect([focusedCard(), matchOn(tester, 'Best 0'), headerMatch(40)], ['Best 0', 40, findsOneWidget]);
    // A row down, the next row under is asked for.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(ran.last, _scores([112, 113, 114, 115]));

    await press(tester, LogicalKeyboardKey.escape);
    expect([find.byType(PosterGrid), focusedCard()], [findsNothing, en.more]);
  });

  testWidgets('a section starts with Recommended for You, of its kind; its More opens that kind\'s page', (tester) async {
    await home(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text(en.rowRecommended), findsOneWidget);
    expect(readsOf('rpc/top_picks_page?').single, allOf(contains('p_offset=0&p_limit=10'), contains('p_kind=movie')));
    expect(readsOf('rpc/watch_again?').last, contains('p_kind=movie'));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect([focusedCard(), matchOn(tester, 'Movie pick')], ['Movie pick', 77]);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(PosterGrid), findsOneWidget);
    expect(reads.last, allOf(startsWith('rpc/top_picks_page?'), contains('p_offset=0&p_limit=50'), contains('p_kind=movie')));
  });

  testWidgets('a title\'s page shows its match: the one that came with it, or WTW\'s answer', (tester) async {
    await home(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect([find.byType(TitleScreen), headerMatch(91)], [findsOneWidget, findsOneWidget]);
    await press(tester, LogicalKeyboardKey.escape);

    // The newest series came without one, and its row is too far down to have been asked for.
    await press(tester, LogicalKeyboardKey.arrowDown, times: 3);
    expect(focusedCard(), 'Series new');
    final asked = ran.length;
    await press(tester, LogicalKeyboardKey.enter);
    expect([find.byType(TitleScreen), headerMatch(47), ran.length], [findsOneWidget, findsOneWidget, asked]);
  });
}
