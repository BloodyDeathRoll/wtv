import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wtv/data/catalog.dart' hide episode;
import 'package:wtv/data/json.dart';
import 'package:wtv/data/progress.dart';

Progress movie(int pos, int? dur) => Progress(1, null, null, pos, dur);
Progress ep(int season, int number, int pos, [int? dur = 2400]) => Progress(1, season, number, pos, dur);
Episode episode(int season, int number) =>
    Episode(id: season * 100 + number, extId: 1, containerExt: 'mp4', season: season, number: number, durationSecs: 2400);

JsonObject row(int titleId, int? groupId, int pos, int? dur, {int? season, int? number, String kind = 'movie'}) => {
  'title_id': titleId,
  'position_secs': pos,
  'duration_secs': dur,
  'episodes': season == null ? null : {'season': season, 'episode': number},
  'titles': {'id': titleId, 'ext_id': 9, 'kind': kind, 'name': 't$titleId', 'group_id': groupId},
};

void main() {
  test('finished at 95 percent, resume skips the first 30 seconds and finished titles', () {
    expect(movie(5699, 6000).finished, isFalse);
    expect(movie(5700, 6000).finished, isTrue);
    expect(movie(5000, null).finished, isFalse);
    expect(movie(29, 6000).resumeSecs, 0);
    expect(movie(30, 6000).resumeSecs, 30);
    expect(movie(5800, 6000).resumeSecs, 0);
    expect(movie(5000, null).resumeSecs, 5000);
    expect(movie(3000, 6000).fraction, closeTo(0.5, 0.0001));
    expect(movie(3000, 0).fraction, isNull);
  });

  test('the episode after - across seasons, none after the last or for an unknown one', () {
    final eps = [episode(1, 1), episode(1, 2), episode(2, 1)];
    expect(episodeAfter(eps, eps[0].id), eps[1]);
    expect(episodeAfter(eps, eps[1].id), eps[2]);
    expect(episodeAfter(eps, eps[2].id), isNull);
    expect(episodeAfter(eps, 999), isNull);
    expect(episodeAfter(eps, null), isNull);
  });

  test('the episode before - across seasons, none before the first or for an unknown one', () {
    final eps = [episode(1, 1), episode(1, 2), episode(2, 1)];
    expect(episodeBefore(eps, eps[2].id), eps[1]);
    expect(episodeBefore(eps, eps[0].id), isNull);
    expect(episodeBefore(eps, 999), isNull);
    expect(episodeBefore(eps, null), isNull);
  });

  test('series Play - first episode, the unfinished one, the next, or back to the first', () {
    final eps = [episode(1, 1), episode(1, 2), episode(2, 1)];
    expect(nextEpisode([], []), isNull);
    expect(nextEpisode(eps, []), EpisodePlay(eps[0], 0));
    // Newest first: the unfinished S1E2 wins over the older S1E1.
    expect(nextEpisode(eps, [ep(1, 2, 600), ep(1, 1, 2400)]), EpisodePlay(eps[1], 600));
    // Finished S1E2: the next is S2E1 (across the season).
    expect(nextEpisode(eps, [ep(1, 2, 2350)]), EpisodePlay(eps[2], 0));
    // The series' last episode finished, or the watched one is gone: from the start.
    expect(nextEpisode(eps, [ep(2, 1, 2390)]), EpisodePlay(eps[0], 0));
    expect(nextEpisode(eps, [ep(3, 7, 100)]), EpisodePlay(eps[0], 0));
    // A movie position on the series is ignored.
    expect(nextEpisode(eps, [movie(100, 200)]), EpisodePlay(eps[0], 0));
  });

  test('a progress row parses, with and without an episode', () {
    final m = progress(row(5, 5, 120, null));
    expect(m, const Progress(5, null, null, 120, null));
    expect(m.isEpisode, isFalse);
    final e = progress(row(6, 6, 300, 2400, season: 2, number: 3, kind: 'series'));
    expect(e, const Progress(6, 2, 3, 300, 2400));
    expect(e.isEpisode, isTrue);
  });

  test('continue watching - one card per title group from its newest row, finished movies out, series kept', () {
    final items = continueItems([
      row(1, 1, 600, 6000), // newest: movie group 1, copy 1
      row(2, 1, 5000, 6000), // older row of the same movie, another copy
      row(3, 3, 5900, 6000), // finished movie: out
      row(4, 4, 2390, 2400, season: 1, number: 8, kind: 'series'), // finished episode: series stays
      row(5, null, 100, null), // never regrouped: its own card
      {'title_id': 6, 'position_secs': 1, 'duration_secs': 2}, // title not readable: skipped
    ]);
    expect([for (final item in items) item.title.id], [1, 4, 5]);
    expect(items[0].progress.positionSecs, 600);
  });

  test('the save body names title, episode, position and length, with nulls', () {
    // The whole body: the nulls are written, and no user is named.
    final movie = jsonDecode(progressBody(7, null, 90, null));
    expect(movie, {'title_id': 7, 'episode_id': null, 'position_secs': 90, 'duration_secs': null});
    final episode = jsonDecode(progressBody(7, 44, 90, 2400));
    expect(episode, {'title_id': 7, 'episode_id': 44, 'position_secs': 90, 'duration_secs': 2400});
  });

  test('one episode per number - the one named after the series, then the newest', () {
    Episode e(int season, int number, int extId, String? name) =>
        Episode(id: extId, extId: extId, containerExt: 'mp4', season: season, number: number, providerName: name);
    const series = '007: הדרך למיליון';
    final picked = oneEach([
      e(1, 1, 179838, '$series - S01E01 - פרק 1'),
      e(1, 1, 229332, 'הבר מצווה - S01E01 - פרק 1'),
      e(1, 1, 285382, '$series - S01E01 - פרק 1'),
      e(1, 1, 292447, 'אוז - S01E01 - השיגרה'),
      e(1, 2, 10, null),
      e(1, 2, 11, null),
      e(2, 1, 5, 'other'),
    ], series);
    expect([for (final p in picked) p.extId], [285382, 11, 5]);
  });
}
