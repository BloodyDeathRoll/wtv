import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:material_ui/material_ui.dart';

import '../../data/epg.dart';
import '../../data/live.dart';
import '../../data/provider_login.dart';
import '../../l10n/app_localizations.dart';
import '../../player/engine.dart';
import '../../services.dart';
import '../components/badges.dart';
import '../components/pressable.dart';
import '../live/number_entry.dart';
import '../theme.dart';
import 'player_screen.dart' show clock;

/// Live TV, full screen, like a TV box: Left and Right (and a keyboard's
/// channel keys) change channel within `channels`, wrapping at the ends; a
/// channel number typed on the number keys goes to that channel. The banner
/// (number, logo, name, and what is on now and next from the provider's short
/// guide) shows for [bannerFor] on every change; on a radio channel it stays.
/// Enter opens the channel list, Down what is on with the channel's guide.
/// Back leaves. Nothing is saved.
///
/// Catch-up, on channels that keep an archive: Up opens the earlier
/// programmes; one chosen plays from its start in place of the live picture.
/// Then Left and Right (and the rewind and fast-forward keys) move
/// [catchupStep], or [catchupHeldStep] a step while held; Enter pauses or
/// plays; the banner shows where in the programme it is, and stays while
/// paused. Back (or a channel change) returns to live.
///
/// The mouse: moving it shows the banner, a click on the picture does what
/// Enter does, and the rows of a panel can be clicked.
class LivePlayerScreen extends StatefulWidget {
  const LivePlayerScreen({
    super.key,
    required this.channels,
    required this.start,
    required this.login,
    required this.firstFocus,
    required this.all,
  }) : assert(channels.length > 0, 'A live page needs at least one channel');

  /// The channels Left and Right move through, and the one to start on.
  final List<Channel> channels;
  final int start;
  final ProviderLogin login;
  final FocusNode firstFocus;

  /// Every channel the user can watch, for a number typed that is not in `channels`.
  final List<Channel> all;

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

/// The full-screen panels: earlier programmes (Up), what is on with the guide (Down), the channel list (Enter).
enum _Panel { earlier, guide, channels }

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  final VideoEngine _engine = services.engine;
  // The channels Left and Right move through: the group watched from, or all of them after a number jump outside it.
  late List<Channel> _list = widget.channels;
  late int _index = widget.start.clamp(0, widget.channels.length - 1);
  int? _stream;
  String? _error;
  var _banner = true;
  Timer? _bannerTimer;
  Timer? _stall;
  late final Timer _clock;
  late final Timer _ticker;
  // The channel's guide, read again each time the banner shows: what is on changes.
  var _guide = const <Programme>[];
  int? _guideFor;
  var _guideRun = 0;
  var _now = _nowSecs();
  // The past programme playing instead of live, if any.
  Programme? _catchup;
  _Panel? _panel;
  var _panelList = const <Programme>[];
  var _panelLoading = false;
  var _panelFailed = false;
  var _panelRun = 0;
  // The panel's row that takes the focus: its first, or the channel watched.
  final _panelFocus = FocusNode();
  late final _numbers = NumberEntry(_onNumber);
  var _wasBuffering = false;
  var _wasEnded = false;
  var _wasPaused = false;
  var _downAt = Duration.zero;
  var _lastStepAt = Duration.zero;

  Channel get _channel => _list[_index];

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngine);
    _clock = Timer.periodic(guideTick, (_) => _tick());
    // The time bar moves while it shows.
    _ticker = Timer.periodic(positionTick, (_) {
      if (_banner && _catchup != null) setState(() {});
    });
    _play();
    _showBanner();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    if (_stream case final stream?) _engine.close(stream);
    for (final timer in [_clock, _ticker, _bannerTimer, _stall]) {
      timer?.cancel();
    }
    _numbers.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  /// Opens the channel's stream: the programme chosen from its archive, or live.
  void _play({int startSecs = 0}) {
    final catchup = _catchup;
    final url =
        (catchup == null ? null : timeshiftUrl(widget.login, _channel.extId, catchup)) ??
        streamUrl(widget.login, StreamKind.live, _channel.extId, 'ts');
    _error = null;
    _stall?.cancel();
    _wasBuffering = _wasEnded = _wasPaused = false;
    _stream = _engine.open(url, startSecs: startSecs);
    _onEngine();
  }

  void _onEngine() {
    if (!mounted) return;
    final e = _engine;
    if (e.ended && !_wasEnded) {
      _wasEnded = true;
      if (_catchup != null) {
        // A past programme played to its end: back to live.
        return _toLive();
      }
      // A live stream has no end: the provider closed it.
      _error = _ended;
    }
    _wasEnded = e.ended;
    if (e.failure != null) _error = e.failure;
    if (e.buffering != _wasBuffering) {
      _wasBuffering = e.buffering;
      _stall?.cancel();
      // A stream that never starts shows no error of its own: after a while it counts as failed.
      if (e.buffering) _stall = Timer(stallAfter, () => setState(() => _error = stalled));
    }
    // A stall that ends: the picture is back, so the failed banner goes (after its usual few seconds).
    if (!e.buffering && e.started && _error == stalled) {
      _error = null;
      _showBanner();
    }
    // The banner stays while paused, and goes soon after playing again.
    if (e.paused != _wasPaused) {
      _wasPaused = e.paused;
      _showBanner(read: false);
    }
    setState(() {});
  }

  /// Shows the banner, for [bannerFor]; `read`: with the guide read again.
  void _showBanner({bool read = true}) {
    _bannerTimer?.cancel();
    _banner = true;
    _now = _nowSecs();
    if (!_channel.isRadio && !(_catchup != null && _engine.paused)) {
      _bannerTimer = Timer(bannerFor, () => setState(() => _banner = false));
    }
    if (read) _readGuide();
    if (mounted) setState(() {});
  }

  /// A nicety: without a guide the banner shows the channel only.
  Future<void> _readGuide() async {
    final run = ++_guideRun;
    final channel = _channel;
    if (_guideFor != channel.id) {
      _guide = const [];
      _guideFor = channel.id;
    }
    try {
      final guide = await shortEpg(services.http, widget.login, channel.extId);
      if (mounted && run == _guideRun) setState(() => _guide = guide);
    } on Exception catch (e) {
      debugPrint('No guide for the channel: $e');
    }
  }

  /// The banner's clock: while it is up (on radio it stays), the line and the bar move on.
  void _tick() {
    if (!_banner) return;
    setState(() => _now = _nowSecs());
    // The programme on air ended: the guide is read again for the one after.
    if (_guide.isNotEmpty && nowAndNext(_guide, _now).$1 == null) _readGuide();
  }

  void _move(int step) {
    _catchup = null;
    _index = (_index + step) % _list.length;
    _play();
    _showBanner();
  }

  void _toLive() {
    _catchup = null;
    _play();
    _showBanner();
  }

  void _toggle() {
    _engine.paused ? _engine.play() : _engine.pause();
    _showBanner();
  }

  /// A number typed goes to that channel, from wherever the screen is.
  bool _onNumber(int number) {
    final found = channelByNumber(number, _list, widget.all);
    if (found == null) return false;
    final (list, index) = found;
    // The same channel keeps its programme.
    final same = list[index].id == _channel.id;
    _closePanel();
    _list = list;
    _index = index;
    if (!same) {
      _catchup = null;
      _play();
    }
    _showBanner();
    return true;
  }

  /// Catch-up: back or forward a step, a bigger one once the key has been held [heldAfter]. False when live.
  bool _seek(KeyEvent event, {required bool forward}) {
    if (_catchup == null) return false;
    if (event is KeyUpEvent) return true;
    final now = event.timeStamp;
    if (event is KeyDownEvent) {
      _downAt = now;
    } else if (now - _lastStepAt < catchupStepGap) {
      // A held key repeats many times a second: the steps are spaced out.
      return true;
    }
    _lastStepAt = now;
    final e = _engine;
    final to = nextPosition(e.position, e.length, forward: forward, held: now - _downAt >= heldAfter);
    if (e.failure != null) {
      // After a failed read the stream is closed: a step tries again from the new place.
      _play(startSecs: to.inSeconds);
    } else if (to != e.position) {
      e.seek(to);
    }
    _showBanner();
    return true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_numbers.key(event)) return KeyEventResult.handled;
    // With a panel open, its list has the keys.
    if (_panel != null) return KeyEventResult.ignored;
    final down = event is KeyDownEvent;
    final catchup = _catchup != null;
    final key = event.logicalKey;
    switch (key) {
      case LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowLeft:
        final forward = key == LogicalKeyboardKey.arrowRight;
        // Left and Right change channel; in catch-up they move through the programme.
        // A held key changes channel once: each change opens a stream at the provider.
        if (!_seek(event, forward: forward) && down) _move(forward ? 1 : -1);
      case LogicalKeyboardKey.channelUp || LogicalKeyboardKey.channelDown:
        if (down) _move(key == LogicalKeyboardKey.channelUp ? 1 : -1);
      case LogicalKeyboardKey.arrowUp:
        if (down) _channel.archiveDays > 0 ? _open(_Panel.earlier) : _showBanner();
      case LogicalKeyboardKey.arrowDown:
        if (down) _open(_Panel.guide);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter || LogicalKeyboardKey.select || LogicalKeyboardKey.space:
        if (down) catchup ? _toggle() : _open(_Panel.channels);
      case LogicalKeyboardKey.info || LogicalKeyboardKey.mediaPlayPause:
        if (down) catchup ? _toggle() : _showBanner();
      // The keyboard's own play and pause keys set the state rather than toggle it.
      case LogicalKeyboardKey.mediaPlay || LogicalKeyboardKey.mediaPause:
        if (!catchup) return KeyEventResult.ignored;
        if (down && _engine.paused == (key == LogicalKeyboardKey.mediaPlay)) _toggle();
      case LogicalKeyboardKey.mediaFastForward || LogicalKeyboardKey.mediaRewind:
        if (!_seek(event, forward: key == LogicalKeyboardKey.mediaFastForward)) return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Opens a panel; its list is read now (the channel list is at hand).
  Future<void> _open(_Panel kind) async {
    final run = ++_panelRun;
    final wait = kind != _Panel.channels;
    setState(() {
      _panel = kind;
      _panelList = const [];
      _panelFailed = false;
      // From the first frame, not "nothing to show".
      _panelLoading = wait;
    });
    void focusRow() => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && run == _panelRun && _panelFocus.context != null) _panelFocus.requestFocus();
    });
    if (!wait) return focusRow();
    final http = services.http;
    final id = _channel.extId;
    try {
      final list = kind == _Panel.earlier
          ? await archive(http, widget.login, id, _nowSecs())
          : await shortEpg(http, widget.login, id, limit: guideLimit);
      if (!mounted || run != _panelRun) return;
      setState(() {
        _panelList = list;
        _panelLoading = false;
      });
      focusRow();
    } on Exception {
      if (!mounted || run != _panelRun) return;
      setState(() {
        _panelFailed = true;
        _panelLoading = false;
      });
    }
  }

  void _closePanel() {
    if (_panel == null) return;
    // A list still on its way is dropped.
    _panelRun++;
    setState(() => _panel = null);
    widget.firstFocus.requestFocus();
  }

  /// Back: off the panel, then from catch-up to live, then out.
  void _back() {
    if (_panel != null) {
      _closePanel();
    } else if (_catchup != null) {
      _toLive();
    } else {
      // The app frame's Back, above this page.
      Actions.invoke(context, const DismissIntent());
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    final channel = _channel;
    final catchup = _catchup;
    final error = _error;
    return Actions(
      actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _back())},
      child: Focus(
        focusNode: widget.firstFocus,
        // Not a stop for the arrow keys: in a panel they stay on its rows.
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _banner || _panel != null ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) {
            if (!_banner && _panel == null) _showBanner();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _panel != null ? null : () => catchup != null ? _toggle() : _open(_Panel.channels),
                child: ColoredBox(color: Colors.black, child: e.view()),
              ),
              if (e.buffering && error == null)
                const Center(
                  child: SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(color: WtvColors.textPrimary, strokeWidth: 3),
                  ),
                ),
              // Not under a panel: it would show through.
              if ((_banner || error != null) && _panel == null)
                _Banner(
                  channel,
                  error: error,
                  onAir: catchup != null ? (catchup, null) : nowAndNext(_guide, _now),
                  now: _now,
                  // The stream's own length once known; the guide's until then.
                  place: catchup == null
                      ? null
                      : (position: e.position, length: e.length ?? Duration(seconds: catchup.end - catchup.start), paused: e.paused),
                ),
              switch (_panel) {
                _Panel.earlier => _EarlierPanel(
                  channel,
                  _panelList,
                  loading: _panelLoading,
                  failed: _panelFailed,
                  first: _panelFocus,
                  onPlay: (programme) {
                    _closePanel();
                    _catchup = programme;
                    _play();
                    _showBanner();
                  },
                ),
                _Panel.guide => _GuidePanel(channel, _panelList, playing: catchup, loading: _panelLoading, failed: _panelFailed, first: _panelFocus),
                _Panel.channels => _ChannelsPanel(
                  _list,
                  _index,
                  current: _panelFocus,
                  onPick: (i) {
                    _closePanel();
                    // The same channel keeps its programme.
                    if (i != _index) {
                      _catchup = null;
                      _index = i;
                      _play();
                    }
                    _showBanner();
                  },
                ),
                null => const SizedBox.shrink(),
              },
              NumberOverlay(_numbers),
            ],
          ),
        ),
      ),
    );
  }
}

/// A panel over the whole picture, dark enough to read on but letting the programme show through.
class _FullPanel extends StatelessWidget {
  const _FullPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xD9000000),
    padding: const EdgeInsets.symmetric(horizontal: 96, vertical: 48),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

/// A row of a panel: light when focused, marked when `selected`. `leading` gets the row's text colour.
class _PanelRow extends StatelessWidget {
  const _PanelRow(this.headline, {required this.onPressed, this.leading, this.supporting, this.supportingLines = 1, this.selected = false, this.focusNode});

  final String headline;
  final VoidCallback onPressed;
  final Widget Function(Color color)? leading;
  final String? supporting;
  final int supportingLines;
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    focusNode: focusNode,
    selected: selected,
    builder: (context, focused) {
      final text = Theme.of(context).textTheme;
      final color = focused ? WtvColors.background : WtvColors.textPrimary;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: focused
              ? WtvColors.textPrimary
              : selected
              ? WtvColors.chip
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          spacing: 16,
          children: [
            ?leading?.call(color),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ContentText(headline, style: text.titleMedium!.copyWith(color: color), maxLines: 1),
                  if (supporting != null)
                    ContentText(supporting!, style: text.bodySmall!.copyWith(color: color.withValues(alpha: 0.7)), maxLines: supportingLines),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _note(BuildContext context, String message, {bool muted = false}) =>
    Text(message, style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: muted ? WtvColors.textMuted : WtvColors.textSecondary));

Widget _rows(int count, Widget Function(int i) row) => Expanded(
  child: ListView.separated(
    padding: const EdgeInsets.only(bottom: 40),
    itemCount: count,
    separatorBuilder: (_, _) => const SizedBox(height: 6),
    itemBuilder: (_, i) => row(i),
  ),
);

/// The earlier programmes of a catch-up channel, newest first. Enter plays one; Back closes.
class _EarlierPanel extends StatelessWidget {
  const _EarlierPanel(this.channel, this.programmes, {required this.loading, required this.failed, required this.first, required this.onPlay});

  final Channel channel;
  final List<Programme> programmes;
  final bool loading;
  final bool failed;
  final FocusNode first;
  final ValueChanged<Programme> onPlay;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final day = intl.DateFormat('EEE d.M', Localizations.localeOf(context).toLanguageTag());
    return _FullPanel(
      children: [
        // Title and channel apart: a Hebrew channel name inside an English line comes out in the wrong order.
        Text(l.liveEarlier, style: text.headlineSmall),
        ContentText(channel.name, style: text.titleMedium!.copyWith(color: WtvColors.textSecondary)),
        const SizedBox(height: 16),
        if (failed)
          _note(context, l.liveArchiveFailed)
        else if (loading)
          _note(context, l.loading, muted: true)
        else if (programmes.isEmpty)
          _note(context, l.liveNoArchive)
        else
          _rows(programmes.length, (i) {
            final p = programmes[i];
            return _PanelRow(
              p.title,
              supporting: '${day.format(_local(p.start))}   ${_time(p.start)}–${_time(p.end)}',
              focusNode: i == 0 ? first : null,
              onPressed: () => onPlay(p),
            );
          }),
      ],
    );
  }
}

/// What is on (or the catch-up programme playing) with its description, then the channel's guide after it.
/// Rows take the focus only so the keys can scroll the list.
class _GuidePanel extends StatelessWidget {
  const _GuidePanel(this.channel, this.programmes, {required this.playing, required this.loading, required this.failed, required this.first});

  final Channel channel;
  final List<Programme> programmes;
  final Programme? playing;
  final bool loading;
  final bool failed;
  final FocusNode first;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final (lead, after) = guideOf(programmes, playing, _nowSecs());
    return _FullPanel(
      children: [
        ContentText(channel.name, style: text.titleMedium!.copyWith(color: WtvColors.textSecondary)),
        const SizedBox(height: 12),
        if (lead != null) ...[
          ContentText(lead.title, style: text.headlineMedium, maxLines: 2),
          Text('${_time(lead.start)}–${_time(lead.end)}', style: text.titleMedium!.copyWith(color: WtvColors.accent)),
          if (lead.description case final description?) ...[
            const SizedBox(height: 8),
            ContentText(description, style: text.bodyLarge!.copyWith(color: WtvColors.textSecondary), maxLines: 5),
          ],
          const SizedBox(height: 24),
        ],
        Text(l.liveGuide, style: text.titleLarge),
        const SizedBox(height: 8),
        if (failed)
          _note(context, l.liveGuideFailed)
        else if (loading)
          _note(context, l.loading, muted: true)
        else if (after.isEmpty)
          _note(context, l.liveNoGuide)
        else
          _rows(after.length, (i) {
            final p = after[i];
            return _PanelRow(
              p.title,
              // Time and title apart: a Hebrew title in one line with the time swaps their order.
              leading: (color) => Text(_time(p.start), style: text.titleMedium!.copyWith(color: color)),
              supporting: p.description,
              supportingLines: 2,
              focusNode: i == 0 ? first : null,
              onPressed: () {},
            );
          }),
      ],
    );
  }
}

/// A channel row's height in the list, and the gap under it.
const _channelRow = 56.0;
const _channelGap = 6.0;

/// The channels Left and Right move through, the one watched marked and focused. Enter switches to one; Back closes.
class _ChannelsPanel extends StatefulWidget {
  const _ChannelsPanel(this.channels, this.index, {required this.current, required this.onPick});

  final List<Channel> channels;
  final int index;
  final FocusNode current;
  final ValueChanged<int> onPick;

  @override
  State<_ChannelsPanel> createState() => _ChannelsPanelState();
}

class _ChannelsPanelState extends State<_ChannelsPanel> {
  // Opens with the channel watched a few rows down, so it is built and can take the focus.
  late final _scroll = ScrollController(initialScrollOffset: (widget.index - 3).clamp(0, widget.channels.length) * (_channelRow + _channelGap));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _FullPanel(
      children: [
        Text(AppLocalizations.of(context)!.liveChannels, style: text.headlineSmall),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 40),
            itemExtent: _channelRow + _channelGap,
            itemCount: widget.channels.length,
            itemBuilder: (context, i) {
              final c = widget.channels[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: _channelGap),
                child: _PanelRow(
                  c.name,
                  selected: i == widget.index,
                  focusNode: i == widget.index ? widget.current : null,
                  onPressed: () => widget.onPick(i),
                  leading: (color) => Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      SizedBox(width: 56, child: Text(c.num?.toString() ?? '', style: text.titleMedium!.copyWith(color: color))),
                      SizedBox(
                        width: 64,
                        height: 36,
                        child: c.logo == null
                            ? null
                            : Image.network(c.logo!, fit: BoxFit.contain, excludeFromSemantics: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Where catch-up is in its programme, and whether it is paused.
typedef _Place = ({Duration position, Duration length, bool paused});

/// The channel strip along the bottom: number, logo, name, the error if the channel failed, and what is on.
class _Banner extends StatelessWidget {
  const _Banner(this.channel, {required this.error, required this.onAir, required this.now, required this.place});

  final Channel channel;
  final String? error;
  final (Programme?, Programme?) onAir;
  final int now;
  final _Place? place;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final (onNow, next) = onAir;
    final place = this.place;
    final secondary = WtvColors.textSecondary;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        // Dark enough to read over any picture, channels' own graphics included.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.3, 1],
            colors: [Colors.transparent, Color(0xCC000000), Color(0xF2000000)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(64, 64, 64, 40),
        child: Row(
          spacing: 20,
          children: [
            if (channel.num case final number?) Text('$number', style: text.displaySmall),
            if (channel.logo case final logo?)
              Container(
                width: 120,
                height: 68,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: WtvColors.surface, borderRadius: BorderRadius.circular(6)),
                child: Image.network(logo, fit: BoxFit.contain, excludeFromSemantics: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ContentText(channel.name, style: text.headlineSmall),
                  if (error != null) Text('${l.liveFailed} ($error)', style: text.bodyMedium!.copyWith(color: secondary)),
                  if (place != null)
                    Text(place.paused ? l.liveCatchupPaused : l.liveCatchup, style: text.labelLarge!.copyWith(color: WtvColors.accent)),
                  if (onNow != null) ...[
                    // Times and title apart: in one line, a Hebrew title turns the line right-to-left and swaps the times.
                    Row(
                      spacing: 16,
                      children: [
                        Text('${_time(onNow.start)}–${_time(onNow.end)}', style: text.titleMedium),
                        Flexible(child: ContentText(onNow.title, style: text.titleMedium, maxLines: 1)),
                      ],
                    ),
                    if (place != null)
                      // Left to right in Hebrew too, like a clock.
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 14,
                            children: [
                              Text(clock(place.position), style: text.titleSmall),
                              _bar(440, 4, place.length > Duration.zero ? place.position.inMilliseconds / place.length.inMilliseconds : 0),
                              Text(clock(place.length), style: text.titleSmall!.copyWith(color: secondary)),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _bar(420, 3, (now - onNow.start) / (onNow.end - onNow.start)),
                      ),
                  ],
                  Text(
                    place != null
                        ? l.liveCatchupHint
                        : channel.archiveDays > 0
                        ? l.liveEarlierHint
                        : l.liveGuideHint,
                    style: text.bodySmall!.copyWith(color: WtvColors.textMuted),
                  ),
                  if (next != null)
                    Text(
                      l.liveNext(_time(next.start), next.title),
                      style: text.bodyMedium!.copyWith(color: secondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double width, double height, double done) => SizedBox(
    width: width,
    height: height,
    child: ColoredBox(
      color: WtvColors.surface,
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: done.clamp(0, 1),
        child: const ColoredBox(color: WtvColors.accent, child: SizedBox.expand()),
      ),
    ),
  );
}

/// Where a catch-up step lands: [catchupStep] ([catchupHeldStep] when `held`) back or forward, never before the
/// start, and forward never into the last [catchupEndMargin] (the end returns to live) nor backward from there.
Duration nextPosition(Duration position, Duration? length, {required bool forward, required bool held}) {
  final step = held ? catchupHeldStep : catchupStep;
  if (!forward) return position > step ? position - step : Duration.zero;
  if (length == null) return position + step;
  final end = length > catchupEndMargin ? length - catchupEndMargin : Duration.zero;
  final to = position + step < end ? position + step : end;
  return to > position ? to : position;
}

int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

DateTime _local(int unixSeconds) => DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);

/// "20:00" in the computer's time zone.
String _time(int unixSeconds) => intl.DateFormat('HH:mm').format(_local(unixSeconds));

const bannerFor = Duration(seconds: 4);
const guideTick = Duration(seconds: 30);
const stallAfter = Duration(seconds: 20);

/// What the banner gives as the reason when a stream never started, and when a live stream ended.
const stalled = 'TIMEOUT';
const _ended = 'ENDED';
const catchupStep = Duration(seconds: 30);
const catchupHeldStep = Duration(minutes: 2);

/// A key held this long steps [catchupHeldStep].
const heldAfter = Duration(seconds: 1);

/// While a key is held, at most one step in this time.
const catchupStepGap = Duration(milliseconds: 400);

/// A forward step stops this far before the end: the end returns to live.
const catchupEndMargin = Duration(seconds: 10);
const positionTick = Duration(milliseconds: 500);

/// Programmes asked for the guide panel: the provider's short guide stops at what it has.
const guideLimit = 30;
