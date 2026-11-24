import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wtv/data/api.dart';
import 'package:wtv/data/catalog.dart';
import 'package:wtv/data/json.dart';
import 'package:wtv/data/marks.dart';
import 'package:wtv/data/session.dart';

JsonObject row([JsonObject more = const {}]) => {'id': 10, 'ext_id': 387982, 'kind': 'movie', 'name': 'החיה', ...more};

String decodedOr(String path) => Uri.decodeComponent(path.split('&or=')[1].split('&').first);

void main() {
  test('a full row parses, nulls and blanks become null', () {
    final t = title(
      row({'title_en': 'The Beast', 'title_he': ' ', 'year': 2026, 'plot': null, 'tmdb_genre_ids': [28, 53], 'certification': 'R'}),
    );
    expect(t.id, 10);
    expect(t.kind, Kind.movie);
    expect(t.nameEn, 'The Beast');
    expect(t.nameHe, isNull);
    expect(t.year, 2026);
    expect(t.plot, isNull);
    expect(t.genreIds, [28, 53]);
    expect(t.certification, 'R');
  });

  test('details take the TMDB runtime first and read group and rating, missing and null alike', () {
    final t = title(row({'runtime_min': 99, 'tmdb_runtime_min': 101, 'tmdb_rating': 6.4, 'group_id': 7, 'container_ext': 'mkv'}));
    expect(t.runtimeMin, 101);
    expect(t.tmdbRating, closeTo(6.4, 0.0001));
    expect(t.groupId, 7);
    expect(t.extId, 387982);
    expect(t.containerExt, 'mkv');
    expect(title(row({'runtime_min': 99, 'tmdb_runtime_min': null})).runtimeMin, 99);
    expect(title(row({'group_id': null})).groupId, isNull);
    expect(title(row()).groupId, isNull);
  });

  test('copies list 4K first and at least the title itself', () {
    final t = title(row({'container_ext': 'mp4'}));
    JsonObject copy(int id, List<int> cats) => {'id': id, 'ext_id': id * 10, 'container_ext': 'mkv', 'category_ids': cats};
    final copies = copiesFrom(
      t,
      [
        copy(1, [449]),
        copy(2, [99, 449]),
      ],
      {99},
    );
    expect([for (final c in copies) c.id], [2, 1]);
    expect([for (final c in copies) c.is4k], [true, false]);
    expect(copiesFrom(t, [], {99}), [const Copy(10, 387982, 'mp4', false)]);
  });

  test("an episode parses, and its name and synopsis fall back like a title's", () {
    final e = episode({
      'id': 5,
      'ext_id': 369702,
      'season': 1,
      'episode': 3,
      'name_en': 'Pilot',
      'name_he': null,
      'overview_en': 'EN',
      'plot': 'PROVIDER',
      'duration_secs': 2555,
      'tmdb_still': '/s.jpg',
      'image_url': 'https://p/e.jpg',
    });
    expect(e.season, 1);
    expect(e.number, 3);
    expect(e.durationSecs, 2555);
    expect(e.displayName(hebrew: false), 'Pilot');
    expect(e.displayName(hebrew: true), 'Pilot');
    expect(e.synopsis(hebrew: false), 'EN');
    expect(e.synopsis(hebrew: true), 'PROVIDER');
    final onlyHebrew = episode({'id': 7, 'ext_id': 2, 'season': 1, 'episode': 5, 'overview_he': 'HE'});
    expect(onlyHebrew.synopsis(hebrew: false), 'HE');
    expect(e.image, 'https://image.tmdb.org/t/p/w300/s.jpg');
    expect(episode({'id': 6, 'ext_id': 1, 'season': 1, 'episode': 4}).displayName(hebrew: false), isNull);
  });

  test('episodes are read in pages of 1000 in a stable order', () {
    final path = episodesPath(15791, offset: 1000);
    for (final part in ['&title_id=eq.15791', '&available=is.true', '&order=season,episode,id', '&offset=1000', '&limit=1000']) {
      expect(path, contains(part));
    }
  });

  test("a person's titles are available cards only, each once, newest first", () {
    JsonObject t(int id, int? year, {bool primary = true, bool available = true}) =>
        row({'year': year, 'is_primary': primary, 'available': available, 'id': id});
    final cards = personCards([
      t(1, 2019),
      t(2, 2025),
      t(3, 2025, primary: false),
      t(4, 2020, available: false),
      t(2, 2025),
      t(5, null),
    ]);
    expect([for (final c in cards) c.id], [2, 1, 5]);
  });

  test('a copy whose card is missing is resolved to its card', () {
    JsonObject t(int id, bool primary, int? group) => row({'is_primary': primary, 'group_id': group, 'available': true, 'id': id});
    expect(cardsMissingFor([t(1, true, 1), t(2, false, 1), t(3, false, 9), t(4, false, null)]), {9});
  });

  test('search quotes the query for the or filter and encodes it', () {
    final or = decodedOr(searchPath('bad, (boys) "x"', hebrew: false, prefix: false));
    const p = r'"*bad, (boys) \"x\"*"';
    expect(or, '(sort_name_en.ilike.$p,sort_name_he.ilike.$p,name.ilike.$p)');
    final path = searchPath('x', hebrew: false, prefix: false);
    expect(path, contains('&is_primary=is.true'));
    expect(path, contains('&order=sort_name_en.asc,id'));
    expect(searchPath('שוטר', hebrew: true, prefix: false), contains('&order=sort_name_he.asc,id'));
  });

  test('a section search keeps to its kind and actors are searched by an encoded name', () {
    expect(searchPath('x', hebrew: false, prefix: false, kind: Kind.movie), contains('&kind=eq.movie&'));
    expect(searchPath('x', hebrew: false, prefix: false), isNot(contains('&kind=')));
    expect(peopleSearchPath('tom h&a', Kind.series), 'rpc/search_people?p_query=tom%20h%26a&p_kind=series');
    expect(peopleSearchPath('brad', null), 'rpc/search_people?p_query=brad');
  });

  test('a prefix search has no leading wildcard', () {
    expect(decodedOr(searchPath('bad', hebrew: false, prefix: true)), startsWith('(sort_name_en.ilike."bad*",'));
  });

  test('percent, underscore and backslash in a query match themselves', () {
    // SQL LIKE escapes are \% \_ \; inside a quoted PostgREST value each backslash is doubled.
    final or = decodedOr(searchPath(r'100%_a\b', hebrew: false, prefix: false));
    expect(or, startsWith(r'(sort_name_en.ilike."*100\\%\\_a\\\\b*",'));
  });

  test('names starting with the query come first, each once, within the limit', () {
    Title t(int id) => title(row({'id': id}));
    expect([for (final m in mergeSearch([t(3), t(4)], [t(1), t(3), t(2), t(4)])) m.id], [3, 4, 1, 2]);
    expect(mergeSearch([for (var i = 0; i < 50; i++) t(i)], [for (var i = 0; i < 50; i++) t(100 + i)]), hasLength(searchLimit));
  });

  test('copy labels number several HD copies only', () {
    const k = Copy(1, 1, null, true);
    const hd = Copy(2, 2, null, false);
    expect(copyLabels([k, hd]), ['4K', 'HD']);
    expect(copyLabels([k, hd, const Copy(3, 2, null, false)]), ['4K', 'HD 1', 'HD 2']);
    expect(copyLabels([hd]), ['HD']);
  });

  test('missing optional columns do not fail', () {
    final t = title(row());
    expect(t.nameEn, isNull);
    expect(t.year, isNull);
    expect(t.genreIds, isEmpty);
  });

  test('names come from TMDB in the app language, else from the provider', () {
    final t = title(row({'title_en': 'The Beast', 'title_he': 'החיה (TMDB)'}));
    expect(t.displayName(hebrew: false), 'The Beast');
    expect(t.displayName(hebrew: true), 'החיה (TMDB)');
    expect(title(row()).displayName(hebrew: false), 'החיה');
  });

  test('synopsis falls back from English to the provider, and from Hebrew to the provider then English', () {
    final all = title(row({'overview_en': 'EN', 'overview_he': 'HE', 'plot': 'PROVIDER'}));
    expect(all.synopsis(hebrew: false), 'EN');
    expect(all.synopsis(hebrew: true), 'HE');
    final onlyProvider = title(row({'plot': 'PROVIDER'}));
    expect(onlyProvider.synopsis(hebrew: false), 'PROVIDER');
    expect(onlyProvider.synopsis(hebrew: true), 'PROVIDER');
    final onlyEnglish = title(row({'overview_en': 'EN'}));
    expect(onlyEnglish.synopsis(hebrew: true), 'EN');
    // The database drops the provider's plot when TMDB has a Hebrew overview.
    final onlyHebrew = title(row({'overview_he': 'HE'}));
    expect(onlyHebrew.synopsis(hebrew: false), 'HE');
  });

  test('images use the TMDB backdrop first and provider images after', () {
    final tmdb = title(row({'tmdb_backdrop': '/b.jpg', 'backdrop_url': 'https://p/b.jpg'}));
    expect(tmdb.cardImage, 'https://image.tmdb.org/t/p/w780/b.jpg');
    expect(tmdb.heroImage, 'https://image.tmdb.org/t/p/w1280/b.jpg');
    final provider = title(row({'backdrop_url': 'https://p/b.jpg', 'poster_url': 'https://p/p.jpg'}));
    expect(provider.cardImage, 'https://p/b.jpg');
    expect(title(row({'poster_url': 'https://p/p.jpg'})).cardImage, 'https://p/p.jpg');
    expect(title(row({'poster_url': 'https://p/p.jpg'})).heroImage, isNull);
  });

  test('category and genre labels fall back to what exists', () {
    const netflix = Category(1, Kind.movie, 'Netflix - נטפליקס', 'Netflix', 'נטפליקס');
    expect(netflix.label(hebrew: false), 'Netflix');
    expect(netflix.label(hebrew: true), 'נטפליקס');
    expect(const Category(1, Kind.movie, 'קטגוריה', null, null).label(hebrew: false), 'קטגוריה');
    expect(const Genre('Drama', null).label(hebrew: true), 'Drama');
  });

  test('sort orders end on id and name follows the language', () {
    // Date added is the newest copy's.
    expect(Sort.added.order(hebrew: false), 'group_added_at.desc.nullslast,id');
    expect(Sort.name.order(hebrew: false), 'sort_name_en.asc,id');
    expect(Sort.name.order(hebrew: true), 'sort_name_he.asc,id');
    for (final s in Sort.values) {
      expect(s.order(hebrew: false), endsWith(',id'), reason: '$s');
    }
  });

  test('a grid page asks for one category, available titles, the order, offset and limit', () {
    final path = pagePath(const Category(185, Kind.series, 'Netflix', null, null), Sort.rating, hebrew: false, offset: 120, limit: 60);
    expect(path, startsWith('titles?select='));
    for (final part in [
      '&kind=eq.series',
      '&available=is.true',
      '&is_primary=is.true',
      '&group_category_ids=cs.%7B185%7D',
      '&order=tmdb_rating.desc.nullslast,id',
      '&offset=120',
      '&limit=60',
    ]) {
      expect(path, contains(part));
    }
  });

  test('rows ask for cards, newest copy first, in a category or all', () {
    final inCategory = latestPath(Kind.movie, 99, 10);
    for (final part in [
      '&kind=eq.movie',
      '&is_primary=is.true',
      '&group_category_ids=cs.%7B99%7D',
      '&order=group_added_at.desc.nullslast,id',
      '&limit=10',
    ]) {
      expect(inCategory, contains(part));
    }
    expect(latestPath(Kind.series, null, 10), isNot(contains('category_ids')));
    expect(latestPath(Kind.series, 18, 10, genre: true), contains('&tmdb_genre_ids=cs.%7B18%7D'));
  });

  test("poster prefers TMDB, then the provider's", () {
    expect(title(row({'tmdb_poster': '/p.jpg', 'poster_url': 'https://p/p.jpg'})).posterImage, 'https://image.tmdb.org/t/p/w342/p.jpg');
    expect(title(row({'poster_url': 'https://p/p.jpg'})).posterImage, 'https://p/p.jpg');
  });

  test('a recommended page asks the server function for one category, offset and limit', () {
    final path = recommendedPath(const Category(7, Kind.movie, 'Kids', null, null), offset: 60, limit: 60);
    expect(path, startsWith('rpc/recommended_page?select='));
    for (final part in ['&p_kind=movie', '&p_category=7', '&p_offset=60', '&p_limit=60']) {
      expect(path, contains(part));
    }
  });

  test("a genre's page filters by TMDB genre, in both orders", () {
    const drama = Category(18, Kind.movie, 'Drama', 'Drama', null, genre: true);
    final page = pagePath(drama, Sort.year, hebrew: false, offset: 0, limit: 60);
    expect(page, contains('&tmdb_genre_ids=cs.%7B18%7D'));
    expect(page, isNot(contains('category_ids')));
    final recommended = recommendedPath(drama, offset: 0, limit: 60);
    expect(recommended, contains('&p_genre=18'));
    expect(recommended, isNot(contains('p_category')));
  });

  test('All movies is the whole kind, in both orders', () {
    const all = Category(0, Kind.movie, 'All movies', null, null, all: true);
    final page = pagePath(all, Sort.name, hebrew: false, offset: 0, limit: 60);
    expect(page, contains('&kind=eq.movie'));
    expect(page, isNot(contains('_ids=cs.')));
    final recommended = recommendedPath(all, offset: 0, limit: 60);
    expect(recommended, isNot(anyOf(contains('p_category'), contains('p_genre'))));
  });

  // Not in the TV app's tests: what the port itself adds or had to write anew.

  test('paths are encoded as Java does, and rows that are not objects are refused', () {
    expect(peopleSearchPath("a*b~c'd(e)!+", null), 'rpc/search_people?p_query=a*b%7Ec%27d%28e%29%21%2B');
    expect(() => [1].objects(), throwsFormatException);
    expect(() => title(row({'kind': 'live'})), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Unknown kind: live')));
    expect(const Category(1, Kind.movie, 'A', null, null, genre: true).copyWith(count: 5).count, 5);
    expect(const Category(1, Kind.movie, 'A', null, null, genre: true).copyWith(count: 5).genre, isTrue);
  });

  group('Catalog', () {
    const rest = 'https://db.test/rest/v1/';
    final calls = <http.Request>[];
    // What the server answers, by the path and query after rest/v1/ (or functions/v1/).
    late Object? Function(String path) server;
    late Catalog catalog;

    List<String> paths() => [for (final c in calls) c.url.toString().replaceFirst(RegExp('^https://db.test/[a-z]+/v1/'), '')];

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        'session': jsonEncode({
          'access_token': 'a1',
          'refresh_token': 'r1',
          'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        }),
      });
      calls.clear();
      final client = MockClient((request) async {
        calls.add(request);
        final answer = server(paths().last);
        if (answer is http.Response) return answer;
        return http.Response.bytes(utf8.encode(jsonEncode(answer)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      catalog = Catalog(Api(Session(client, url: 'https://db.test', key: 'public-key'), client, url: 'https://db.test', key: 'public-key'));
    });

    test('categories are read once, also when asked twice at once; a failed read is not kept', () async {
      server = (_) => http.Response('', 500);
      await expectLater(catalog.categories(Kind.movie), throwsA(isA<ApiException>()));
      server = (_) => [
        {'ext_id': 99, 'name': '4K UHD', 'name_en': '4K', 'name_he': ''},
      ];
      final [first, second] = await Future.wait([catalog.categories(Kind.movie), catalog.categories(Kind.movie)]);
      expect(second, same(first));
      expect(first.single.label(hebrew: true), '4K UHD');
      expect(calls, hasLength(2));
      expect(calls.last.url.toString(), '${rest}categories?select=ext_id,name,name_en,name_he&kind=eq.movie&order=position');
    });

    test("genres become a kind's categories, by name", () async {
      server = (_) => [
        {'kind': 'movie', 'id': 18, 'name_en': 'Drama', 'name_he': 'דרמה'},
        {'kind': 'series', 'id': 10759, 'name_en': 'Action & Adventure', 'name_he': null},
        {'kind': 'movie', 'id': 28, 'name_en': 'Action', 'name_he': 'פעולה'},
      ];
      final genres = await catalog.genreCategories(Kind.movie, hebrew: false);
      expect([for (final g in genres) (g.id, g.name, g.genre)], [(28, 'Action', true), (18, 'Drama', true)]);
      expect((await catalog.genres())[(Kind.series, 10759)]!.label(hebrew: true), 'Action & Adventure');
      expect(paths(), ['genres?select=kind,id,name_en,name_he']);
    });

    test('search asks for names that start with the query and names that contain it', () async {
      server = (path) => [
        for (final id in Uri.decodeComponent(path).contains('"*') ? [1, 3, 2] : [3]) row({'id': id}),
      ];
      expect([for (final t in await catalog.search(' be*ast ', hebrew: false, kind: Kind.movie)) t.id], [3, 1, 2]);
      expect(paths(), [
        searchPath('beast', hebrew: false, prefix: true, kind: Kind.movie),
        searchPath('beast', hebrew: false, prefix: false, kind: Kind.movie),
      ]);
      expect(await catalog.search(' * ', hebrew: false), isEmpty);
      expect(await catalog.searchPeople('a'), isEmpty);
      expect(calls, hasLength(2));
    });

    test("a section's rows: categories then genres, empty ones left out, six requests at once at most", () async {
      var running = 0, most = 0;
      final release = Completer<void>();
      final client = MockClient((request) async {
        final path = request.url.toString().replaceFirst(rest, '');
        if (path.startsWith('categories?')) {
          return http.Response(jsonEncode([for (var id = 1; id <= 9; id++) {'ext_id': id, 'name': 'c$id'}]), 200);
        }
        calls.add(request);
        most = max(most, ++running);
        await release.future;
        running--;
        return http.Response(jsonEncode(path.contains('%7B2%7D') ? [] : [row()]), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      catalog = Catalog(Api(Session(client, url: 'https://db.test', key: 'public-key'), client, url: 'https://db.test', key: 'public-key'));
      const drama = Category(18, Kind.movie, 'Drama', 'Drama', null, genre: true);
      final pending = catalog.rows(Kind.movie, perRow: 5, extra: [drama]);
      await pumpEventQueue();
      expect(running, 6);
      release.complete();
      final rows = await pending;
      expect([for (final (category, _) in rows) category.id], [1, 3, 4, 5, 6, 7, 8, 9, 18]);
      expect(rows.last.$2.single.id, 10);
      expect(most, 6);
      expect(paths().first, latestPath(Kind.movie, 1, 5));
      expect(paths().last, latestPath(Kind.movie, 18, 5, genre: true));
    });

    test('episodes are read page by page, one per season and number', () async {
      server = (path) => path.contains('&offset=0&')
          ? [for (var i = 1; i <= 1000; i++) {'id': i, 'ext_id': i, 'season': 1, 'episode': i}]
          : [
              {'id': 1001, 'ext_id': 1001, 'season': 1, 'episode': 1000},
              {'id': 1002, 'ext_id': 1002, 'season': 2, 'episode': 1},
            ];
      final episodes = await catalog.episodes(title(row({'kind': 'series'})));
      expect(paths(), [episodesPath(10, offset: 0), episodesPath(10, offset: 1000)]);
      expect(episodes, hasLength(1001));
      expect([for (final e in episodes.skip(999)) e.id], [1001, 1002]);
    });

    test("a person's titles: a copy whose card was not among the rows is read as its card", () async {
      server = (path) => path.startsWith('title_cast?')
          ? [
              {'titles': row({'id': 1, 'is_primary': true, 'available': true, 'group_id': 1})},
              {'titles': row({'id': 3, 'is_primary': false, 'available': true, 'group_id': 9})},
              {'titles': null},
            ]
          : [row({'id': 9, 'is_primary': true, 'available': true, 'group_id': 9, 'year': 2026})];
      expect([for (final t in await catalog.personTitles(287)) t.id], [9, 1]);
      expect(paths().first, startsWith('title_cast?select=titles(id,ext_id,'));
      expect(paths().first, endsWith(',wtw_match,is_primary,available)&person_id=eq.287'));
      expect(paths().last, endsWith(',wtw_match,is_primary,available&id=in.(9)'));
    });

    test("marks: the user's rating first, then WTW's reaction; a failed WTW read is no rating", () async {
      final t = title(row({'group_id': 7}));
      var rated = <JsonObject>[];
      Object? wtw = [
        {'wtw_reaction': 'loved'},
      ];
      server = (path) => path.startsWith('ratings?')
          ? rated
          : path.startsWith('watchlist?')
          ? [
              {'title_id': 7},
            ]
          : wtw;
      var marks = await catalog.marks(t);
      expect((marks.rating, marks.onWatchlist), (Rating.love, true));
      expect(paths(), [
        'ratings?select=rating&title_id=eq.7',
        'watchlist?select=title_id&title_id=eq.7',
        'rankings?select=wtw_reaction&title_id=eq.10',
      ]);
      rated = [
        {'rating': 'dislike'},
      ];
      expect((await catalog.marks(t)).rating, Rating.dislike);
      rated = [];
      wtw = http.Response('', 500);
      marks = await catalog.marks(t);
      expect((marks.rating, marks.onWatchlist), (null, true));
      expect(marks.copyWith(rating: () => Rating.like).rating, Rating.like);
      expect(marks.copyWith(onWatchlist: false).onWatchlist, isFalse);
      expect(const Marks(rating: Rating.love).copyWith(rating: () => null).rating, isNull);
    });

    test('rating and watchlist changes are saved on the card and bump their versions', () async {
      final t = title(row({'group_id': 7}));
      server = (_) => http.Response('', 204);
      await catalog.setRating(t, Rating.like);
      expect((calls.last.method, paths().last), ('POST', 'ratings?on_conflict=user_id,title_id'));
      expect(calls.last.headers['Prefer'], 'resolution=merge-duplicates,return=minimal');
      expect(jsonDecode(calls.last.body), {'title_id': 7, 'rating': 'like'});
      await catalog.setRating(t, null);
      expect((calls.last.method, paths().last), ('DELETE', 'ratings?title_id=eq.7'));
      expect(catalog.ratingsVersion.value, 2);
      await catalog.setWatchlist(t, true);
      expect((calls.last.method, paths().last), ('POST', 'watchlist?on_conflict=user_id,title_id'));
      expect(calls.last.headers['Prefer'], 'resolution=ignore-duplicates,return=minimal');
      expect(calls.last.body, '{"title_id":7}');
      await catalog.setWatchlist(t, false);
      expect((calls.last.method, paths().last), ('DELETE', 'watchlist?title_id=eq.7'));
      expect(catalog.watchlistVersion.value, 2);
      // A change that was not saved is not announced.
      server = (_) => http.Response('', 500);
      await expectLater(catalog.setWatchlist(t, true), throwsA(isA<ApiException>()));
      expect(catalog.watchlistVersion.value, 2);
    });

    test('positions: saved, read over all copies, cleared, and the Continue watching row', () async {
      final t = title(row({'group_id': 7}));
      server = (path) => path.contains('titles!inner(id,')
          ? [
              {'title_id': 10, 'position_secs': 600, 'duration_secs': 6000, 'episodes': null, 'titles': row({'group_id': 7})},
            ]
          : path.startsWith('progress?select=')
          ? [
              {'title_id': 11, 'position_secs': 300, 'duration_secs': null, 'episodes': {'season': 2, 'episode': 3}},
            ]
          : http.Response('', 204);
      await catalog.saveProgress(10, null, 90, 6000);
      expect((calls.last.method, paths().last), ('POST', 'progress?on_conflict=user_id,title_id,episode_id'));
      expect(calls.last.body, '{"title_id":10,"episode_id":null,"position_secs":90,"duration_secs":6000}');
      final progress = await catalog.progress(t);
      expect((progress.single.titleId, progress.single.season, progress.single.episode), (11, 2, 3));
      expect(
        paths().last,
        'progress?select=title_id,position_secs,duration_secs,episodes(season,episode),titles!inner(group_id)&titles.group_id=eq.7&order=updated_at.desc',
      );
      await catalog.clearProgress([10, 11]);
      expect((calls.last.method, paths().last), ('DELETE', 'progress?title_id=in.(10,11)'));
      await catalog.clearProgress([]);
      expect(calls, hasLength(3));
      expect((await catalog.continueWatching()).single.progress.positionSecs, 600);
      expect(paths().last, endsWith(',wtw_match)&titles.available=is.true&order=updated_at.desc&limit=200'));
    });

    test('Live TV: channels, favourites and what is hidden; radio shows unless turned off', () async {
      server = (path) => path.startsWith('channels?')
          ? [
              {'id': 5, 'ext_id': 123, 'name': 'Kan 11', 'num': 11},
            ]
          : path.contains('favorite=is.true') || path.contains('channel_prefs?select=channel_id&hidden')
          ? [
              {'channel_id': 5},
            ]
          : path.startsWith('live_group_prefs?')
          ? [
              {'category_id': 20},
            ]
          : path.startsWith('user_settings?select')
          ? <JsonObject>[]
          : http.Response('', 204);
      expect((await catalog.channels()).single.num, 11);
      expect(paths().last, 'channels?select=id,ext_id,name,num,logo_url,archive_days,is_radio,category_ids&available=is.true&order=num.nullslast,id&limit=1000');
      expect(await catalog.favoriteChannels(), {5});
      final filters = await catalog.liveFilters();
      expect([filters.hiddenChannels, filters.hiddenGroups, filters.showRadio], [
        {5},
        {20},
        true,
      ]);
      await catalog.setFavorite(5, true);
      expect((paths().last, calls.last.body), ('channel_prefs?on_conflict=user_id,channel_id', '{"channel_id":5,"favorite":true}'));
      await catalog.setChannelHidden(5, true);
      expect((paths().last, calls.last.body), ('channel_prefs?on_conflict=user_id,channel_id', '{"channel_id":5,"hidden":true}'));
      await catalog.setGroupHidden(20, false);
      expect((paths().last, calls.last.body), ('live_group_prefs?on_conflict=user_id,category_id', '{"category_id":20,"hidden":false}'));
      await catalog.setShowRadio(false);
      expect((paths().last, calls.last.body), ('user_settings?on_conflict=user_id', '{"show_radio":false}'));
    });

    test("the ranking and WTW's scores are asked of the server's functions", () async {
      server = (path) => path == 'rank' ? {'fresh': true} : {'scores': {'5': 87, '6': null}};
      expect(await catalog.refreshRanking('wtw-token'), isFalse);
      expect((calls.last.url.toString(), calls.last.body), ('https://db.test/functions/v1/rank', '{"wtw_token":"wtw-token"}'));
      expect(await catalog.wtwScores('wtw-token', [5, 6, 7]), {5: 87, 6: null});
      expect((paths().last, calls.last.body), ('wtw-scores', '{"wtw_token":"wtw-token","title_ids":[5,6,7]}'));
      server = (_) => <String, Object?>{};
      expect(await catalog.refreshRanking('wtw-token'), isTrue);
      expect(await catalog.wtwScores('wtw-token', [5]), isEmpty);
    });

    test("Home's rows, the watchlist and the counts ask the server as the TV app does", () async {
      server = (path) => path.startsWith('rpc/category_counts')
          ? [
              {'tag': 'genre', 'id': 18, 'n': 240},
            ]
          : path.startsWith('watchlist?')
          ? [
              {'added_at': 'x', 'titles': row()},
            ]
          : path.startsWith('title_cast?')
          ? [
              {'position': 0, 'character': '', 'people': {'tmdb_id': 287, 'name': 'Brad Pitt', 'profile': '/b.jpg'}},
            ]
          : path.startsWith('rpc/search_people?')
          ? [
              {'tmdb_id': 287, 'name': 'Brad Pitt', 'profile': null},
            ]
          : [row()];
      const kids = Category(7, Kind.movie, 'Kids', null, null);
      final t = title(row());
      await catalog.topPicks();
      await catalog.topPicksPage(Kind.series, offset: 20, limit: 20);
      await catalog.topPicksPage(null, offset: 0, limit: 20);
      await catalog.finishedTitles(kind: Kind.movie);
      await catalog.newForYou(limit: 5);
      await catalog.alsoLiked(t);
      await catalog.watchAgain();
      await catalog.recommendedPage(kids, offset: 0, limit: 60);
      await catalog.page(kids, Sort.name, hebrew: true, offset: 60, limit: 60);
      const select = 'select=id,ext_id,container_ext,kind,name,title_en,title_he,year,plot,overview_en,overview_he,tmdb_genre_ids,certification,'
          'tmdb_backdrop,tmdb_poster,backdrop_url,poster_url,runtime_min,tmdb_runtime_min,director,cast_names,tmdb_rating,original_language,group_id,wtw_match';
      expect(paths(), [
        'rpc/top_picks?$select&p_limit=20',
        'rpc/top_picks_page?$select&p_offset=20&p_limit=20&p_kind=series',
        'rpc/top_picks_page?$select&p_offset=0&p_limit=20',
        'rpc/finished_titles?$select&p_limit=20&p_kind=movie',
        'rpc/new_for_you?$select&p_limit=5',
        'rpc/also_liked?$select&p_title=10&p_limit=20',
        'rpc/watch_again?$select&p_limit=20',
        'rpc/recommended_page?$select&p_kind=movie&p_category=7&p_offset=0&p_limit=60',
        'titles?$select&kind=eq.movie&available=is.true&is_primary=is.true&group_category_ids=cs.%7B7%7D&order=sort_name_he.asc,id&offset=60&limit=60',
      ]);
      expect((await catalog.watchlist()).single.id, 10);
      expect(paths().last, 'watchlist?select=added_at,titles!inner(${select.substring(7)})&titles.available=is.true&order=added_at.desc');
      expect(await catalog.categoryCounts(Kind.movie), {('genre', 18): 240});
      expect(paths().last, 'rpc/category_counts?p_kind=movie');
      final cast = (await catalog.cast(10)).single;
      expect((cast.personId, cast.name, cast.character, cast.photo), (287, 'Brad Pitt', null, 'https://image.tmdb.org/t/p/w185/b.jpg'));
      expect(paths().last, 'title_cast?select=position,character,people(tmdb_id,name,profile)&title_id=eq.10&order=position');
      final found = (await catalog.searchPeople(' brad ', kind: Kind.movie)).single;
      expect((found.personId, found.name, found.photo), (287, 'Brad Pitt', null));
      expect(paths().last, 'rpc/search_people?p_query=brad&p_kind=movie');
    });

    test('the copies of a title: its group, 4K by the category name', () async {
      server = (path) => path.startsWith('categories?')
          ? [
              {'ext_id': 99, 'name': 'Movies 4k'},
              {'ext_id': 449, 'name': 'Movies'},
            ]
          : [
              {'id': 1, 'ext_id': 10, 'container_ext': 'mkv', 'category_ids': [449]},
              {'id': 2, 'ext_id': 20, 'container_ext': 'mkv', 'category_ids': [99]},
            ];
      expect(await catalog.copies(title(row())), [const Copy(2, 20, 'mkv', true), const Copy(1, 10, 'mkv', false)]);
      expect(paths().last, 'titles?select=id,ext_id,container_ext,category_ids&group_id=eq.10&available=is.true&order=id');
      expect((await catalog.liveCategories()).first.id, 99);
    });
  });
}
