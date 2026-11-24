import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'engine.dart';

/// mpv, through `media_kit`.
///
/// Streams are loaded with mpv's own `loadfile`, not the library's `open`:
/// that one writes the address (which holds the provider login) to a file in
/// the temporary folder. `loadfile replace` also closes the open stream before
/// it opens the next. So the library's `playing` and `completed` do not run;
/// this class reads mpv's state itself whenever mpv says something changed.
///
/// Never print a log line or an address from here: both hold the login.
class MpvEngine extends VideoEngine {
  MpvEngine() {
    MediaKit.ensureInitialized();
    _player = Player(
      configuration: const PlayerConfiguration(title: 'WTV', logLevel: MPVLogLevel.warn),
    );
    _controller = VideoController(_player);
    // The library starts its video output after the next frame, and every command waits for that:
    // ask for a frame, so a still screen does not hold the first stream back.
    WidgetsBinding.instance.ensureVisualUpdate();
    _player.stream.position.listen((_) {
      _gotPosition = _opened;
      if (_sought) _seeking = null;
    });
    _player.stream.duration.listen((_) {
      _gotLength = _opened;
      notifyListeners();
    });
    _player.stream.tracks.listen(_onTracks);
    _player.stream.log.listen((log) {
      _messages.add(log.text);
      if (_messages.length > 20) _messages.removeAt(0);
    });
    _work = _setUp();
  }

  late final Player _player;
  late final VideoController _controller;

  NativePlayer get _mpv => _player.platform! as NativePlayer;

  // The engine's commands, one after another.
  late Future<void> _work;

  // The number of the stream wanted now; 0 before the first.
  var _stream = 0;
  // A stream is wanted (opened and not closed).
  var _wanted = false;
  // mpv has taken the stream's address: its state is this stream's from here on.
  var _opened = false;
  String? _url;
  var _start = Duration.zero;
  var _gotPosition = false;
  var _gotLength = false;
  // Where a seek is going, until mpv reports a position after it: the time line does not jump back meanwhile.
  Duration? _seeking;
  var _sought = false;
  var _paused = false;
  var _started = false;
  var _waiting = true;
  var _ended = false;
  String? _failure;
  var _speed = 1.0;
  var _audio = const <MediaTrack>[];
  var _subtitles = const <MediaTrack>[];
  String? _audioTrack;
  String? _subtitleTrack;
  final _messages = <String>[];

  Future<void> _setUp() async {
    for (final (name, value) in const [
      // A file's own default subtitle only: not the first track, not the system's language.
      ('subs-fallback', 'default'),
      ('subs-match-os-language', 'no'),
      // The end does not pause: after a seek back the film plays on.
      ('keep-open-pause', 'no'),
    ]) {
      await _mpv.setProperty(name, value);
    }
    for (final name in const [
      'idle-active',
      'path',
      'core-idle',
      'eof-reached',
      'current-tracks/audio/id',
      'current-tracks/sub/id',
    ]) {
      await _mpv.observeProperty(name, (_) => _sync());
    }
  }

  void _queue(Future<void> Function() command) => _work = _work.then((_) => command()).catchError((Object _) {});

  @override
  int open(String url, {int startSecs = 0}) {
    final stream = ++_stream;
    _wanted = true;
    _opened = false;
    _url = url;
    _start = Duration(seconds: startSecs);
    _gotPosition = _gotLength = false;
    _seeking = null;
    _paused = _started = _ended = false;
    _waiting = true;
    _failure = null;
    // Each video starts at normal speed.
    _speed = 1.0;
    _audio = _subtitles = const [];
    _audioTrack = _subtitleTrack = null;
    _messages.clear();
    _queue(() async {
      // Replaced before its turn came: its stream is never opened.
      if (stream != _stream) return;
      await _mpv.setProperty('start', startSecs > 0 ? '$startSecs' : 'none');
      await _mpv.setProperty('pause', 'no');
      await _mpv.setProperty('speed', '1');
      await _mpv.command(['loadfile', url, 'replace']);
      if (stream != _stream) return;
      // The command has run, and with it every message mpv sent before it: what comes now is this stream's.
      _opened = true;
      await _sync();
    });
    notifyListeners();
    return stream;
  }

  @override
  void close(int stream) {
    if (stream != _stream || !_wanted) return;
    _wanted = _opened = false;
    _queue(() => _mpv.command(['stop']));
    notifyListeners();
  }

  /// Reads mpv's state. mpv only says that something changed; the values are read here, as they are now.
  Future<void> _sync() async {
    if (!_opened) return;
    final stream = _stream;
    final idle = await _mpv.getProperty('idle-active');
    final path = await _mpv.getProperty('path');
    final coreIdle = await _mpv.getProperty('core-idle');
    final end = await _mpv.getProperty('eof-reached');
    final audio = await _mpv.getProperty('current-tracks/audio/id');
    final subtitle = await _mpv.getProperty('current-tracks/sub/id');
    if (stream != _stream || !_opened) return;
    if (idle == 'yes') {
      // No file after the address was taken: it did not open, or it broke.
      _failure ??= failureReason(_messages);
    } else if (path == _url) {
      // Until mpv is on this stream's address, the stream before it may still be closing.
      _ended = end == 'yes';
      _waiting = coreIdle != 'no';
      if (!_waiting) _started = true;
      _audioTrack = audio.isEmpty ? null : audio;
      _subtitleTrack = subtitle.isEmpty ? null : subtitle;
    }
    notifyListeners();
  }

  void _onTracks(Tracks tracks) {
    if (!_opened) return;
    bool real(String id) => id != 'auto' && id != 'no';
    _audio = [
      for (final (i, t) in tracks.audio.where((t) => real(t.id)).indexed)
        MediaTrack(
          t.id,
          trackLabel(i + 1, language: t.language, title: t.title, channels: t.channelscount ?? t.audiochannels),
          language: t.language,
        ),
    ];
    _subtitles = [
      for (final (i, t) in tracks.subtitle.where((t) => real(t.id)).indexed)
        MediaTrack(
          t.id,
          trackLabel(i + 1, language: t.language, title: t.title),
          language: t.language,
        ),
    ];
    _sync();
  }

  @override
  Duration get position => _seeking ?? (_gotPosition ? _player.state.position : _start);

  @override
  Duration? get length => _gotLength && _player.state.duration > Duration.zero ? _player.state.duration : null;

  @override
  bool get paused => _paused;

  @override
  bool get started => _started;

  @override
  bool get buffering => _wanted && _failure == null && !_ended && !_paused && _waiting;

  @override
  bool get ended => _ended;

  @override
  String? get failure => _failure;

  @override
  List<MediaTrack> get audioTracks => _audio;

  @override
  List<MediaTrack> get subtitleTracks => _subtitles;

  @override
  String? get audioTrack => _audioTrack;

  @override
  String? get subtitleTrack => _subtitleTrack;

  @override
  double get speed => _speed;

  void _set(String name, String value) => _queue(() async {
    await _mpv.setProperty(name, value);
    await _sync();
  });

  @override
  void play() {
    _paused = false;
    _set('pause', 'no');
    notifyListeners();
  }

  @override
  void pause() {
    _paused = true;
    _set('pause', 'yes');
    notifyListeners();
  }

  @override
  void seek(Duration to) {
    _seeking = to;
    _sought = false;
    _queue(() async {
      await _mpv.command(['seek', (to.inMilliseconds / 1000).toStringAsFixed(3), 'absolute']);
      _sought = _seeking == to;
    });
  }

  @override
  void setSpeed(double speed) {
    _speed = speed;
    _set('speed', '$speed');
    notifyListeners();
  }

  @override
  void setAudioTrack(String id) => _set('aid', id);

  @override
  void setSubtitleTrack(String? id) => _set('sid', id ?? 'no');

  // shortcut: subtitles are the library's text over the picture, so picture subtitles (PGS, DVD) do not show;
  // switch the library to libass drawing if a title needs them.
  @override
  Widget view() => ExcludeFocus(
    child: IgnorePointer(
      child: Video(controller: _controller, controls: NoVideoControls),
    ),
  );
}
