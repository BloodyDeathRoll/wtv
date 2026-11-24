import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:material_ui/material_ui.dart';
import 'package:wtv/data/live.dart';
import 'package:wtv/data/provider_login.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/ui/components/buttons.dart';
import 'package:wtv/ui/components/cards.dart';
import 'package:wtv/ui/components/chips.dart';
import 'package:wtv/ui/components/side_rail.dart';
import 'package:wtv/ui/components/title_menu.dart';
import 'package:wtv/ui/live/live_screen.dart';
import 'package:wtv/ui/live/number_entry.dart';
import 'package:wtv/ui/player/live_player_screen.dart';
import 'package:wtv/ui/search/search_screen.dart';
import 'package:wtv/ui/settings/settings_screen.dart';

import 'fakes.dart';

Map<String, Object?> _row(int id, String name, {List<int> categories = const [1], int archiveDays = 0}) => {
  'id': id,
  'ext_id': id + 1000,
  'name': name,
  'num': id,
  'logo_url': null,
  'archive_days': archiveDays,
  'is_radio': false,
  'category_ids': categories,
};

// Israel is the provider's first category, so the main group: seven channels, two rows of the grid.
final _channelRows = [
  _row(1, 'Kan 11', archiveDays: 7),
  _row(2, 'Keshet 12'),
  _row(3, 'Reshet 13'),
  for (var id = 4; id <= 7; id++) _row(id, 'Channel $id'),
  _row(21, 'Sport 1', categories: const [30]),
  _row(22, 'Sport 2', categories: const [30]),
];
const _categoryRows = [
  {'ext_id': 1, 'name': 'ישראל', 'name_en': 'Israel', 'name_he': 'ישראל'},
  {'ext_id': 30, 'name': 'ספורט', 'name_en': 'Sports', 'name_he': 'ספורט'},
];

const _kan = Channel(1, 1001, 'Kan 11', 11, null, 7, false, [1]);
const _keshet = Channel(2, 1002, 'Keshet 12', 12, null, 0, false, [1]);
const _reshet = Channel(3, 1003, 'Reshet 13', 13, null, 0, false, [1]);
const _sport = Channel(21, 1021, 'Sport 1', 55, null, 0, false, [30]);
const _radio = Channel(9, 1009, 'Galgalatz', 90, null, 0, true, [1]);

String _live(int streamId) => 'https://tv.example.com/live/me/secret/$streamId.ts';

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String _time(int unixSeconds) => intl.DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));

/// Live TV: the channel page, the full-screen live player with catch-up, and both inside the app.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  /// Types a channel number and waits until it is taken.
  Future<void> type(WidgetTester tester, List<LogicalKeyboardKey> digits) async {
    for (final digit in digits) {
      await tester.sendKeyEvent(digit);
      await tester.pump();
    }
    await tester.pump(numberWait);
    await tester.pumpAndSettle();
  }

  T? focusedIn<T extends Widget>() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<T>();
  String? focusedChip() => focusedIn<OptionChip>()?.label;
  String? focusedCard() => focusedIn<ChannelCard>()?.name;
  String? focusedButton() => focusedIn<MenuItem>()?.label ?? focusedIn<ActionButton>()?.label;
  List<String> cards(WidgetTester tester) => [for (final c in tester.widgetList<ChannelCard>(find.byType(ChannelCard))) c.name];
  List<String> chips(WidgetTester tester) => [for (final c in tester.widgetList<OptionChip>(find.byType(OptionChip))) '${c.label} ${c.detail}'];
  Finder typed(String text) => find.descendant(of: find.byType(NumberOverlay), matching: find.text(text));

  // What the database holds, and whether it answers.
  var favorites = <int>[];
  var channelsDown = false;
  var writesFail = false;
  setUp(() {
    favorites = [];
    channelsDown = writesFail = false;
  });

  Object? database(String read) {
    if (read.startsWith('channels?')) return channelsDown ? http.Response('down', 500) : _channelRows;
    if (read.startsWith('categories?') && read.contains('kind=eq.live')) return _categoryRows;
    if (read.startsWith('channel_prefs?select=channel_id&favorite')) return [for (final id in favorites) {'channel_id': id}];
    if (read.startsWith('POST ') && writesFail) return http.Response('no', 500);
    return const [];
  }

  group('the channel page', () {
    final first = FocusNode();
    // Each channel watched: "the list's ids @ the place in it, of how many channels in all".
    final watched = <String>[];
    setUp(watched.clear);
    tearDownAll(first.dispose);

    Future<void> show(WidgetTester tester, {Guide? guide, bool login = false}) async {
      await showScreen(
        tester,
        FocusScope(
          key: UniqueKey(),
          child: LiveScreen(
            firstFocus: first,
            onWatch: (channels, index, all) => watched.add('${[for (final c in channels) c.id].join(' ')} @ $index, of ${all.length}'),
          ),
        ),
        rest: database,
        guide: guide,
        login: login,
      );
      first.requestFocus();
      await tester.pumpAndSettle();
    }

    testWidgets('a chip per group, Favourites first; the focused chip shows its group, and Up from the cards returns to it', (tester) async {
      favorites = [22];
      await show(tester);
      expect(chips(tester), ['Favourites 1', 'Israel 7', 'Sports 2']);
      expect([focusedChip(), cards(tester)], [
        'Favourites',
        ['Sport 2'],
      ]);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedChip(), 'Israel');
      expect(cards(tester), ['Kan 11', 'Keshet 12', 'Reshet 13', 'Channel 4', 'Channel 5', 'Channel 6', 'Channel 7']);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), 'Kan 11');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), 'Channel 7');

      // Enter watches it, with its group as the channel list.
      await press(tester, LogicalKeyboardKey.enter);
      expect(watched, ['1 2 3 4 5 6 7 @ 6, of 9']);

      // Up from the first row: the shown group's chip, not the nearest one.
      await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
      expect([focusedChip(), cards(tester).length], ['Israel', 7]);

      // A click on a chip shows its group too. (The test font is wide: the chip is past the row's end.)
      await tester.ensureVisible(find.text('Sports'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sports'));
      await tester.pumpAndSettle();
      expect([focusedChip(), cards(tester)], [
        'Sports',
        ['Sport 1', 'Sport 2'],
      ]);
    });

    testWidgets('the menu makes a channel a favourite and back; a save that fails puts the star back', (tester) async {
      await show(tester);
      expect([chips(tester), focusedChip()], [
        ['Israel 7', 'Sports 2'],
        'Israel',
      ]);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(focusedButton(), en.liveMenuFavorite);
      // The main group cannot be hidden.
      expect(find.text(en.liveMenuHideGroup('Israel')), findsNothing);
      await press(tester, LogicalKeyboardKey.enter);
      expect(writes.last, 'POST channel_prefs?on_conflict=user_id,channel_id {"channel_id":1,"favorite":true}');
      expect(chips(tester), ['Favourites 1', 'Israel 7', 'Sports 2']);
      // The group shown stays, and so does the focus.
      expect([focusedCard(), cards(tester).length], ['Kan 11', 7]);
      expect([find.byIcon(Icons.star), find.text(en.liveFavoriteAdded)], [findsOneWidget, findsOneWidget]);
      await tester.pump(messageShort);
      await tester.pump();
      expect(find.text(en.liveFavoriteAdded), findsNothing);

      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(focusedButton(), en.liveMenuUnfavorite);
      await press(tester, LogicalKeyboardKey.enter);
      expect(writes.last, 'POST channel_prefs?on_conflict=user_id,channel_id {"channel_id":1,"favorite":false}');
      expect([chips(tester), find.byIcon(Icons.star)], [
        ['Israel 7', 'Sports 2'],
        findsNothing,
      ]);

      writesFail = true;
      await press(tester, LogicalKeyboardKey.contextMenu);
      await press(tester, LogicalKeyboardKey.enter);
      expect(writes.last, contains('"favorite":true'));
      expect([chips(tester), find.byIcon(Icons.star)], [
        ['Israel 7', 'Sports 2'],
        findsNothing,
      ]);
    });

    testWidgets('the menu hides a channel, and a group that is not the main one; the focus moves to a chip', (tester) async {
      await show(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.contextMenu);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedButton(), en.liveMenuHide);
      await press(tester, LogicalKeyboardKey.enter);
      expect(writes.last, 'POST channel_prefs?on_conflict=user_id,channel_id {"channel_id":1,"hidden":true}');
      expect([chips(tester), cards(tester).first, focusedChip()], [
        ['Israel 6', 'Sports 2'],
        'Keshet 12',
        'Israel',
      ]);
      expect(find.text(en.liveHidden), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), startsWith('Sport '));
      await press(tester, LogicalKeyboardKey.contextMenu);
      await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
      expect(focusedButton(), en.liveMenuHideGroup('Sports'));
      await press(tester, LogicalKeyboardKey.enter);
      expect(writes.last, 'POST live_group_prefs?on_conflict=user_id,category_id {"category_id":30,"hidden":true}');
      expect([chips(tester), focusedChip()], [
        ['Israel 6'],
        'Israel',
      ]);
    });

    testWidgets('a number typed watches that channel, from all the channels; one that no channel has is said', (tester) async {
      await show(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect([typed('2'), watched], [findsOneWidget, isEmpty]);
      await type(tester, [LogicalKeyboardKey.numpad1]);
      expect(watched, ['1 2 3 4 5 6 7 21 22 @ 7, of 9']);
      expect(typed('21'), findsNothing);

      await type(tester, [LogicalKeyboardKey.digit9, LogicalKeyboardKey.digit9]);
      expect([typed(en.liveNoChannel(99)), watched.length], [findsOneWidget, 1]);
      await tester.pump(missingFor);
      await tester.pump();
      expect(typed(en.liveNoChannel(99)), findsNothing);

      // A number still being typed when the page loses the focus is dropped.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(typed('2'), findsOneWidget);
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(typed('2'), findsNothing);
      await tester.pump(numberWait);
      expect(watched.length, 1);
      first.requestFocus();
      await tester.pumpAndSettle();

      // The fourth digit takes the number at once.
      for (final digit in [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4]) {
        await tester.sendKeyEvent(digit);
      }
      await tester.pump();
      expect(typed(en.liveNoChannel(1234)), findsOneWidget);
    });

    testWidgets('each card on screen shows what is on now, asked once; with no provider login nothing is asked', (tester) async {
      final now = _now();
      Object? guide(String action, int id) => id == 1001 ? [programme('News', now - 600, now + 600)] : const <Object?>[];
      await show(tester, guide: guide, login: true);
      expect(guideCalls.toSet(), {for (var id = 1001; id <= 1007; id++) 'get_short_epg $id'});
      expect([guideCalls.length, find.text('News')], [7, findsOneWidget]);

      await show(tester, guide: guide);
      expect([guideCalls, find.text('News'), cards(tester).length], [isEmpty, findsNothing, 7]);
    });

    testWidgets('a failed load says so with Retry, which takes the focus and loads again', (tester) async {
      channelsDown = true;
      await show(tester);
      expect([find.byType(ChannelCard), focusedButton()], [findsNothing, en.retry]);
      channelsDown = false;
      await press(tester, LogicalKeyboardKey.enter);
      expect([focusedChip(), cards(tester).length], ['Israel', 7]);
    });
  });

  group('the live player', () {
    const group = [_kan, _keshet, _reshet];
    const everything = [_kan, _keshet, _reshet, _sport, _radio];
    final first = FocusNode();
    // The app frame's Back, reached only when the player has nothing of its own to go back from.
    var backs = 0;
    setUp(() => backs = 0);
    tearDownAll(first.dispose);

    Future<void> show(WidgetTester tester, {List<Channel> channels = group, int start = 0, Guide? guide}) async {
      await showScreen(
        tester,
        Actions(
          actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => backs++)},
          child: FocusScope(
            key: UniqueKey(),
            child: LivePlayerScreen(
              channels: channels,
              start: start,
              login: const ProviderLogin('tv.example.com', 'me', 'secret'),
              firstFocus: first,
              all: everything,
            ),
          ),
        ),
        guide: guide,
      );
      first.requestFocus();
      await tester.pumpAndSettle();
    }

    /// The texts of the panel row that has the focus.
    List<String> focusedRow() {
      final texts = <String>[];
      void visit(Element e) {
        if (e.widget case Text(:final data?)) texts.add(data);
        e.visitChildren(visit);
      }

      FocusManager.instance.primaryFocus?.context?.visitChildElements(visit);
      return texts;
    }

    Future<void> afterBanner(WidgetTester tester) async {
      await tester.pump(bannerFor);
      await tester.pump();
    }

    test('a catch-up step is 30 s, 2 min when held; it stays inside the programme and off its last 10 s', () {
      const length = Duration(hours: 1);
      const minute = Duration(minutes: 1);
      Duration to(Duration from, {bool forward = true, bool held = false, Duration? of = length}) =>
          nextPosition(from, of, forward: forward, held: held);
      expect(to(minute), const Duration(seconds: 90));
      expect(to(minute * 5, held: true), minute * 7);
      expect(to(minute, forward: false), const Duration(seconds: 30));
      expect(to(minute, forward: false, held: true), Duration.zero);
      expect(to(length - const Duration(seconds: 25)), length - catchupEndMargin);
      expect(to(length - const Duration(seconds: 4)), length - const Duration(seconds: 4));
      expect(to(minute, of: null), const Duration(seconds: 90));
    });

    testWidgets('the channel plays live; the banner shows now and next for a few seconds, and comes back on a key', (tester) async {
      final now = _now();
      await show(tester, guide: (_, _) => [programme('News', now - 600, now + 600), programme('Film', now + 600, now + 4200)]);
      expect(engine.opened, [(_live(1001), 0)]);
      expect(guideCalls, ['get_short_epg 1001']);
      expect(
        [find.text('Kan 11'), find.text('News'), find.text(en.liveNext(_time(now + 600), 'Film')), find.text(en.liveEarlierHint)],
        everyElement(findsOneWidget),
      );
      await afterBanner(tester);
      expect(find.text('Kan 11'), findsNothing);

      // Up on a channel with no archive shows the banner; the guide is read again.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await afterBanner(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect([find.text('Keshet 12'), find.text(en.liveGuideHint)], everyElement(findsOneWidget));
      expect(guideCalls, ['get_short_epg 1001', 'get_short_epg 1002', 'get_short_epg 1002']);

      // Leaving closes the stream.
      await tester.pumpWidget(const SizedBox());
      expect(engine.stream, isNull);
    });

    testWidgets('Left and Right change channel, round the ends; a held key changes once', (tester) async {
      await show(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect([engine.opened.last, find.text('Keshet 12')], [(_live(1002), 0), findsOneWidget]);
      await press(tester, LogicalKeyboardKey.arrowLeft, times: 2);
      expect(engine.opened.last.$1, _live(1003));
      await press(tester, LogicalKeyboardKey.channelUp);
      expect(engine.opened.last.$1, _live(1001));

      final before = engine.opened.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect([engine.opened.length - before, engine.opened.last.$1], [1, _live(1002)]);
    });

    testWidgets('a radio channel keeps its banner', (tester) async {
      await show(tester, channels: const [_radio]);
      await afterBanner(tester);
      expect(find.text('Galgalatz'), findsOneWidget);
    });

    testWidgets('a number typed goes to that channel: in the list, else among all, which Left and Right then move through', (tester) async {
      await show(tester);
      await type(tester, [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit3]);
      expect(engine.opened.last.$1, _live(1003));
      // The channel watched: nothing opens again.
      await type(tester, [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit3]);
      expect(engine.opened.length, 2);

      await type(tester, [LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit5]);
      expect(engine.opened.last.$1, _live(1021));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(engine.opened.last.$1, _live(1009));

      await type(tester, [LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit7]);
      expect([typed(en.liveNoChannel(77)), engine.opened.length], [findsOneWidget, 4]);
    });

    testWidgets('Enter opens the channel list on the one watched; one picked plays; Back closes the list, then leaves', (tester) async {
      await show(tester, start: 1);
      await press(tester, LogicalKeyboardKey.enter);
      // The list is over the whole picture: the banner, still up, makes room.
      expect([find.text(en.liveChannels), find.text(en.liveGuideHint)], [findsOneWidget, findsNothing]);
      expect(focusedRow(), contains('Keshet 12'));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), contains('Reshet 13'));
      await press(tester, LogicalKeyboardKey.enter);
      expect([engine.opened.last.$1, find.text(en.liveChannels)], [_live(1003), findsNothing]);

      // The channel watched, picked again, keeps its stream.
      await press(tester, LogicalKeyboardKey.enter, times: 2);
      expect([engine.opened.length, find.text(en.liveChannels)], [2, findsNothing]);

      // A click on the picture opens the list too; in it Left and Right change nothing.
      await tester.tapAt(const Offset(480, 100));
      await tester.pumpAndSettle();
      expect(find.text(en.liveChannels), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(engine.opened.length, 2);
      await press(tester, LogicalKeyboardKey.escape);
      expect([find.text(en.liveChannels), backs], [findsNothing, 0]);
      await press(tester, LogicalKeyboardKey.escape);
      expect(backs, 1);
    });

    testWidgets('Down shows what is on with its description, and what comes after', (tester) async {
      final now = _now();
      Object? guide(String action, int id) => [
        programme('News', now - 600, now + 600, description: 'The day so far'),
        programme('Film', now + 600, now + 4200),
        programme('Late show', now + 4200, now + 7800),
      ];
      await show(tester, guide: guide);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(guideCalls.last, 'get_short_epg 1001');
      expect([find.text(en.liveGuide), find.text('The day so far'), find.text('Late show')], everyElement(findsOneWidget));
      expect(focusedRow(), contains('Film'));
      await press(tester, LogicalKeyboardKey.escape);
      expect([find.text(en.liveGuide), backs], [findsNothing, 0]);

      // A guide that cannot be read says so.
      await show(tester, guide: (_, _) => http.Response('', 500));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text(en.liveGuideFailed), findsOneWidget);
    });

    testWidgets('catch-up: Up lists the earlier programmes; one plays from its start, steps and pauses; Back or its end returns to live', (
      tester,
    ) async {
      final now = _now();
      Object? guide(String action, int id) => action == 'get_simple_data_table'
          ? [
              programme('Old film', now - 10800, now - 7200, archived: true),
              programme('Morning show', now - 7200, now - 3600, archived: true),
              programme('Not kept', now - 3600, now - 600),
              programme('News', now - 600, now + 600, archived: true),
            ]
          : [programme('News', now - 600, now + 600)];
      await show(tester, guide: guide);
      // The banner, with what is on now, goes first.
      await afterBanner(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(guideCalls.last, 'get_simple_data_table 1001');
      // Newest first; not what is still on, nor what the provider did not keep.
      expect([find.text(en.liveEarlier), find.text('Old film')], everyElement(findsOneWidget));
      expect([find.text('Not kept'), find.text('News')], everyElement(findsNothing));
      expect(focusedRow(), contains('Morning show'));

      await press(tester, LogicalKeyboardKey.enter);
      final start = DateTime.fromMillisecondsSinceEpoch((now - 7200) * 1000, isUtc: true).toIso8601String();
      final shifted = 'https://tv.example.com/timeshift/me/secret/60/${start.substring(0, 10)}:${start.substring(11, 13)}-${start.substring(14, 16)}/1001.ts';
      expect(engine.opened.last, (shifted, 0));
      expect([find.text(en.liveCatchup), find.text('Morning show'), find.text(en.liveCatchupHint)], everyElement(findsOneWidget));

      // Left and Right move through the programme, not the channels.
      engine.plays(length: const Duration(hours: 1), at: const Duration(minutes: 5));
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowLeft, times: 2);
      expect(engine.seeks, [const Duration(seconds: 330), const Duration(minutes: 5), const Duration(seconds: 270)]);
      expect(engine.opened.length, 2);

      // Paused, the banner stays.
      await press(tester, LogicalKeyboardKey.enter);
      expect([engine.paused, find.text(en.liveCatchupPaused)], [isTrue, findsOneWidget]);
      await afterBanner(tester);
      expect(find.text(en.liveCatchupPaused), findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.paused, isFalse);
      await afterBanner(tester);
      expect(find.text('Morning show'), findsNothing);

      await press(tester, LogicalKeyboardKey.escape);
      expect([engine.opened.last, backs], [(_live(1001), 0), 0]);

      // Played to its end: live again.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.opened.last.$1, shifted);
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      expect([engine.opened.last.$1, find.text(en.liveCatchup)], [_live(1001), findsNothing]);
    });

    testWidgets('a channel that fails, never starts or is closed by the provider says so, and why', (tester) async {
      await show(tester);
      engine.now((e) => e.failure = 'HTTP 403');
      await tester.pump();
      expect(find.text('${en.liveFailed} (HTTP 403)'), findsOneWidget);
      // It stays past the banner's time.
      await afterBanner(tester);
      expect(find.text('${en.liveFailed} (HTTP 403)'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.textContaining(en.liveFailed), findsNothing);
      engine.now((e) => e.buffering = true);
      await tester.pump(stallAfter);
      await tester.pump();
      expect(find.text('${en.liveFailed} ($stalled)'), findsOneWidget);
      // The picture comes after all: the message goes.
      engine.now((e) {
        e.buffering = false;
        e.started = true;
      });
      await tester.pump();
      expect(find.textContaining(en.liveFailed), findsNothing);

      engine.now((e) => e.ended = true);
      await tester.pump();
      expect(find.text('${en.liveFailed} (ENDED)'), findsOneWidget);
    });
  });

  group('in the app', () {
    Future<void> liveTab(WidgetTester tester, {bool login = true}) async {
      await startApp(tester, rest: database, login: login);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
      expect(find.byType(LiveScreen), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedChip(), 'Israel');
    }

    testWidgets('a channel with no provider login opens Settings on the login', (tester) async {
      await liveTab(tester, login: false);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);
      expect([find.byType(SettingsScreen), find.text(en.providerMissing)], everyElement(findsOneWidget));
      expect([engine.opened, find.byType(LivePlayerScreen)], [isEmpty, findsNothing]);
    });

    testWidgets('a channel plays full screen with its group as the channel list; Back returns to the page and closes the stream', (tester) async {
      await liveTab(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.opened, [(_live(1002), 0)]);
      // The player is the whole screen: no side menu over the video.
      expect([find.byType(LivePlayerScreen), find.byType(SideRail)], [findsOneWidget, findsNothing]);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(engine.opened.last.$1, _live(1003));
      // A number outside the group: from every channel of the page.
      await type(tester, [LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit2]);
      expect(engine.opened.last.$1, _live(1022));

      await press(tester, LogicalKeyboardKey.escape);
      expect([find.byType(LivePlayerScreen), find.byType(SideRail)], [findsNothing, findsOneWidget]);
      expect([engine.stream, focusedCard()], [isNull, 'Keshet 12']);
    });

    testWidgets('Search on Live TV finds channels, names that start with the text first, and plays the one chosen', (tester) async {
      await liveTab(tester);
      await tester.tap(find.byIcon(Icons.search_outlined));
      await tester.pumpAndSettle();
      expect([find.byType(SearchScreen), find.text(en.searchHintLive)], everyElement(findsOneWidget));
      reads.clear();
      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(typingPause);
      await tester.pumpAndSettle();
      expect(cards(tester), ['Sport 1', 'Sport 2']);
      // Only the channel list was read for it.
      expect(reads, [startsWith('channels?')]);

      // Enter in the field moves on to the channels found.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(focusedCard(), 'Sport 1');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.opened, [(_live(1022), 0)]);
      // Left and Right move through what was found.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(engine.opened.last.$1, _live(1021));
    });
  });
}
