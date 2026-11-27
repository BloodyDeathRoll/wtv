import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../player/engine.dart';
import '../../player/subtitles.dart';
import '../../services.dart';
import '../../window.dart';
import '../components/buttons.dart';
import '../components/dialogs.dart';
import '../components/pressable.dart';
import '../components/title_menu.dart';
import '../theme.dart';

/// Full-screen playback of one stream. Back leaves.
///
/// The keys, on the picture: Enter or Space pauses or plays at once. Left and
/// Right move [seekStep]; held, the steps grow the longer the key is held
/// ([scrubTo]), and the picture follows when the key is let go. Down (or Up)
/// goes to the buttons. The keyboard's media keys work too.
///
/// The mouse: moving it shows the controls, a click on the picture pauses or
/// plays, a click on the time bar goes there. The pointer is hidden with the
/// controls.
///
/// The controls look like Live TV's catch-up banner: the title, then a line of
/// the time in, the time bar and the length, then a line of buttons: play or
/// pause, the previous and next episode (`episode` only), subtitles, settings
/// (audio track and speed). They show while paused; while playing they go
/// [hideAfter] after the last key ([buttonsHideAfter] with a button focused,
/// [pointerHideAfter] after the mouse). What has the focus is in the accent
/// colour: a button, or the time bar (with a knob) when the keys are the
/// picture's. The subtitle choice is kept for the next video.
///
/// Starts at `startSecs`. Reports the position (seconds, and the length when
/// known) every [saveEvery] while playing, on pause, at the end, and, with
/// `isFinal`, when the page closes. Nothing is reported before playback has
/// started: a stream that fails must not wipe the saved position.
///
/// `next` names the episode that follows, if any. When the episode ends, an Up
/// next card counts down [upNextSecs] and then calls `onNext`; Enter on it
/// plays at once, Back hides it. Not before the end: there is no way to tell
/// where the credits start. `onPrevious` is null on a series' first episode.
///
/// A stream that stops well before its end was cut: the provider closes a
/// stream when its account opens one too many. That is said, with Close.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    required this.startSecs,
    required this.firstFocus,
    required this.episode,
    required this.next,
    required this.onNext,
    required this.onPrevious,
    required this.onProgress,
    required this.onClose,
  });

  final String url;
  final String title;
  final int startSecs;
  final FocusNode firstFocus;
  final bool episode;
  final String? next;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final void Function(int positionSecs, int? durationSecs, bool isFinal) onProgress;
  final VoidCallback onClose;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final VideoEngine _engine = services.engine;
  late final int _stream;
  late final Future<String?> _savedSubtitles = loadSubtitleChoice();
  late final Timer _saver;
  late final Timer _clock;

  // Playback began at some point: the position is worth saving.
  var _started = false;
  var _wasEnded = false;
  // Left for another episode: the position is saved already.
  var _left = false;
  var _upNext = false;
  late final AppLifecycleListener _lifecycle;
  var _secondsLeft = upNextSecs;
  Timer? _countdown;
  final _overlayButton = FocusNode();

  // The controls: shown, which part has the keys, and a menu open over them.
  var _shown = false;
  var _onButtons = false;
  var _menuOpen = false;
  var _byPointer = false;
  // The last click on the picture: a second one soon after is a double click.
  DateTime? _lastClick;
  Timer? _hide;
  final _playButton = FocusNode();
  // The second on the time line, to draw it again only when it changes.
  var _shownSecond = -1;
  // Where held Left / Right has got to; the player goes there when the key is let go.
  Duration? _scrub;
  var _downAt = Duration.zero;
  var _lastStepAt = Duration.zero;
  Timer? _scrubIdle;

  bool get _failed => _engine.failure != null;

  /// The error and Up next have their own button, and the keys.
  bool get _overlay => _failed || _upNext;

  @override
  void initState() {
    super.initState();
    _stream = _engine.open(widget.url, startSecs: widget.startSecs);
    // As on the TV: a film pauses when the window is hidden (minimised).
    _lifecycle = AppLifecycleListener(onHide: _engine.pause);
    _engine.addListener(_onEngine);
    _saver = Timer.periodic(saveEvery, (_) {
      final e = _engine;
      if (e.started && !e.paused && !e.buffering && !e.ended && !_failed) _save(isFinal: false);
    });
    _clock = Timer.periodic(clockTick, (_) {
      final second = _engine.position.inSeconds + (_engine.length?.inSeconds ?? 0) * 1000000;
      if (_shown && second != _shownSecond) setState(() => _shownSecond = second);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _engine.removeListener(_onEngine);
    if (!_left) _save(isFinal: true);
    // The stream closes with the page. Nothing, if the next episode's has replaced it.
    _engine.close(_stream);
    for (final timer in [_saver, _clock, _countdown, _hide, _scrubIdle]) {
      timer?.cancel();
    }
    _overlayButton.dispose();
    _playButton.dispose();
    super.dispose();
  }

  void _save({required bool isFinal}) {
    if (!_started) return;
    widget.onProgress(_engine.position.inSeconds, _engine.length?.inSeconds, isFinal);
  }

  void _onEngine() {
    if (!mounted) return;
    final e = _engine;
    if (e.started && !_started) {
      _started = true;
      _applySubtitles();
    }
    if (e.ended && !_wasEnded) {
      _save(isFinal: false);
      if (widget.next != null) _startUpNext();
    }
    _wasEnded = e.ended;
    if (_overlay) _focusOverlay();
    setState(() {});
  }

  /// The saved subtitle choice, once the file's tracks are known.
  Future<void> _applySubtitles() async {
    final saved = await _savedSubtitles;
    if (!mounted) return;
    final (change, track) = subtitleFor(_engine.subtitleTracks, saved);
    if (change) _engine.setSubtitleTrack(track);
  }

  void _focusOverlay() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _overlay && _overlayButton.context != null && !_overlayButton.hasFocus) _overlayButton.requestFocus();
  });

  void _startUpNext() {
    _upNext = true;
    _secondsLeft = upNextSecs;
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        _goNext();
      }
    });
  }

  /// Another episode takes this page's place: the position is saved first, as the page will not be asked again.
  void _leaveFor(VoidCallback other) {
    _countdown?.cancel();
    if (!_left) _save(isFinal: true);
    _left = true;
    other();
  }

  void _goNext() => _leaveFor(widget.onNext);

  void _toPicture() {
    widget.firstFocus.requestFocus();
    _onButtons = false;
  }

  void _toButtons() {
    final built = _shown;
    _poke();
    if (built) return _playButton.requestFocus();
    // The buttons are built with the controls, in the frame that showing them asked for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playButton.context != null) _playButton.requestFocus();
    });
  }

  /// Something was pressed or moved: the controls show, and stay a little longer.
  void _poke({bool pointer = false}) {
    _byPointer = pointer;
    if (!_shown) setState(() => _shown = true);
    _restartHide();
  }

  void _restartHide() {
    _hide?.cancel();
    if (!_shown || _engine.paused || _menuOpen) return;
    final after = _onButtons
        ? buttonsHideAfter
        : _byPointer
        ? pointerHideAfter
        : hideAfter;
    _hide = Timer(after, () {
      if (!mounted) return;
      // The buttons go with the controls: the focus leaves them first.
      if (!_overlay) _toPicture();
      setState(() => _shown = false);
    });
  }

  void _toggle() {
    if (_engine.paused) {
      _engine.play();
      // Playing again: the keys are the picture's, so the controls go soon.
      _toPicture();
    } else {
      _engine.pause();
      _save(isFinal: false);
    }
    _poke();
  }

  /// A seek key: each press and repeat is a step; letting go sends the player there.
  void _seekKey(KeyEvent event, {required bool forward}) {
    if (event is KeyUpEvent) return _commit();
    final now = event.timeStamp;
    if (event is KeyDownEvent) {
      _downAt = now;
    } else if (now - _lastStepAt < heldStepGap) {
      // A held key repeats many times a second: the steps are spaced out.
      return;
    }
    _lastStepAt = now;
    setState(() => _scrub = scrubTo(_scrub ?? _engine.position, _engine.length, forward: forward, held: now - _downAt));
    // A key let go somewhere else (a menu opened, the focus moved) still lands.
    _scrubIdle?.cancel();
    _scrubIdle = Timer(scrubIdleAfter, _commit);
    _poke();
  }

  void _commit() {
    _scrubIdle?.cancel();
    final to = _scrub;
    if (to == null || !mounted) return;
    _engine.seek(to);
    setState(() => _scrub = null);
    _restartHide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_overlay) return KeyEventResult.ignored;
    final down = event is KeyDownEvent;
    if (down && _shown) _poke();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight:
        // On the buttons these move between them.
        if (_onButtons) return KeyEventResult.ignored;
        _seekKey(event, forward: event.logicalKey == LogicalKeyboardKey.arrowRight);
      case LogicalKeyboardKey.mediaFastForward || LogicalKeyboardKey.mediaRewind:
        _seekKey(event, forward: event.logicalKey == LogicalKeyboardKey.mediaFastForward);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter || LogicalKeyboardKey.space || LogicalKeyboardKey.select:
        // On a button, Enter is the button's.
        if (_onButtons) return KeyEventResult.ignored;
        if (down) _toggle();
      case LogicalKeyboardKey.mediaPlayPause:
        if (down) _toggle();
      // The keyboard's own play and pause keys set the state rather than toggle it.
      case LogicalKeyboardKey.mediaPlay || LogicalKeyboardKey.mediaPause:
        if (down && _engine.paused == (event.logicalKey == LogicalKeyboardKey.mediaPlay)) _toggle();
      case LogicalKeyboardKey.mediaTrackNext:
        if (down && widget.next != null) _goNext();
      case LogicalKeyboardKey.mediaTrackPrevious:
        if (down && widget.onPrevious != null) _leaveFor(widget.onPrevious!);
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp:
        if (down && !_onButtons) {
          _toButtons();
        } else if (down && event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _toPicture();
          _restartHide();
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Back: off the Up next card, then off the buttons, then out of the player.
  void _back() {
    if (_upNext && !_failed) {
      _countdown?.cancel();
      setState(() => _upNext = false);
      _toPicture();
    } else if (_onButtons && !_overlay) {
      _toPicture();
      _restartHide();
    } else {
      // The app frame's Back, above this page.
      Actions.invoke(context, const DismissIntent());
    }
  }

  Future<void> _menu(List<(String, List<_Choice>)> sections) async {
    _menuOpen = true;
    _restartHide();
    await showDialog<void>(context: context, builder: (_) => _ChoiceMenu(sections.where((s) => s.$2.isNotEmpty).toList()));
    _menuOpen = false;
    if (mounted) _poke();
  }

  void _pickSubtitle(MediaTrack? track) {
    _engine.setSubtitleTrack(track?.id);
    // Only a choice the viewer made is kept: not a file's own default.
    saveSubtitleChoice(subtitleChoice(track));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final e = _engine;
    final failure = e.failure;
    return Actions(
      actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _back())},
      child: Focus(
        focusNode: widget.firstFocus,
        // Not a stop for the arrow keys: Right on the last button stays there instead of falling to the picture.
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _shown || _overlay ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _poke(pointer: true),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Not onDoubleTap: it would hold every single click back until the double-click time is up.
                onTap: _overlay
                    ? null
                    : () {
                        _toPicture();
                        _toggle();
                        final now = DateTime.now();
                        final last = _lastClick;
                        if (last != null && now.difference(last) < kDoubleTapTimeout) {
                          // The second click undid the first's pause.
                          toggleFullScreen();
                          _lastClick = null;
                        } else {
                          _lastClick = now;
                        }
                      },
                child: ColoredBox(color: Colors.black, child: e.view()),
              ),
              if (e.buffering && !_overlay)
                const Center(
                  child: SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(color: WtvColors.textPrimary, strokeWidth: 3),
                  ),
                ),
              if (_shown && !_overlay)
                _Controls(
                  title: widget.title,
                  paused: e.paused,
                  position: _scrub ?? e.position,
                  length: e.length ?? Duration.zero,
                  barFocused: !_onButtons,
                  playButton: _playButton,
                  onFocus: (focused) {
                    if (focused == _onButtons) return;
                    setState(() => _onButtons = focused);
                    _restartHide();
                  },
                  onToggle: _toggle,
                  onSeek: (share) {
                    final length = e.length;
                    if (length == null) return;
                    e.seek(length * share);
                    _poke(pointer: true);
                  },
                  episode: widget.episode,
                  onPrevious: widget.onPrevious == null ? null : () => _leaveFor(widget.onPrevious!),
                  onNext: widget.next == null ? null : _goNext,
                  onSubtitles: e.subtitleTracks.isEmpty
                      ? null
                      : () => _menu([
                          (
                            l.playerSubtitles,
                            [
                              _Choice(l.playerSubtitlesOff, e.subtitleTrack == null, () => _pickSubtitle(null)),
                              for (final t in e.subtitleTracks) _Choice(t.label, t.id == e.subtitleTrack, () => _pickSubtitle(t)),
                            ],
                          ),
                        ]),
                  onSettings: () => _menu([
                    (
                      l.playerAudio,
                      [for (final t in e.audioTracks) _Choice(t.label, t.id == e.audioTrack, () => e.setAudioTrack(t.id))],
                    ),
                    (l.playerSpeed, [for (final s in speeds) _Choice('$s×', s == e.speed, () => e.setSpeed(s))]),
                  ]),
                ),
              if (_upNext && !_failed)
                Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: Container(
                    margin: const EdgeInsets.all(48),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: WtvColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.upNext, style: text.labelLarge!.copyWith(color: WtvColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(widget.next!, style: text.titleMedium),
                        const SizedBox(height: 16),
                        ActionButton(label: l.playNextIn(_secondsLeft), focusNode: _overlayButton, onPressed: _goNext),
                      ],
                    ),
                  ),
                ),
              if (_failed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title, style: text.headlineMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(
                          l.playFailed(failure!),
                          style: text.bodyLarge!.copyWith(color: WtvColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ActionButton(label: l.close, focusNode: _overlayButton, onPressed: widget.onClose),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The controls along the bottom, like Live TV's catch-up banner; the lines are left to right in Hebrew too, like a clock.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.title,
    required this.paused,
    required this.position,
    required this.length,
    required this.barFocused,
    required this.playButton,
    required this.onFocus,
    required this.onToggle,
    required this.onSeek,
    required this.episode,
    required this.onPrevious,
    required this.onNext,
    required this.onSubtitles,
    required this.onSettings,
  });

  final String title;
  final bool paused;
  final Duration position;
  final Duration length;
  final bool barFocused;
  final FocusNode playButton;
  final ValueChanged<bool> onFocus;
  final VoidCallback onToggle;

  /// A click on the time bar, as a share of its width.
  final ValueChanged<double> onSeek;
  final bool episode;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSubtitles;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final done = length > Duration.zero ? (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        // Dark enough to read over any picture.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.3, 1],
            colors: [Colors.transparent, Color(0xCC000000), Color(0xF2000000)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(64, 64, 64, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (paused) Text(l.liveCatchupPaused, style: text.labelLarge!.copyWith(color: WtvColors.accent)),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    spacing: 14,
                    children: [
                      Text(clock(position), style: text.titleSmall),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (tap) => onSeek((tap.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                            // Taller than the line, for the mouse.
                            child: SizedBox(
                              height: 20,
                              child: CustomPaint(painter: _BarPainter(done, knob: barFocused)),
                            ),
                          ),
                        ),
                      ),
                      Text(clock(length), style: text.titleSmall!.copyWith(color: WtvColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: onFocus,
                    child: Row(
                      spacing: 14,
                      children: [
                        _ControlButton(
                          paused ? Icons.play_arrow : Icons.pause,
                          paused ? l.play : l.playerPause,
                          onToggle,
                          focusNode: playButton,
                        ),
                        if (episode) ...[
                          _ControlButton(Icons.skip_previous, l.playerPrevious, onPrevious),
                          _ControlButton(Icons.skip_next, l.playerNext, onNext),
                        ],
                        _ControlButton(Icons.closed_caption, l.playerSubtitles, onSubtitles),
                        _ControlButton(Icons.settings, l.railSettings, onSettings),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The time bar: the part played in the accent colour, with a knob when Left and Right move through the video.
class _BarPainter extends CustomPainter {
  const _BarPainter(this.done, {required this.knob});

  final double done;
  final bool knob;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()..strokeWidth = 4;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line..color = WtvColors.surface);
    canvas.drawLine(Offset(0, y), Offset(size.width * done, y), line..color = WtvColors.accent);
    if (knob) canvas.drawCircle(Offset(size.width * done, y), 9, Paint()..color = WtvColors.accent);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.done != done || old.knob != knob;
}

/// A round button of the controls, in the accent colour when focused; with no `onPressed` it is greyed and skipped.
class _ControlButton extends StatelessWidget {
  const _ControlButton(this.icon, this.label, this.onPressed, {this.focusNode});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  Widget _circle(bool focused, Color color) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(color: focused ? WtvColors.accent : null, shape: BoxShape.circle),
    child: Icon(icon, size: 24, color: color, semanticLabel: onPressed == null ? label : null),
  );

  @override
  Widget build(BuildContext context) {
    final onPressed = this.onPressed;
    // Not a button at all: a greyed one would still take the focus.
    if (onPressed == null) return _circle(false, WtvColors.textMuted.withValues(alpha: 0.5));
    return Pressable(
      onPressed: onPressed,
      focusNode: focusNode,
      semanticLabel: label,
      builder: (context, focused) => _circle(focused, focused ? Colors.black : WtvColors.textPrimary),
    );
  }
}

/// A row of a player menu: `pick` chooses it.
class _Choice {
  const _Choice(this.label, this.selected, this.pick);

  final String label;
  final bool selected;
  final VoidCallback pick;
}

/// Lists to choose one row from, each under its heading; the chosen row is marked and has the focus.
/// Enter chooses and closes; Back closes.
class _ChoiceMenu extends StatelessWidget {
  const _ChoiceMenu(this.sections);

  final List<(String, List<_Choice>)> sections;

  @override
  Widget build(BuildContext context) {
    final all = [for (final (_, choices) in sections) ...choices];
    final focused = all.where((c) => c.selected).firstOrNull ?? all.firstOrNull;
    return Panel(
      width: 440,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                for (final (heading, choices) in sections) ...[
                  Text(heading, style: Theme.of(context).textTheme.titleLarge),
                  for (final c in choices)
                    MenuItem(c.selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, c.label, () {
                      c.pick();
                      Navigator.pop(context);
                    }, autofocus: c == focused),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Where a Left / Right step lands: [seekStep] on a press; on a held key the step doubles with each
/// second held, up to [seekMax]. Never before the start, and forward never into the last
/// [endMargin] (the end starts the next episode) nor backward from there.
Duration scrubTo(Duration position, Duration? length, {required bool forward, required Duration held}) {
  final doublings = (held.inMilliseconds ~/ 1000).clamp(0, 10);
  final grown = seekStep * (1 << doublings);
  final step = grown < seekMax ? grown : seekMax;
  if (!forward) return position > step ? position - step : Duration.zero;
  if (length == null) return position + step;
  final end = length > endMargin ? length - endMargin : Duration.zero;
  final to = position + step < end ? position + step : end;
  return to > position ? to : position;
}

/// A time on the time line: 1:02:03, or 2:03 under an hour.
String clock(Duration time) {
  final s = time.isNegative ? 0 : time.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}' : '${s ~/ 60}:${two(s % 60)}';
}

const saveEvery = Duration(seconds: 15);
const upNextSecs = 10;

/// While playing, the controls go this long after the last key.
const hideAfter = Duration(milliseconds: 800);

/// With a button focused they stay longer: time to read and choose.
const buttonsHideAfter = Duration(seconds: 5);

/// After the mouse moved they stay long enough to reach a button.
const pointerHideAfter = Duration(seconds: 3);
const seekStep = Duration(seconds: 10);
const seekMax = Duration(minutes: 5);

/// While a key is held, at most one step in this time.
const heldStepGap = Duration(milliseconds: 150);

/// No step for this long: the player goes to where the steps got to.
const scrubIdleAfter = Duration(milliseconds: 600);
const endMargin = Duration(seconds: 5);

const clockTick = Duration(milliseconds: 250);
const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
