import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

/// The viewer's last subtitle choice, carried to the next video (the next
/// episode most of all). Subtitles come only from the files themselves: the
/// provider lists none, and many tracks carry no language tag.
///
/// Stored as [subtitlesOff], [subtitlesUntagged] or a language tag. Nothing
/// stored: each file's own default.
const subtitlesOff = 'off';
const subtitlesUntagged = 'und';

const _key = 'subtitles';

/// The saved choice; null for none, or when the settings file cannot be read.
Future<String?> loadSubtitleChoice() async {
  try {
    return (await SharedPreferences.getInstance()).getString(_key);
  } catch (e) {
    debugPrint('Reading the subtitle choice failed: $e');
    return null;
  }
}

/// Keeps the choice for the next video. A failed write loses only that.
Future<void> saveSubtitleChoice(String choice) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_key, choice);
  } catch (e) {
    debugPrint('Saving the subtitle choice failed: $e');
  }
}

/// What a picked track stands for: its language tag, or [subtitlesUntagged]; [subtitlesOff] for none.
String subtitleChoice(MediaTrack? picked) => picked == null ? subtitlesOff : picked.language ?? subtitlesUntagged;

/// What the saved choice asks of a file with these subtitle tracks: `(true, null)` turns them off,
/// `(true, id)` shows that track, `(false, null)` leaves the file's own default.
/// A file without the saved language shows its untagged track, if any: most tracks here carry no tag.
(bool, String?) subtitleFor(List<MediaTrack> tracks, String? saved) {
  if (saved == null) return (false, null);
  if (saved == subtitlesOff) return (true, null);
  bool untagged(MediaTrack t) => t.language == null || t.language == subtitlesUntagged;
  final track =
      (saved == subtitlesUntagged ? null : tracks.where((t) => t.language == saved).firstOrNull) ??
      tracks.where(untagged).firstOrNull;
  return track == null ? (false, null) : (true, track.id);
}
