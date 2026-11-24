import 'dart:convert';

import 'catalog.dart';
import 'json.dart';

/// Where playback of a movie or one episode stopped. Episodes are known by
/// season and number, not id: a series' copies each have their own episode rows.
class Progress {
  const Progress(this.titleId, this.season, this.episode, this.positionSecs, this.durationSecs);

  final int titleId;
  final int? season;
  final int? episode;
  final int positionSecs;
  final int? durationSecs;

  bool get isEpisode => season != null && episode != null;

  /// Watched to the credits: not resumed, and a movie leaves Continue watching.
  bool get finished {
    final duration = durationSecs;
    return duration != null && duration > 0 && positionSecs >= duration * finishedAt;
  }

  /// Where Play starts: the saved position, unless it is at the very start or finished.
  int get resumeSecs => finished || positionSecs < minResumeSecs ? 0 : positionSecs;

  /// Share watched, for the bar on a card; null when the length is unknown.
  double? get fraction {
    final duration = durationSecs;
    return duration == null || duration <= 0 ? null : (positionSecs / duration).clamp(0.0, 1.0);
  }

  (int, int?, int?, int, int?) get _fields => (titleId, season, episode, positionSecs, durationSecs);

  @override
  bool operator ==(Object other) => other is Progress && other._fields == _fields;

  @override
  int get hashCode => _fields.hashCode;
}

const finishedAt = 0.95;
const minResumeSecs = 30;

/// What Play does on a series page: this episode, from this second.
class EpisodePlay {
  const EpisodePlay(this.episode, this.startSecs);

  final Episode episode;
  final int startSecs;

  @override
  bool operator ==(Object other) => other is EpisodePlay && other.episode == episode && other.startSecs == startSecs;

  @override
  int get hashCode => Object.hash(episode, startSecs);
}

/// Play on a series: the last episode watched if it is unfinished, else the
/// one after it; the first episode when nothing was watched, the last one
/// watched is gone, or it was the series' last.
/// `progress` is newest first; `episodes` in order.
EpisodePlay? nextEpisode(List<Episode> episodes, List<Progress> progress) {
  final first = episodes.firstOrNull;
  if (first == null) return null;
  final last = progress.where((p) => p.isEpisode).firstOrNull;
  if (last == null) return EpisodePlay(first, 0);
  final i = episodes.indexWhere((e) => e.season == last.season && e.number == last.episode);
  if (i < 0) return EpisodePlay(first, 0);
  if (!last.finished) return EpisodePlay(episodes[i], last.resumeSecs);
  return EpisodePlay(episodes.elementAtOrNull(i + 1) ?? first, 0);
}

/// The episode after `episodeId` in `episodes` (in order); null after the last, or when it is not there.
Episode? episodeAfter(List<Episode> episodes, int? episodeId) {
  final i = episodes.indexWhere((e) => e.id == episodeId);
  return i >= 0 ? episodes.elementAtOrNull(i + 1) : null;
}

/// The episode before `episodeId` in `episodes` (in order); null before the first, or when it is not there.
Episode? episodeBefore(List<Episode> episodes, int? episodeId) {
  final i = episodes.indexWhere((e) => e.id == episodeId);
  return i > 0 ? episodes[i - 1] : null;
}

/// A card in the Continue watching row.
class ContinueItem {
  const ContinueItem(this.title, this.progress);

  final Title title;
  final Progress progress;
}

/// Continue watching from progress rows (newest first, each with its title):
/// one card per title (its copies count as one), from its newest row. A
/// finished movie leaves the row; a series stays, for its next episode.
List<ContinueItem> continueItems(List<JsonObject> rows) {
  final seen = <int>{};
  final items = [
    for (final o in rows)
      if (o.optObject('titles') case final t?) ContinueItem(title(t), progress(o)),
  ];
  return items
      .where((item) => seen.add(item.title.groupId ?? item.title.id))
      .where((item) => item.progress.isEpisode || !item.progress.finished)
      .toList();
}

const progressColumns = 'title_id,position_secs,duration_secs,episodes(season,episode)';

/// A progress row from the REST API, with its episode's season and number embedded.
Progress progress(JsonObject o) {
  final e = o.optObject('episodes');
  return Progress(
    o.getInt('title_id'),
    e?.getInt('season'),
    e?.getInt('episode'),
    o.getInt('position_secs'),
    o.isNull('duration_secs') ? null : o.getInt('duration_secs'),
  );
}

/// The JSON body that saves a position. The user is the database's: the signed-in one.
String progressBody(int titleId, int? episodeId, int positionSecs, int? durationSecs) => jsonEncode({
  'title_id': titleId,
  'episode_id': episodeId,
  'position_secs': positionSecs,
  'duration_secs': durationSecs,
});
