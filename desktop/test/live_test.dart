import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wtv/data/live.dart';

Channel ch(int id, [List<int> categories = const []]) => Channel(id, id + 1000, 'ch $id', id, null, 0, false, categories);
const israel = LiveCategory(1, 'ישראל', 'Israel', 'ישראל');
const radio = LiveCategory(20, 'רדיו', 'Radio', null);
const sport = LiveCategory(30, 'ספורט', 'Sports', 'ספורט');

List<int> ids(LiveGroup group) => [for (final c in group.channels) c.id];

void main() {
  test('favourites first, then categories in order, empty groups left out', () {
    final channels = [
      ch(1, [1]),
      ch(2, [1]),
      ch(3, [20]),
      ch(4, [1, 20]),
    ];
    final groups = liveGroups(channels, [israel, sport, radio], {3, 2}, 'Favourites', hebrew: false);
    expect([for (final g in groups) g.label], ['Favourites', 'Israel', 'Radio']);
    expect(groups[0].category, isNull);
    expect(ids(groups[0]), [2, 3]);
    expect(ids(groups[1]), [1, 2, 4]);
    expect(ids(groups[2]), [3, 4]);
  });

  test('no favourites gives no Favourites group, and Hebrew labels fall back to the provider name', () {
    final groups = liveGroups([
      ch(3, [20]),
    ], [radio], {}, 'Favourites', hebrew: true);
    expect([for (final g in groups) g.label], ['רדיו']);
  });

  test('a channel row parses, with no number, logo or categories', () {
    final full = channel({
      'id': 5,
      'ext_id': 123,
      'name': 'Kan 11',
      'num': 11,
      'logo_url': 'https://l/k.png',
      'archive_days': 7,
      'is_radio': false,
      'category_ids': [1, 20],
    });
    expect(full, const Channel(5, 123, 'Kan 11', 11, 'https://l/k.png', 7, false, [1, 20]));
    final bare = channel({'id': 6, 'ext_id': 9, 'name': 'X', 'num': null, 'logo_url': ''});
    expect(bare, const Channel(6, 9, 'X', null, null, 0, false, []));
  });

  test('the favourite body names the channel and the flag only', () {
    expect(favoriteBody(5, true), '{"channel_id":5,"favorite":true}');
  });

  test('hidden channels and groups and radio are left out, but a favourite in a hidden group stays', () {
    const radioChannel = Channel(9, 1009, 'Radio 9', 9, null, 0, true, [20]);
    final channels = [
      ch(1, [1]),
      ch(2, [1]),
      ch(3, [30]),
      radioChannel,
    ];
    const filters = LiveFilters(hiddenChannels: {2}, hiddenGroups: {30}, showRadio: false);
    final groups = liveGroups(channels, [israel, sport, radio], {3, 2, 9}, 'Favourites', hebrew: false, filters: filters);
    expect([for (final g in groups) g.label], ['Favourites', 'Israel']);
    expect(ids(groups[0]), [3]);
    expect(ids(groups[1]), [1]);
  });

  test('the hide bodies name one flag each', () {
    expect(jsonDecode(hiddenBody(5, true)), {'channel_id': 5, 'hidden': true});
    expect(jsonDecode(groupBody(20, false)), {'category_id': 20, 'hidden': false});
  });

  test('a typed number is found in the watched group first, then in all channels', () {
    final group = [ch(5), ch(9)];
    final all = [ch(1), ch(5), ch(9), ch(12)];
    expect(channelByNumber(9, group, all), (group, 1));
    expect(channelByNumber(12, group, all), (all, 3));
    expect(channelByNumber(77, group, all), isNull);
  });

  test('all shown channels are each once, by number, unnumbered last', () {
    const unnumbered = Channel(3, 1003, 'ch 3', null, null, 0, false, []);
    final groups = [
      LiveGroup(null, 'Favourites', [ch(9), ch(2)]),
      LiveGroup(null, 'Israel', [unnumbered, ch(2), ch(5)]),
    ];
    expect([for (final c in allShown(groups)) c.id], [2, 5, 9, 3]);
  });

  // Not in the TV app's tests: what the port adds.

  test('channels with the same number keep their order, and one filter changes at a time', () {
    const twin = Channel(7, 1007, 'twin', 2, null, 0, false, []);
    final shown = allShown([
      LiveGroup(null, 'All', [ch(9), twin, ch(2)]),
    ]);
    expect([for (final c in shown) c.id], [7, 2, 9]);
    final filters = const LiveFilters(hiddenChannels: {2}).copyWith(hiddenGroups: {30}).copyWith(showRadio: false);
    expect([filters.hiddenChannels, filters.hiddenGroups, filters.showRadio], [
      {2},
      {30},
      false,
    ]);
  });
}
