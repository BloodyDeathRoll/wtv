import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wtv/data/provider_login.dart';
import 'package:wtv/l10n/app_localizations.dart';
import 'package:wtv/player/engine.dart';
import 'package:wtv/player/subtitles.dart';
import 'package:wtv/services.dart';
import 'package:wtv/ui/components/buttons.dart';
import 'package:wtv/ui/components/cards.dart';
import 'package:wtv/ui/components/pressable.dart';
import 'package:wtv/ui/components/side_rail.dart';
import 'package:wtv/ui/components/title_menu.dart';
import 'package:wtv/ui/player/player_screen.dart';
import 'package:wtv/ui/settings/settings_screen.dart';
import 'package:wtv/ui/title/title_screen.dart';

import 'fakes.dart';
import 'title_test.dart' show episodeRow, row, saved;

const _minute = Duration(minutes: 1);
const _second = Duration(seconds: 1);

/// The film and episode player: the engine it drives, its keys and mouse, the saved position, the next episode.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('the rules', () {
    test('a step is 10 s; held, it doubles each second up to 5 min; it stays inside the video', () {
      const length = Duration(hours: 1);
      Duration to(Duration from, {bool forward = true, int heldMs = 0, Duration? of = length}) =>
          scrubTo(from, of, forward: forward, held: Duration(milliseconds: heldMs));
      expect(to(_minute), const Duration(seconds: 70));
      expect(to(_minute, forward: false, heldMs: 999), const Duration(seconds: 50));
      expect(to(_minute, heldMs: 1000), const Duration(seconds: 80));
      expect(to(_minute, heldMs: 3000), const Duration(seconds: 140));
      expect(to(_minute, heldMs: 5000), const Duration(minutes: 6));
      expect(to(_minute, heldMs: 600000), const Duration(minutes: 6));
      expect(to(const Duration(seconds: 4), forward: false), Duration.zero);
      // Not into the last 5 s (the end starts the next episode), and not back from there.
      expect(to(length - const Duration(seconds: 8)), length - const Duration(seconds: 5));
      expect(to(length - const Duration(seconds: 2)), length - const Duration(seconds: 2));
      expect(to(_minute, of: null), const Duration(seconds: 70));
    });

    test('the time line shows hours only when there are any', () {
      expect([clock(Duration.zero), clock(const Duration(seconds: 125)), clock(const Duration(seconds: 3723)), clock(-_second)], [
        '0:00',
        '2:05',
        '1:02:03',
        '0:00',
      ]);
    });

    test('why a stream did not open is the HTTP status, never the message: it quotes the address', () {
      const address = 'https://tv.example.com/movie/me/secret/1.mkv';
      expect(failureReason(['https: HTTP error 403 Forbidden', 'Failed to open $address.']), 'HTTP 403');
      expect(failureReason(['HTTP error 404 Not Found', 'HTTP error 509 Bandwidth Limit Exceeded']), 'HTTP 509');
      expect(failureReason(['Failed to open $address.']), 'no stream');
      expect(failureReason(const []), 'no stream');
    });

    test('a track is named by its language tag, its title and its channels', () {
      expect(trackLabel(1, language: 'heb'), 'HEB');
      expect(trackLabel(2, language: 'eng', title: ' Commentary ', channels: 2), 'ENG · Commentary · 2.0');
      expect(trackLabel(3, channels: 6), 'Track 3 · 5.1');
      expect(trackLabel(4, language: 'und', channels: 3), 'Track 4 · 3 ch');
    });

    test('the saved subtitle choice: off, a language (or the untagged track in its place), else the file\'s own', () {
      const hebrew = MediaTrack('2', 'HEB', language: 'heb');
      const english = MediaTrack('3', 'ENG', language: 'eng');
      const untagged = MediaTrack('4', 'Track 3');
      const all = [hebrew, english, untagged];
      expect(subtitleFor(all, null), (false, null));
      expect(subtitleFor(all, subtitlesOff), (true, null));
      expect(subtitleFor(all, 'eng'), (true, '3'));
      expect(subtitleFor(all, 'fre'), (true, '4'));
      expect(subtitleFor(all, subtitlesUntagged), (true, '4'));
      expect(subtitleFor(const [hebrew], 'fre'), (false, null));
      expect(subtitleFor(const [], subtitlesUntagged), (false, null));
      expect([subtitleChoice(null), subtitleChoice(hebrew), subtitleChoice(untagged)], [subtitlesOff, 'heb', subtitlesUntagged]);
    });
  });

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

  /// The control button, or the menu row, that has the focus.
  String? focusedButton() => focusedIn<MenuItem>()?.label ?? focusedIn<ActionButton>()?.label ?? focusedIn<Pressable>()?.semanticLabel;

  group('the screen', () {
    const address = 'https://tv.example.com/movie/me/secret/1.mkv';
    final first = FocusNode();
    // What the page reported: (second, length, final).
    final reports = <(int, int?, bool)>[];
    var nexts = 0;
    var previouses = 0;
    var closes = 0;
    // The app frame's Back, reached only when the player has nothing of its own to go back from.
    var backs = 0;
    setUp(() {
      reports.clear();
      nexts = previouses = closes = backs = 0;
    });
    tearDownAll(first.dispose);

    Future<void> show(WidgetTester tester, {int startSecs = 0, bool episode = false, String? next, bool previous = false}) async {
      await showScreen(
        tester,
        Actions(
          actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => backs++)},
          child: FocusScope(
            key: UniqueKey(),
            child: PlayerScreen(
              url: address,
              title: 'Movie one',
              startSecs: startSecs,
              firstFocus: first,
              episode: episode,
              next: next,
              onNext: () => nexts++,
              onPrevious: previous ? () => previouses++ : null,
              onProgress: (position, length, isFinal) => reports.add((position, length, isFinal)),
              onClose: () => closes++,
            ),
          ),
        ),
      );
      first.requestFocus();
      await tester.pump();
    }

    /// The page goes, as when the app frame closes it.
    Future<void> leave(WidgetTester tester) => tester.pumpWidget(const SizedBox());

    bool controlsShown() => find.text('Movie one').evaluate().isNotEmpty;

    testWidgets('the position is saved every 15 s while playing, on pause and at the close; never before playback starts', (tester) async {
      await show(tester, startSecs: 90);
      expect(engine.opened, [(address, 90)]);
      await tester.pump(saveEvery + _second);
      expect(reports, isEmpty);

      engine.plays(length: _minute * 100, at: const Duration(seconds: 95));
      await tester.pump(saveEvery);
      expect(reports, [(95, 6000, false)]);
      // Not while it waits for data.
      engine.now((e) => e.buffering = true);
      await tester.pump(saveEvery);
      expect(reports.length, 1);
      engine.now((e) {
        e.buffering = false;
        e.position = const Duration(seconds: 97);
      });

      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.paused, isTrue);
      expect(reports.last, (97, 6000, false));
      // Paused: the controls stay, and nothing more is saved.
      await tester.pump(saveEvery * 2);
      expect(find.text(en.liveCatchupPaused), findsOneWidget);
      expect(reports.length, 2);

      await leave(tester);
      expect(reports.last, (97, 6000, true));
      expect([engine.closed, engine.stream], [
        [1],
        null,
      ]);
    });

    testWidgets('a stream that never played saves nothing, so the saved position stays', (tester) async {
      await show(tester, startSecs: 90);
      await leave(tester);
      expect(reports, isEmpty);
      expect(engine.closed, [1]);
    });

    testWidgets('the keys: Left and Right step, Enter and Space pause, Down goes to the buttons, Back comes off them first', (tester) async {
      await show(tester);
      engine.plays(length: _minute * 100, at: _minute);
      await tester.pump();
      expect(controlsShown(), isFalse);

      // A step shows the controls; the player goes there when the key is let go.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect([find.text('1:10'), find.text('1:40:00')], [findsOneWidget, findsOneWidget]);
      expect(engine.seeks, isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(engine.seeks, [const Duration(seconds: 70)]);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(engine.seeks.last, _minute);
      // They go soon after the last key.
      await tester.pump(hideAfter + _second);
      expect(controlsShown(), isFalse);

      await press(tester, LogicalKeyboardKey.space);
      expect((engine.paused, controlsShown()), (true, true));
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.paused, isFalse);

      // The buttons: Pause, then Settings (subtitles are greyed with no track, and skipped). They stay longer.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedButton(), en.playerPause);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedButton(), en.railSettings);
      // Right on the last button stays on it: the keys do not fall back to the picture's.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedButton(), en.railSettings);
      expect(engine.seeks.length, 2);
      await tester.pump(buttonsHideAfter - _second);
      expect(controlsShown(), isTrue);
      // Enter is the button's. Left on the first button stays on it.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(engine.seeks.length, 2);
      await press(tester, LogicalKeyboardKey.enter);
      expect((engine.paused, focusedButton()), (true, en.play));

      // Back comes off the buttons, then leaves.
      await press(tester, LogicalKeyboardKey.escape);
      expect((first.hasPrimaryFocus, backs), (true, 0));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(first.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.escape);
      expect(backs, 1);

      // Left alone on the buttons while playing, the controls go and the keys are the picture's again.
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedButton(), en.playerPause);
      await tester.pump(buttonsHideAfter + _second);
      expect((controlsShown(), first.hasPrimaryFocus), (false, true));
    });

    testWidgets('the keyboard\'s media keys: play and pause set the state, the others act as the buttons', (tester) async {
      await show(tester, episode: true, next: 'S1 E3', previous: true);
      engine.plays(length: _minute * 20, at: _minute);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.mediaPlay);
      expect(engine.paused, isFalse);
      await press(tester, LogicalKeyboardKey.mediaPause, times: 2);
      expect(engine.paused, isTrue);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(engine.paused, isFalse);
      await press(tester, LogicalKeyboardKey.mediaFastForward);
      expect(engine.seeks, [const Duration(seconds: 70)]);
      await press(tester, LogicalKeyboardKey.mediaTrackPrevious);
      await press(tester, LogicalKeyboardKey.mediaTrackNext);
      expect((previouses, nexts), (1, 1));
    });

    testWidgets('the mouse: moving it shows the controls, a click on the picture pauses, a click on the time bar goes there', (tester) async {
      await show(tester);
      engine.plays(length: _minute * 100);
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(400, 200));
      await mouse.moveTo(const Offset(420, 220));
      await tester.pump();
      expect(controlsShown(), isTrue);
      await tester.pump(pointerHideAfter - _second);
      expect(controlsShown(), isTrue);
      await tester.pump(_second * 2);
      expect(controlsShown(), isFalse);

      await tester.tapAt(const Offset(400, 200));
      await tester.pump();
      expect((engine.paused, controlsShown()), (true, true));

      // The middle of the bar, between the two times.
      final from = tester.getTopRight(find.text('0:00'));
      final to = tester.getBottomLeft(find.text('1:40:00'));
      await tester.tapAt(Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2));
      await tester.pump();
      expect(engine.seeks.single, _minute * 50);
      // A pointer on a button gives it the focus.
      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel(en.railSettings)));
      await tester.pump();
      expect(focusedButton(), en.railSettings);
    });

    testWidgets('a double click on the picture toggles full screen and leaves the film playing', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('wtv/window'), (call) async {
        calls.add(call.method);
        return null;
      });
      await show(tester);
      engine.plays(length: _minute * 100);
      await tester.pump();
      await tester.tapAt(const Offset(400, 200));
      await tester.tapAt(const Offset(400, 200));
      await tester.pump();
      expect((calls.length, engine.paused), (1, false));
      // A third click is a single one again: it pauses.
      await tester.tapAt(const Offset(400, 200));
      await tester.pump();
      expect((calls.length, engine.paused), (1, true));
      await leave(tester);
    });

    testWidgets('an episode: the previous and next buttons; with no previous episode that button is greyed', (tester) async {
      await show(tester, episode: true, next: 'S1 E3 · Third', previous: true);
      engine.plays(length: _minute * 20, at: _minute);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedButton(), en.playerPrevious);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedButton(), en.playerNext);
      await press(tester, LogicalKeyboardKey.enter);
      // The position is saved before the next episode takes the page, and not again when the page goes.
      expect(nexts, 1);
      expect(reports, [(60, 1200, true)]);
      await leave(tester);
      expect(reports.length, 1);

      await show(tester, episode: true, next: null);
      engine.plays(length: _minute * 20, at: _minute);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedButton(), en.railSettings);
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    });

    testWidgets('an episode that ends: Up next counts down and plays; Back hides it; Enter plays at once', (tester) async {
      await show(tester, episode: true, next: 'S1 E3 · Third');
      engine.plays(length: _minute * 20, at: _minute * 20 - _second);
      await tester.pump();
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      expect([find.text(en.upNext), find.text('S1 E3 · Third')], [findsOneWidget, findsOneWidget]);
      expect(focusedButton(), en.playNextIn(10));
      expect(reports, [(1199, 1200, false)]);
      await tester.pump(_second * 3);
      expect(focusedButton(), en.playNextIn(7));
      await press(tester, LogicalKeyboardKey.escape);
      expect([find.text(en.upNext), first.hasPrimaryFocus, backs], [findsNothing, true, 0]);
      await tester.pump(_second * 20);
      expect(nexts, 0);

      await show(tester, episode: true, next: 'S1 E3 · Third');
      engine.plays(length: _minute * 20, at: _minute * 20);
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      await tester.pump(_second * 9);
      expect(nexts, 0);
      await tester.pump(_second);
      expect((nexts, reports.last), (1, (1200, 1200, true)));
      await leave(tester);

      await show(tester, episode: true, next: 'S1 E3 · Third');
      engine.plays(length: _minute * 20, at: _minute * 20);
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter);
      expect(nexts, 2);
      // The last episode, or a film: the end is just the end.
      await show(tester);
      engine.plays(length: _minute * 20, at: _minute * 20);
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      expect(find.text(en.upNext), findsNothing);
    });

    testWidgets('a stream that stops well before its end is the end, as on the TV: the position is saved, Up next shows', (tester) async {
      await show(tester, episode: true, next: 'S1 E3');
      engine.plays(length: _minute * 100, at: _minute * 30);
      await tester.pump();
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      expect(find.text(en.upNext), findsOneWidget);
      expect(reports, [(1800, 6000, false)]);
    });

    testWidgets('the film pauses when the window is hidden, as on the TV', (tester) async {
      await show(tester);
      engine.plays(length: _minute * 100, at: _minute * 30);
      await tester.pump();
      expect(engine.paused, isFalse);
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(engine.paused, isTrue);
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(engine.paused, isTrue);
    });

    testWidgets('a stream that does not open says why, with Close; nothing is saved', (tester) async {
      await show(tester, startSecs: 90);
      engine.now((e) => e.failure = 'HTTP 403');
      await tester.pumpAndSettle();
      expect(find.text(en.playFailed('HTTP 403')), findsOneWidget);
      expect(focusedButton(), en.close);
      await press(tester, LogicalKeyboardKey.enter);
      expect(closes, 1);
      await leave(tester);
      expect(reports, isEmpty);
    });

    group('subtitles', () {
      const tracks = [MediaTrack('2', 'HEB', language: 'heb'), MediaTrack('3', 'ENG', language: 'eng'), MediaTrack('4', 'Track 3')];

      /// A film whose own default is the English track.
      Future<void> start(WidgetTester tester, {String? saved}) async {
        await show(tester);
        SharedPreferences.setMockInitialValues({'subtitles': ?saved});
        engine.now((e) {
          e.subtitleTracks = tracks;
          e.subtitleTrack = '3';
        });
        engine.plays(length: _minute * 100);
        await tester.pumpAndSettle();
      }

      testWidgets('the saved choice is applied when the film starts', (tester) async {
        await start(tester);
        expect(engine.subtitleTrack, '3');
        await start(tester, saved: subtitlesOff);
        expect(engine.subtitleTrack, isNull);
        await start(tester, saved: 'heb');
        expect(engine.subtitleTrack, '2');
        // A language this film does not have: its untagged track.
        await start(tester, saved: 'fre');
        expect(engine.subtitleTrack, '4');
      });

      testWidgets('the menu: Off and the tracks, the one showing marked and focused; a pick is kept for the next video', (tester) async {
        Future<String?> kept() async => (await SharedPreferences.getInstance()).getString('subtitles');
        Future<void> openMenu() async {
          await press(tester, LogicalKeyboardKey.arrowDown);
          await press(tester, LogicalKeyboardKey.arrowRight);
          expect(focusedButton(), en.playerSubtitles);
          await press(tester, LogicalKeyboardKey.enter);
        }

        await start(tester);
        await openMenu();
        expect([for (final item in tester.widgetList<MenuItem>(find.byType(MenuItem))) item.label], [en.playerSubtitlesOff, 'HEB', 'ENG', 'Track 3']);
        expect(focusedButton(), 'ENG');
        expect(tester.widget<MenuItem>(find.widgetWithText(MenuItem, 'ENG')).icon, Icons.radio_button_checked);
        // The file's own default was not a choice: nothing is kept yet.
        expect(await kept(), isNull);
        // While the menu is open the controls stay.
        await tester.pump(buttonsHideAfter * 2);
        expect(find.text('Movie one'), findsOneWidget);

        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.enter);
        expect((engine.subtitleTrack, await kept()), ('2', 'heb'));
        expect([find.byType(MenuItem), focusedButton()], [findsNothing, en.playerSubtitles]);

        await press(tester, LogicalKeyboardKey.enter);
        await click(tester, find.text('Track 3'));
        expect((engine.subtitleTrack, await kept()), ('4', subtitlesUntagged));
        await press(tester, LogicalKeyboardKey.enter);
        await click(tester, find.text(en.playerSubtitlesOff));
        expect((engine.subtitleTrack, await kept()), (null, subtitlesOff));
        // Back closes the menu and changes nothing.
        await press(tester, LogicalKeyboardKey.enter);
        await press(tester, LogicalKeyboardKey.escape);
        expect([find.byType(MenuItem), engine.subtitleTrack, backs], [findsNothing, null, 0]);
      });
    });

    testWidgets('settings: the audio tracks and the speed', (tester) async {
      await show(tester);
      engine.now((e) {
        e.audioTracks = const [MediaTrack('1', 'ENG · 5.1', language: 'eng'), MediaTrack('2', 'HEB · 2.0', language: 'heb')];
        e.audioTrack = '1';
      });
      engine.plays(length: _minute * 100);
      await tester.pump();
      Future<void> openMenu() async {
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedButton(), en.railSettings);
        await press(tester, LogicalKeyboardKey.enter);
      }

      await openMenu();
      expect([find.text(en.playerAudio), find.text(en.playerSpeed)], [findsOneWidget, findsOneWidget]);
      expect(focusedButton(), 'ENG · 5.1');
      await click(tester, find.text('HEB · 2.0'));
      expect(engine.audioTrack, '2');
      await press(tester, LogicalKeyboardKey.enter);
      expect(tester.widget<MenuItem>(find.widgetWithText(MenuItem, '1.0×')).icon, Icons.radio_button_checked);
      await tester.ensureVisible(find.text('1.5×'));
      await click(tester, find.text('1.5×'));
      expect(engine.speed, 1.5);
    });
  });

  group('in the app', () {
    var positions = <Object?>[];
    setUp(() => positions = []);

    Object? database(String read) {
      if (read.startsWith('progress?')) return positions;
      if (read.startsWith('episodes?')) return [episodeRow(101, 1, 1), episodeRow(102, 1, 2), episodeRow(103, 1, 3, name: 'Third')];
      if (read.startsWith('titles?select=id,ext_id,container_ext,category_ids')) return const [];
      if (read.startsWith('titles?')) return read.contains('kind=eq.movie') ? [row(1, 'Movie one', year: 2020)] : const [];
      return const [];
    }

    String? focusedCard() => focusedIn<ImageCard>()?.title;

    /// Home, with a series under way (its second episode, ten minutes in) and a new movie.
    Future<void> home(WidgetTester tester, {bool login = true}) async {
      positions = [saved(7, 600, duration: 1200, episode: (1, 2))];
      await startApp(tester, rest: database);
      if (login) await services.provider.save(const ProviderLogin('tv.example.com', 'me', 'secret'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), 'Show');
    }

    testWidgets('Play with no provider login opens Settings on the login, and says why', (tester) async {
      await home(tester, login: false);
      await press(tester, LogicalKeyboardKey.enter, times: 2);
      expect([find.byType(SettingsScreen), find.text(en.providerMissing)], [findsOneWidget, findsOneWidget]);
      expect(focusedIn<TextField>(), isNotNull);
      expect([engine.opened, find.byType(PlayerScreen)], [isEmpty, findsNothing]);
    });

    testWidgets('a film plays from the provider, full screen; Back closes the stream and saves the position', (tester) async {
      await home(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedCard(), 'Movie one');
      await press(tester, LogicalKeyboardKey.enter, times: 2);
      expect(engine.opened, [('https://tv.example.com/movie/me/secret/1.mkv', 0)]);
      // The player is the whole screen: no side menu over the video.
      expect([find.byType(PlayerScreen), find.byType(SideRail)], [findsOneWidget, findsNothing]);

      engine.plays(length: _minute * 100, at: _minute * 2);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('Movie one'), findsWidgets);
      writes.clear();
      await press(tester, LogicalKeyboardKey.escape);
      expect([find.byType(PlayerScreen), find.byType(TitleScreen), find.byType(SideRail)], [findsNothing, findsOneWidget, findsOneWidget]);
      expect(engine.stream, isNull);
      expect(writes.single, allOf(startsWith('POST progress?'), contains('"title_id":1'), contains('"episode_id":null'), contains('"position_secs":120')));
    });

    testWidgets('an episode resumes; the next one takes its place on the same stream slot, and Back returns to the series', (tester) async {
      await home(tester);
      await press(tester, LogicalKeyboardKey.enter, times: 2);
      expect(engine.opened, [('https://tv.example.com/series/me/secret/102.mkv', 600)]);
      engine.plays(length: _minute * 20, at: _minute * 20);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('Show · S1 E2'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter);

      writes.clear();
      engine.now((e) => e.ended = true);
      await tester.pumpAndSettle();
      expect(find.text('S1 E3 · Third'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.opened.last, ('https://tv.example.com/series/me/secret/103.mkv', 0));
      // One page, one stream: the engine closed the old one when it opened the new.
      expect([find.byType(PlayerScreen), engine.stream], [findsOneWidget, 2]);
      expect(writes.where((w) => w.contains('"episode_id":102')), isNotEmpty);
      expect(writes.every((w) => w.contains('"title_id":7') && w.contains('"position_secs":1200')), isTrue);

      // The last episode: no next button to press.
      engine.plays(length: _minute * 20, at: _minute);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedButton(), en.playerPrevious);
      await press(tester, LogicalKeyboardKey.enter);
      expect(engine.opened.last, ('https://tv.example.com/series/me/secret/102.mkv', 0));
      await press(tester, LogicalKeyboardKey.escape);
      expect([find.byType(PlayerScreen), find.byType(TitleScreen)], [findsNothing, findsOneWidget]);
      expect(engine.stream, isNull);
    });
  });
}
