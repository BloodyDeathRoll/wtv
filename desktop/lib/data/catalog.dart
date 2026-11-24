import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, mergeSort;

import 'api.dart';
import 'images.dart';
import 'json.dart';
import 'live.dart';
import 'marks.dart';
import 'progress.dart';
import 'semaphore.dart';
import 'session.dart';

enum Kind {
  movie('movie'),
  series('series');

  const Kind(this.db);

  final String db;
}

/// A provider category, or with `genre` a TMDB genre, or with `all` every title
/// of the kind (side bar → Categories): all open the same grid. `count`, when
/// known, is how many titles it has.
class Category {
  const Category(
    this.id,
    this.kind,
    this.name,
    this.nameEn,
    this.nameHe, {
    this.genre = false,
    this.all = false,
    this.count,
  });

  final int id;
  final Kind kind;
  final String name;
  final String? nameEn;
  final String? nameHe;
  final bool genre;
  final bool all;
  final int? count;

  String label({required bool hebrew}) => (hebrew ? nameHe : nameEn) ?? name;

  Category copyWith({int? count}) =>
      Category(id, kind, name, nameEn, nameHe, genre: genre, all: all, count: count ?? this.count);
}

/// A movie or series as the app shows it. TMDB text first, in the app's
/// language; the provider's own (mostly Hebrew) text when TMDB has none.
class Title {
  const Title({
    required this.id,
    required this.extId,
    this.containerExt,
    required this.kind,
    required this.name,
    this.nameEn,
    this.nameHe,
    this.year,
    this.plot,
    this.overviewEn,
    this.overviewHe,
    required this.genreIds,
    this.certification,
    this.tmdbBackdrop,
    this.tmdbPoster,
    this.providerBackdrop,
    this.providerPoster,
    this.runtimeMin,
    this.director,
    this.castNames,
    this.tmdbRating,
    this.originalLanguage,
    this.groupId,
    this.match,
  });

  final int id;

  /// The provider's id of this copy; with `containerExt`, what playback needs.
  final int extId;
  final String? containerExt;
  final Kind kind;
  final String name;
  final String? nameEn;
  final String? nameHe;
  final int? year;
  final String? plot;
  final String? overviewEn;
  final String? overviewHe;
  final List<int> genreIds;
  final String? certification;
  final String? tmdbBackdrop;
  final String? tmdbPoster;
  final String? providerBackdrop;
  final String? providerPoster;
  final int? runtimeMin;
  final String? director;
  final String? castNames;
  final double? tmdbRating;
  final String? originalLanguage;

  /// The card of this title's copies; null before the first regroup (then the title is its own card).
  final int? groupId;

  /// WTW's "% match" from the user's ranking; null without one. Shown only while WTW is connected.
  final int? match;

  String displayName({required bool hebrew}) => (hebrew ? nameHe : nameEn) ?? name;

  String? synopsis({required bool hebrew}) => hebrew ? overviewHe ?? plot ?? overviewEn : overviewEn ?? plot ?? overviewHe;

  String? get cardImage =>
      tmdbImage(tmdbBackdrop, TmdbSize.card) ?? providerBackdrop ?? tmdbImage(tmdbPoster, TmdbSize.card) ?? providerPoster;

  String? get heroImage => tmdbImage(tmdbBackdrop, TmdbSize.backdrop) ?? providerBackdrop;

  String? get posterImage => tmdbImage(tmdbPoster, TmdbSize.poster) ?? providerPoster;

  /// A title as its only copy: what Play uses when the copies are not known.
  /// For a grouped title whose copies all went unavailable this copy may not
  /// play either; playback (P3-1) must show a failed stream as an error.
  Copy asCopy() => Copy(id, extId, containerExt, false);
}

/// Orders of a category grid. Name follows the app's language.
enum Sort {
  added,
  year,
  name,
  rating;

  /// The REST `order` value for a sort; every order ends on `id`, so paging is stable.
  String order({required bool hebrew}) => switch (this) {
    Sort.added => 'group_added_at.desc.nullslast,id',
    Sort.year => 'year.desc.nullslast,id',
    Sort.name => '${hebrew ? 'sort_name_he' : 'sort_name_en'}.asc,id',
    Sort.rating => 'tmdb_rating.desc.nullslast,id',
  };
}

/// A cast member as the title page shows them.
class CastMember {
  const CastMember(this.personId, this.name, this.character, this.profile);

  final int personId;
  final String name;
  final String? character;
  final String? profile;

  String? get photo => tmdbImage(profile, TmdbSize.profile);
}

/// An episode of a series. Names and synopses as for titles: TMDB first, then the provider's.
class Episode {
  const Episode({
    required this.id,
    required this.extId,
    this.containerExt,
    required this.season,
    required this.number,
    this.nameEn,
    this.nameHe,
    this.overviewEn,
    this.overviewHe,
    this.plot,
    this.durationSecs,
    this.tmdbStill,
    this.providerImage,
    this.providerName,
  });

  final int id;
  final int extId;
  final String? containerExt;
  final int season;
  final int number;
  final String? nameEn;
  final String? nameHe;
  final String? overviewEn;
  final String? overviewHe;
  final String? plot;
  final int? durationSecs;
  final String? tmdbStill;
  final String? providerImage;

  /// The provider's own name, "Series - S01E01 - …"; tells this series' episodes from others filed under it.
  final String? providerName;

  /// Null when there is no real name: the page writes "Episode 3" in the
  /// app's language. TMDB's own stand-ins ("Episode 3") are stored empty by
  /// the enrichment job.
  String? displayName({required bool hebrew}) => hebrew ? nameHe ?? nameEn : nameEn;

  /// As for titles: in Hebrew the provider's (Hebrew) plot comes before TMDB's English.
  /// English ends on the Hebrew overview because the database drops the plot when one exists.
  String? synopsis({required bool hebrew}) => hebrew ? overviewHe ?? plot ?? overviewEn : overviewEn ?? plot ?? overviewHe;

  String? get image => tmdbImage(tmdbStill, TmdbSize.still) ?? providerImage;
}

/// One provider copy of a title; Play chooses among them.
class Copy {
  const Copy(this.id, this.extId, this.containerExt, this.is4k);

  final int id;
  final int extId;
  final String? containerExt;
  final bool is4k;

  (int, int, String?, bool) get _fields => (id, extId, containerExt, is4k);

  @override
  bool operator ==(Object other) => other is Copy && other._fields == _fields;

  @override
  int get hashCode => _fields.hashCode;
}

class Genre {
  const Genre(this.nameEn, this.nameHe);

  final String nameEn;
  final String? nameHe;

  String label({required bool hebrew}) => (hebrew ? nameHe : null) ?? nameEn;
}

/// One at a time: each waits for the one before.
class _Lock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() body) {
    final result = _last.then((_) => body());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Catalog reads, cached for the app's lifetime (the catalog changes every few hours at most).
class Catalog {
  Catalog(this._api);

  final Api _api;

  // A lock per cache: a quick tab switch must not fetch twice or race, and
  // the two fetches do not wait for each other.
  final _categoriesLock = _Lock();
  final _genresLock = _Lock();
  final _categories = <Kind, List<Category>>{};
  Map<(Kind, int), Genre>? _genres;

  /// Parallel row requests. ~25 categories at once is a lot for Wi-Fi.
  final _rowRequests = Semaphore(6);

  Future<List<JsonObject>> _rows(String path) async => (await _api.get(path)).objects();

  Future<List<Title>> _titles(String path) async => [for (final o in await _rows(path)) title(o)];

  Future<List<Category>> categories(Kind kind) => _categoriesLock.run(
    () async => _categories[kind] ??= [
      for (final o in await _rows('categories?select=ext_id,name,name_en,name_he&kind=eq.${kind.db}&order=position'))
        Category(o.getInt('ext_id'), kind, o.getString('name'), o.text('name_en'), o.text('name_he')),
    ],
  );

  /// A kind's genres as categories, by name: the side bar's second group of tags.
  Future<List<Category>> genreCategories(Kind kind, {required bool hebrew}) async {
    final list = [
      for (final MapEntry(key: (genreKind, id), value: g) in (await genres()).entries)
        if (genreKind == kind) Category(id, kind, g.nameEn, g.nameEn, g.nameHe, genre: true),
    ];
    mergeSort(list, compare: (a, b) => a.label(hebrew: hebrew).compareTo(b.label(hebrew: hebrew)));
    return list;
  }

  Future<Map<(Kind, int), Genre>> genres() => _genresLock.run(
    () async => _genres ??= {
      for (final o in await _rows('genres?select=kind,id,name_en,name_he'))
        (_kindOf(o.getString('kind')), o.getInt('id')): Genre(o.getString('name_en'), o.text('name_he')),
    },
  );

  /// The newest titles the provider has, in one category or all.
  Future<List<Title>> latest(Kind kind, {int? category, int limit = 10, bool genre = false}) =>
      _titles(latestPath(kind, category, limit, genre: genre));

  /// One page of a category, best first by the user's WTW ranking; newest first without one.
  Future<List<Title>> recommendedPage(Category category, {required int offset, required int limit}) =>
      _titles(recommendedPath(category, offset: offset, limit: limit));

  /// Home: the best ranked titles the user has not rated in WTW.
  Future<List<Title>> topPicks({int limit = 20}) => _titles('rpc/top_picks?select=$_titleColumns&p_limit=$limit');

  /// "Recommended for You": the ranking's best, unrated, in one kind or both; a page at a time.
  Future<List<Title>> topPicksPage(Kind? kind, {required int offset, required int limit}) =>
      _titles('rpc/top_picks_page?select=$_titleColumns&p_offset=$offset&p_limit=$limit${_pKind(kind)}');

  /// "Watch it again" without WTW: the titles the user finished, last finished first.
  Future<List<Title>> finishedTitles({int limit = 20, Kind? kind}) =>
      _titles('rpc/finished_titles?select=$_titleColumns&p_limit=$limit${_pKind(kind)}');

  /// Home: of the newest titles, the ranking's best, unrated.
  Future<List<Title>> newForYou({int limit = 20}) => _titles('rpc/new_for_you?select=$_titleColumns&p_limit=$limit');

  /// "Viewers also liked": the cards nearest in WTW's taste space, the user's best first.
  Future<List<Title>> alsoLiked(Title title, {int limit = 20}) =>
      _titles('rpc/also_liked?select=$_titleColumns&p_title=${title.id}&p_limit=$limit');

  /// Home: titles loved or liked in WTW.
  Future<List<Title>> watchAgain({int limit = 20, Kind? kind}) =>
      _titles('rpc/watch_again?select=$_titleColumns&p_limit=$limit${_pKind(kind)}');

  /// Asks the server to rank the catalog from the user's WTW data (`wtwToken`
  /// is their WTW session). Cheap when a recent ranking exists: the server
  /// keeps it. True when a new ranking was made.
  Future<bool> refreshRanking(String wtwToken) async =>
      !jsonObject(await _api.function('rank', jsonEncode({'wtw_token': wtwToken}))).optBoolean('fresh');

  /// WTW's own "% match" for these cards, asked of WTW by the server (`wtw-scores`):
  /// card id to the percent WTW shows, null when WTW does not score the title.
  /// Cards WTW could not be asked about this time are left out.
  Future<Map<int, int?>> wtwScores(String wtwToken, List<int> ids) async {
    final body = jsonEncode({'wtw_token': wtwToken, 'title_ids': ids});
    final scores = jsonObject(await _api.function('wtw-scores', body)).optObject('scores');
    if (scores == null) return {};
    return {for (final id in scores.keys) int.parse(id): scores.isNull(id) ? null : scores.getInt(id)};
  }

  /// One page of a category in the given order.
  Future<List<Title>> page(Category category, Sort sort, {required bool hebrew, required int offset, required int limit}) =>
      _titles(pagePath(category, sort, hebrew: hebrew, offset: offset, limit: limit));

  /// A series' episodes in order, one per season and number (see [oneEach]).
  /// Read 1,000 at a time: the REST API returns no more per call, and daily
  /// shows have up to 1,500.
  Future<List<Episode>> episodes(Title series) async {
    final all = <Episode>[];
    while (true) {
      final page = [for (final o in await _rows(episodesPath(series.id, offset: all.length))) episode(o)];
      all.addAll(page);
      if (page.length < episodesPage) return oneEach(all, series.name);
    }
  }

  /// The provider's titles a person is billed in (top 15 billing, from TMDB),
  /// as cards, newest first. Read from the cast side: the person's index makes
  /// it fast, where filtering titles by cast is not.
  Future<List<Title>> personTitles(int personId) async {
    final rows = [
      for (final o in await _rows('title_cast?select=titles($_titleColumns,is_primary,available)&person_id=eq.$personId'))
        ?o.optObject('titles'),
    ];
    // Cast is stored for every copy, so the card is normally among the rows.
    // A copy whose card is not (its enrichment still pending) is resolved to it.
    final missing = cardsMissingFor(rows);
    final cards = missing.isEmpty
        ? const <JsonObject>[]
        : await _rows('titles?select=$_titleColumns,is_primary,available&id=in.(${missing.join(',')})');
    return personCards([...rows, ...cards]);
  }

  /// Cards whose name contains `query`, in English, Hebrew or the provider's
  /// own; names starting with it first. Of one kind, or both.
  Future<List<Title>> search(String query, {required bool hebrew, Kind? kind}) async {
    final q = query.replaceAll('*', '').trim();
    if (q.isEmpty) return [];
    final [startsWith, contains] = await Future.wait([
      _titles(searchPath(q, hebrew: hebrew, prefix: true, kind: kind)),
      _titles(searchPath(q, hebrew: hebrew, prefix: false, kind: kind)),
    ]);
    return mergeSearch(startsWith, contains);
  }

  /// Actors whose name contains `query` and who are in an available title (of `kind`): the best known first.
  Future<List<CastMember>> searchPeople(String query, {Kind? kind}) async {
    final q = query.trim();
    if (q.length < 2) return [];
    return [
      for (final o in await _rows(peopleSearchPath(q, kind)))
        CastMember(o.getInt('tmdb_id'), o.getString('name'), null, o.text('profile')),
    ];
  }

  /// Billed cast of a title, in order.
  Future<List<CastMember>> cast(int titleId) async {
    final rows = await _rows('title_cast?select=position,character,people(tmdb_id,name,profile)&title_id=eq.$titleId&order=position');
    return rows.map((o) {
      final p = o.getObject('people');
      return CastMember(p.getInt('tmdb_id'), p.getString('name'), o.text('character'), p.text('profile'));
    }).toList();
  }

  /// The available copies of a title, the 4K ones first; at least the title itself.
  Future<List<Copy>> copies(Title title) async {
    final fourK = {
      for (final c in await categories(title.kind))
        if (c.name.toLowerCase().contains('4k')) c.id,
    };
    final rows = await _rows(
      'titles?select=id,ext_id,container_ext,category_ids&group_id=eq.${title.groupId ?? title.id}&available=is.true&order=id',
    );
    return copiesFrom(title, rows, fourK);
  }

  /// Saves where playback stopped: one row per movie, or per episode, and user.
  Future<void> saveProgress(int titleId, int? episodeId, int positionSecs, int? durationSecs) => _api.post(
    'progress?on_conflict=user_id,title_id,episode_id',
    progressBody(titleId, episodeId, positionSecs, durationSecs),
    prefer: 'resolution=merge-duplicates,return=minimal',
  );

  /// A title's saved positions over all its copies, newest first.
  Future<List<Progress>> progress(Title title) async {
    final rows = await _rows(
      'progress?select=$progressColumns,titles!inner(group_id)&titles.group_id=eq.${title.groupId ?? title.id}&order=updated_at.desc',
    );
    return rows.map(_progressRow).toList();
  }

  /// Forgets the saved positions on these copies: the title leaves Continue watching and plays from the start.
  Future<void> clearProgress(Iterable<int> titleIds) async {
    if (titleIds.isNotEmpty) await _api.delete('progress?title_id=in.(${titleIds.join(',')})');
  }

  /// The Continue watching row: titles with a saved position, last watched first.
  Future<List<ContinueItem>> continueWatching() async => continueItems(
    await _rows(
      'progress?select=$progressColumns,titles!inner($_titleColumns)&titles.available=is.true&order=updated_at.desc&limit=$_continueRows',
    ),
  ).take(_continueCards).toList();

  /// The live categories, in the provider's order.
  Future<List<LiveCategory>> liveCategories() async => [
    for (final o in await _rows('categories?select=ext_id,name,name_en,name_he&kind=eq.live&order=position'))
      LiveCategory(o.getInt('ext_id'), o.getString('name'), o.text('name_en'), o.text('name_he')),
  ];

  /// The available channels by number. shortcut: one call, the API's 1,000-row cap (583 today); page it if the provider passes 1,000.
  Future<List<Channel>> channels() async => [
    for (final o in await _rows('channels?select=$channelColumns&available=is.true&order=num.nullslast,id&limit=1000')) channel(o),
  ];

  /// The ids of the user's favourite channels.
  Future<Set<int>> favoriteChannels() async => {
    for (final o in await _rows('channel_prefs?select=channel_id&favorite=is.true')) o.getInt('channel_id'),
  };

  Future<void> setFavorite(int channelId, bool favorite) =>
      _api.post('channel_prefs?on_conflict=user_id,channel_id', favoriteBody(channelId, favorite), prefer: _upsert);

  /// Bumped on every watchlist change, so the Watchlist page reads it again.
  ValueListenable<int> get watchlistVersion => _watchlistVersion;
  final _watchlistVersion = ValueNotifier(0);

  /// The user's rating and watchlist entry for a title's card.
  Future<Marks> marks(Title title) async {
    // Pre-filled from WTW (P4-6): the user's WTW rating shows until they rate here.
    // It cannot be cleared from WTV: clearing removes only the WTV rating.
    // `title.id` is the card's copy; `rank` writes a row for every copy of a title.
    Future<String?> wtwReaction() async {
      try {
        return (await _rows('rankings?select=wtw_reaction&title_id=eq.${title.id}')).firstOrNull?.text('wtw_reaction');
      } on Exception {
        return null;
      }
    }

    final stored = _rows(
      'ratings?select=rating&title_id=eq.${title.cardId}',
    ).then((rows) => rows.firstOrNull?.text('rating'));
    final listed = _rows('watchlist?select=title_id&title_id=eq.${title.cardId}').then((rows) => rows.isNotEmpty);
    final wtw = wtwReaction();
    await Future.wait([stored, listed, wtw]);
    return Marks(rating: rating(await stored) ?? fromWtw(await wtw), onWatchlist: await listed);
  }

  /// Rated titles count as seen: a change reloads Home's and the sections' rows.
  ValueListenable<int> get ratingsVersion => _ratingsVersion;
  final _ratingsVersion = ValueNotifier(0);

  /// Rates a title's card, or clears its rating with null.
  Future<void> setRating(Title title, Rating? rating) async {
    if (rating == null) {
      await _api.delete('ratings?title_id=eq.${title.cardId}');
    } else {
      await _api.post('ratings?on_conflict=user_id,title_id', ratingBody(title.cardId, rating), prefer: _upsert);
    }
    _ratingsVersion.value++;
  }

  /// How many titles the kind has in all, per provider category and per genre: (tag, id) to count.
  Future<Map<(String, int), int>> categoryCounts(Kind kind) async => {
    for (final o in await _rows('rpc/category_counts?p_kind=${kind.db}')) (o.getString('tag'), o.getInt('id')): o.getInt('n'),
  };

  Future<void> setWatchlist(Title title, bool on) async {
    if (on) {
      await _api.post(
        'watchlist?on_conflict=user_id,title_id',
        jsonEncode({'title_id': title.cardId}),
        prefer: 'resolution=ignore-duplicates,return=minimal',
      );
    } else {
      await _api.delete('watchlist?title_id=eq.${title.cardId}');
    }
    _watchlistVersion.value++;
  }

  /// The watchlist, last added first; titles the provider no longer has are left out.
  /// shortcut: entries (and ratings) point at the card's copy at the time. If the provider drops
  /// that copy, the regroup makes another copy the card and the entry no longer shows, though the
  /// title is still there; key them by TMDB id if that happens often.
  Future<List<Title>> watchlist() async => [
    for (final o in await _rows('watchlist?select=added_at,titles!inner($_titleColumns)&titles.available=is.true&order=added_at.desc'))
      if (o.optObject('titles') case final t?) title(t),
  ];

  /// What the user hid on the Live TV page.
  Future<LiveFilters> liveFilters() async {
    Future<Set<int>> hidden(String path, String id) async => {for (final o in await _rows(path)) o.getInt(id)};
    final channels = hidden('channel_prefs?select=channel_id&hidden=is.true', 'channel_id');
    final groups = hidden('live_group_prefs?select=category_id&hidden=is.true', 'category_id');
    final radio = _rows('user_settings?select=show_radio').then(
      (rows) => rows.firstOrNull?.optBoolean('show_radio', true) ?? true,
    );
    await Future.wait([channels, groups, radio]);
    return LiveFilters(hiddenChannels: await channels, hiddenGroups: await groups, showRadio: await radio);
  }

  Future<void> setChannelHidden(int channelId, bool hidden) =>
      _api.post('channel_prefs?on_conflict=user_id,channel_id', hiddenBody(channelId, hidden), prefer: _upsert);

  Future<void> setGroupHidden(int categoryId, bool hidden) =>
      _api.post('live_group_prefs?on_conflict=user_id,category_id', groupBody(categoryId, hidden), prefer: _upsert);

  Future<void> setShowRadio(bool show) =>
      _api.post('user_settings?on_conflict=user_id', jsonEncode({'show_radio': show}), prefer: _upsert);

  /// A section's rows: its provider categories, then `extra` (genres), newest first; empty ones left out.
  Future<List<(Category, List<Title>)>> rows(Kind kind, {int perRow = 10, List<Category> extra = const []}) async {
    final all = await Future.wait([
      for (final c in [...await categories(kind), ...extra])
        _rowRequests.withPermit(() async => (c, await latest(kind, category: c.id, limit: perRow, genre: c.genre))),
    ]);
    return [
      for (final row in all)
        if (row.$2.isNotEmpty) row,
    ];
  }
}

// Inside `Catalog`, `progress` is the method: this is the row reader of that name.
const _progressRow = progress;

/// Rows and grids show cards: one title per group of copies (#56). A card's
/// categories and date are those of all its copies.
String _cards(Kind kind, int? category, {bool genre = false}) {
  final filter = category == null
      ? ''
      : (genre ? '&tmdb_genre_ids=cs.%7B$category%7D' : '&group_category_ids=cs.%7B$category%7D');
  return 'titles?select=$_titleColumns&kind=eq.${kind.db}&available=is.true&is_primary=is.true$filter';
}

String latestPath(Kind kind, int? category, int limit, {bool genre = false}) =>
    '${_cards(kind, category, genre: genre)}&order=${Sort.added.order(hebrew: false)}&limit=$limit';

String recommendedPath(Category category, {required int offset, required int limit}) =>
    'rpc/recommended_page?select=$_titleColumns&p_kind=${category.kind.db}'
    '${category.all ? '' : '&${category.genre ? 'p_genre' : 'p_category'}=${category.id}'}'
    '&p_offset=$offset&p_limit=$limit';

String pagePath(Category category, Sort sort, {required bool hebrew, required int offset, required int limit}) =>
    '${_cards(category.kind, category.all ? null : category.id, genre: category.genre)}'
    '&order=${sort.order(hebrew: hebrew)}&offset=$offset&limit=$limit';

const _titleColumns =
    'id,ext_id,container_ext,kind,name,title_en,title_he,year,plot,overview_en,overview_he,tmdb_genre_ids,certification,'
    'tmdb_backdrop,tmdb_poster,backdrop_url,poster_url,runtime_min,tmdb_runtime_min,director,cast_names,tmdb_rating,original_language,group_id,wtw_match';

Kind _kindOf(String db) => Kind.values.where((k) => k.db == db).firstOrNull ?? (throw ApiException('Unknown kind: $db'));

String _pKind(Kind? kind) => kind == null ? '' : '&p_kind=${kind.db}';

/// Java's `URLEncoder.encode` with a space as `%20`: the paths are the TV app's byte for byte.
String _urlEncode(String text) =>
    Uri.encodeQueryComponent(text).replaceAll('+', '%20').replaceAll('%2A', '*').replaceAll('~', '%7E');

/// A title row from the REST API.
Title title(JsonObject o) => Title(
  id: o.getInt('id'),
  extId: o.getInt('ext_id'),
  containerExt: o.text('container_ext'),
  kind: _kindOf(o.getString('kind')),
  name: o.getString('name'),
  nameEn: o.text('title_en'),
  nameHe: o.text('title_he'),
  year: o._int('year'),
  plot: o.text('plot'),
  overviewEn: o.text('overview_en'),
  overviewHe: o.text('overview_he'),
  genreIds: o.optArray('tmdb_genre_ids')?.ints() ?? const [],
  certification: o.text('certification'),
  tmdbBackdrop: o.text('tmdb_backdrop'),
  tmdbPoster: o.text('tmdb_poster'),
  providerBackdrop: o.text('backdrop_url'),
  providerPoster: o.text('poster_url'),
  runtimeMin: o._int('tmdb_runtime_min') ?? o._int('runtime_min'),
  director: o.text('director'),
  castNames: o.text('cast_names'),
  tmdbRating: o.isNull('tmdb_rating') ? null : o.getDouble('tmdb_rating'),
  originalLanguage: o.text('original_language'),
  groupId: o._int('group_id'),
  match: o._int('wtw_match'),
);

/// Ids of the cards of copies in `rows` whose card is not in `rows` itself.
Set<int> cardsMissingFor(List<JsonObject> rows) {
  final present = {
    for (final o in rows)
      if (o.optBoolean('is_primary')) o.getInt('id'),
  };
  return {
    for (final o in rows)
      if (!o.optBoolean('is_primary') && !o.isNull('group_id'))
        if (!present.contains(o.getInt('group_id'))) o.getInt('group_id'),
  };
}

/// Cards from a person's title rows: available cards only, newest first, each once.
List<Title> personCards(List<JsonObject> rows) {
  final seen = <int>{};
  final cards = [
    for (final o in rows)
      if (o.optBoolean('is_primary') && o.optBoolean('available')) title(o),
  ].where((t) => seen.add(t.id)).toList();
  // No year sorts last.
  int year(Title t) => t.year ?? -(1 << 31);
  return cards..sort((a, b) => year(a) != year(b) ? year(b).compareTo(year(a)) : a.id.compareTo(b.id));
}

/// Cards whose names start with (`prefix`) or contain `query`, over the three
/// names. The value is quoted for PostgREST's `or=(…)` syntax (commas,
/// parentheses and quotes are text) and URL-encoded. `*` is PostgREST's ilike
/// wildcard; `%` and `_` in the query are escaped so they match themselves.
String searchPath(String query, {required bool hebrew, required bool prefix, Kind? kind}) {
  final literal = query.replaceAll('*', '').replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  // Inside a quoted PostgREST value, backslashes and quotes are escaped once more.
  final quotedBody = literal.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final pattern = '"${prefix ? '' : '*'}$quotedBody*"';
  final or = '(sort_name_en.ilike.$pattern,sort_name_he.ilike.$pattern,name.ilike.$pattern)';
  return 'titles?select=$_titleColumns&is_primary=is.true&available=is.true${kind == null ? '' : '&kind=eq.${kind.db}'}'
      '&or=${_urlEncode(or)}'
      '&order=${Sort.name.order(hebrew: hebrew)}&limit=$searchLimit';
}

const searchLimit = 60;

/// The actors search, the query URL-encoded.
String peopleSearchPath(String query, Kind? kind) => 'rpc/search_people?p_query=${_urlEncode(query)}${_pKind(kind)}';

/// Rows read for Continue watching: a series has a row per episode watched.
const _continueRows = 200;
const _continueCards = 20;

/// Names that start with the query first (each fetched on its own, so the limit cannot cut them), then the rest.
List<Title> mergeSearch(List<Title> startsWith, List<Title> contains) {
  final seen = <int>{};
  return [...startsWith, ...contains].where((t) => seen.add(t.id)).take(searchLimit).toList();
}

const episodesPage = 1000;

String episodesPath(int seriesId, {required int offset}) =>
    'episodes?select=id,ext_id,container_ext,season,episode,name,name_en,name_he,overview_en,overview_he,plot,duration_secs,tmdb_still,image_url'
    '&title_id=eq.$seriesId&available=is.true&order=season,episode,id&offset=$offset&limit=$episodesPage';

Episode episode(JsonObject o) => Episode(
  id: o.getInt('id'),
  extId: o.getInt('ext_id'),
  containerExt: o.text('container_ext'),
  season: o.getInt('season'),
  number: o.getInt('episode'),
  nameEn: o.text('name_en'),
  nameHe: o.text('name_he'),
  overviewEn: o.text('overview_en'),
  overviewHe: o.text('overview_he'),
  plot: o.text('plot'),
  durationSecs: o._int('duration_secs'),
  tmdbStill: o.text('tmdb_still'),
  providerImage: o.text('image_url'),
  providerName: o.text('name'),
);

/// One episode per season and number, in order. The provider lists some
/// several times: an older upload of the same file, or another series'
/// episode filed under this one. The copy named after the series wins, then
/// the newest (the provider's ids grow).
List<Episode> oneEach(List<Episode> episodes, String seriesName) {
  bool named(Episode e) => e.providerName?.startsWith(seriesName) == true;
  final best = <(int, int), Episode>{};
  for (final e in episodes) {
    final other = best[(e.season, e.number)];
    if (other == null || (named(e) != named(other) ? named(e) : e.extId > other.extId)) best[(e.season, e.number)] = e;
  }
  return best.values.toList();
}

/// Copies from rows of `titles`; a copy is 4K when it is in one of `fourK` (categories named with "4K").
List<Copy> copiesFrom(Title title, List<JsonObject> rows, Set<int> fourK) {
  final copies = [
    for (final o in rows)
      Copy(
        o.getInt('id'),
        o.getInt('ext_id'),
        o.text('container_ext'),
        (o.optArray('category_ids')?.ints() ?? const []).any(fourK.contains),
      ),
  ];
  if (copies.isEmpty) copies.add(title.asCopy());
  // The 4K ones first; each kind keeps its order.
  return [...copies.where((c) => c.is4k), ...copies.where((c) => !c.is4k)];
}

/// Button labels for the copies: "4K", "HD", and "HD 1", "HD 2" when there are several HD copies.
List<String> copyLabels(List<Copy> copies) {
  final numberHd = copies.where((c) => !c.is4k).length > 1;
  var hd = 0;
  return [for (final c in copies) c.is4k ? '4K' : (numberHd ? 'HD ${++hd}' : 'HD')];
}

extension JsonRows on JsonArray {
  List<JsonObject> objects() => [
    for (final value in this) value is JsonObject ? value : throw const FormatException('Not a JSON object'),
  ];
}

extension JsonText on JsonObject {
  int? _int(String key) => isNull(key) ? null : getInt(key);

  /// The string at `key`, or null for a missing, null or blank value.
  String? text(String key) {
    if (isNull(key)) return null;
    final text = optString(key);
    return text.trim().isEmpty ? null : text;
  }
}

const _upsert = 'resolution=merge-duplicates,return=minimal';
