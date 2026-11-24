import 'package:flutter/widgets.dart';

/// An audio or subtitle track of the open stream.
class MediaTrack {
  const MediaTrack(this.id, this.label, {this.language});

  /// The engine's own name for the track.
  final String id;
  final String label;

  /// The language tag as the file carries it; null when the track has none.
  final String? language;
}

/// The video engine as the player screens use it: mpv in the app (`MpvEngine`), a fake in the tests.
///
/// One engine plays one stream at a time. [open] closes the stream that was
/// open before the next one opens, so the app never holds two of the
/// provider's streams. Listeners are told of every change but [position]'s.
abstract class VideoEngine extends ChangeNotifier {
  /// Opens `url` and plays it from `startSecs`. Returns the stream's number, for [close].
  int open(String url, {int startSecs = 0});

  /// Closes stream `stream`. Nothing if a later [open] has replaced it.
  void close(int stream);

  Duration get position;

  /// Null until known, and for a stream with no end.
  Duration? get length;

  bool get paused;

  /// Playback has begun: the stream opened and its first picture or sound played.
  bool get started;

  /// Waiting for data: the stream is opening, or playback has stalled.
  bool get buffering;

  /// The stream ran out: the film's end, or the provider cut it.
  bool get ended;

  /// Why the stream did not open; null while there is nothing to say.
  String? get failure;

  List<MediaTrack> get audioTracks;
  List<MediaTrack> get subtitleTracks;

  /// The id of the track playing; null for none (subtitles off).
  String? get audioTrack;
  String? get subtitleTrack;

  double get speed;

  void play();
  void pause();
  void seek(Duration to);
  void setSpeed(double speed);
  void setAudioTrack(String id);

  /// Null turns the subtitles off.
  void setSubtitleTrack(String? id);

  /// The picture, with the subtitles on it.
  Widget view();
}

/// Why a stream did not open, from the engine's last messages: the HTTP status, if one was logged.
/// Never the messages themselves: they quote the stream's address, which holds the provider login.
/// "HTTP error 404" is ffmpeg's wording, as the libmpv in use logs it; another wording falls back to "no stream".
String failureReason(Iterable<String> messages) {
  for (final message in messages.toList().reversed) {
    final status = RegExp(r'HTTP error (\d{3})').firstMatch(message);
    if (status != null) return 'HTTP ${status[1]}';
  }
  return 'no stream';
}

/// A track's name in the menus: its language tag, its title, and for sound its channels; "Track 2" with none of them.
// shortcut: the file's own language tag (ENG, HEB) is shown, not the language's name; add a name table if users ask.
String trackLabel(int number, {String? language, String? title, int? channels}) {
  final tag = language == null || language == 'und' ? null : language.toUpperCase();
  final layout = switch (channels) {
    null => null,
    1 => '1.0',
    2 => '2.0',
    6 => '5.1',
    8 => '7.1',
    _ => '$channels ch',
  };
  final name = [tag, if (title != null && title.trim().isNotEmpty) title.trim()].nonNulls.join(' · ');
  return [name.isEmpty ? 'Track $number' : name, ?layout].join(' · ');
}
