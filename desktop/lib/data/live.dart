import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals, mergeSort;

import 'catalog.dart';
import 'json.dart';

/// A live channel. `num` is the provider's channel number; `archiveDays` > 0 has catch-up.
class Channel {
  const Channel(this.id, this.extId, this.name, this.num, this.logo, this.archiveDays, this.isRadio, this.categoryIds);

  final int id;
  final int extId;
  final String name;
  final int? num;
  final String? logo;
  final int archiveDays;
  final bool isRadio;
  final List<int> categoryIds;

  (int, int, String, int?, String?, int, bool) get _fields => (id, extId, name, num, logo, archiveDays, isRadio);

  @override
  bool operator ==(Object other) =>
      other is Channel && other._fields == _fields && listEquals(other.categoryIds, categoryIds);

  @override
  int get hashCode => Object.hash(_fields, Object.hashAll(categoryIds));
}

class LiveCategory {
  const LiveCategory(this.id, this.name, this.nameEn, this.nameHe);

  final int id;
  final String name;
  final String? nameEn;
  final String? nameHe;

  String label({required bool hebrew}) => (hebrew ? nameHe : nameEn) ?? name;
}

/// A group of channels on the Live TV page: Favourites (`category` null) or a provider category.
class LiveGroup {
  const LiveGroup(this.category, this.label, this.channels);

  final LiveCategory? category;
  final String label;
  final List<Channel> channels;
}

const channelColumns = 'id,ext_id,name,num,logo_url,archive_days,is_radio,category_ids';

Channel channel(JsonObject o) => Channel(
  o.getInt('id'),
  o.getInt('ext_id'),
  o.getString('name'),
  o.isNull('num') ? null : o.getInt('num'),
  o.text('logo_url'),
  o.optInt('archive_days'),
  o.optBoolean('is_radio'),
  o.optArray('category_ids')?.ints() ?? const [],
);

/// What the user hid on the Live TV page: single channels, whole groups, and all radio channels when `showRadio` is off.
class LiveFilters {
  const LiveFilters({this.hiddenChannels = const {}, this.hiddenGroups = const {}, this.showRadio = true});

  final Set<int> hiddenChannels;
  final Set<int> hiddenGroups;
  final bool showRadio;

  LiveFilters copyWith({Set<int>? hiddenChannels, Set<int>? hiddenGroups, bool? showRadio}) => LiveFilters(
    hiddenChannels: hiddenChannels ?? this.hiddenChannels,
    hiddenGroups: hiddenGroups ?? this.hiddenGroups,
    showRadio: showRadio ?? this.showRadio,
  );
}

/// The page's groups: Favourites first when there are any, then each category
/// in the provider's order, without what `filters` hides. A favourite in a
/// hidden group still shows under Favourites. Channels keep the given order;
/// empty groups are left out.
List<LiveGroup> liveGroups(
  List<Channel> channels,
  List<LiveCategory> categories,
  Set<int> favorites,
  String favoritesLabel, {
  required bool hebrew,
  LiveFilters filters = const LiveFilters(),
}) {
  final shown = [
    for (final c in channels)
      if (!filters.hiddenChannels.contains(c.id) && (filters.showRadio || !c.isRadio)) c,
  ];
  final favorite = LiveGroup(null, favoritesLabel, [
    for (final c in shown)
      if (favorites.contains(c.id)) c,
  ]);
  final byCategory = [
    for (final category in categories)
      if (!filters.hiddenGroups.contains(category.id))
        LiveGroup(category, category.label(hebrew: hebrew), [
          for (final c in shown)
            if (c.categoryIds.contains(category.id)) c,
        ]),
  ];
  return [
    for (final group in [favorite, ...byCategory])
      if (group.channels.isNotEmpty) group,
  ];
}

/// The JSON body that hides or shows a channel; the favourite flag is left as it is.
String hiddenBody(int channelId, bool hidden) => jsonEncode({'channel_id': channelId, 'hidden': hidden});

/// The JSON body that hides or shows a live group.
String groupBody(int categoryId, bool hidden) => jsonEncode({'category_id': categoryId, 'hidden': hidden});

/// The JSON body that sets a channel's favourite flag. The user is the database's: the signed-in one.
String favoriteBody(int channelId, bool favorite) => jsonEncode({'channel_id': channelId, 'favorite': favorite});

/// The channel with this provider number: in `current` first (its order kept), else in `all`; null when neither has it.
/// Numbers can repeat across provider categories: the first one wins.
(List<Channel>, int)? channelByNumber(int num, List<Channel> current, List<Channel> all) {
  for (final list in [current, all]) {
    final i = list.indexWhere((c) => c.num == num);
    if (i >= 0) return (list, i);
  }
  return null;
}

/// Every channel the page shows, once, in channel-number order (unnumbered last).
List<Channel> allShown(List<LiveGroup> groups) {
  final seen = <int>{};
  final shown = [for (final group in groups) ...group.channels].where((c) => seen.add(c.id)).toList();
  // Channels with the same number keep their order.
  mergeSort(
    shown,
    compare: (a, b) {
      final x = a.num, y = b.num;
      return x == null || y == null ? (x == null ? 1 : 0) - (y == null ? 1 : 0) : x.compareTo(y);
    },
  );
  return shown;
}
