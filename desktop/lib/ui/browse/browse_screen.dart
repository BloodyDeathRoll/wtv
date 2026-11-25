import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:material_ui/material_ui.dart' hide Title;

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../data/progress.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/buttons.dart';
import '../components/cards.dart';
import '../components/hero.dart';
import '../components/rows.dart';
import '../components/title_menu.dart';
import '../theme.dart';

/// A row on the page. Its "More" card opens `category`'s grid, or, with
/// `forYou`, the Recommended for You page of `forYouKind` (null: both kinds).
/// `progress` (Continue watching) gives a card its watched bar and label, by title id.
class BrowseRow {
  const BrowseRow(this.label, this.category, this.titles, {this.progress = const {}, this.forYou = false, this.forYouKind});

  final String label;
  final Category? category;
  final List<Title> titles;
  final Map<int, (double?, String?)> progress;
  final bool forYou;
  final Kind? forYouKind;
}

sealed class _Load {
  const _Load();
}

class _Loading extends _Load {
  const _Loading();
}

class _Ready extends _Load {
  const _Ready(this.rows, this.genres);

  final List<BrowseRow> rows;
  final Map<(Kind, int), Genre> genres;
}

class _Failed extends _Load {
  const _Failed(this.message);

  final String message;
}

const _continueWait = Duration(seconds: 5);

/// A first ranking takes about 10 s; after that the server answers at once.
const _rankingWait = Duration(seconds: 30);

/// Rows whose WTW match is asked for as soon as the page shows.
const _firstScoredRows = 3;

/// Titles in a section's "Recommended for You" row, before its More card.
const _sectionPicks = 10;

/// How long a page's rows are shown again as they are; older ones are shown, then read again.
const _rowsFresh = Duration(minutes: 10);

/// Whose rows these are: another language or account (WTW's too) never sees them.
typedef _Owner = (bool hebrew, String? email, String? wtwEmail);

/// A page's rows as last loaded, for `owner`, after `ratings` and `progress` changes.
class _Shown {
  const _Shown(this.owner, this.ratings, this.progress, this.load, this.at);

  final _Owner owner;
  final int ratings;
  final int progress;
  final _Ready load;
  final DateTime at;
}

/// Each page's last rows (by its kind; null is Home), kept while the app runs: switching tabs does not load them again.
final _shown = <Kind?, _Shown>{};

/// New rankings made while the app runs; a load that saw an older count does not keep its rows.
var _rankings = 0;

/// Continue watching as last loaded, and for whom.
(_Owner, List<ContinueItem>)? _lastWatching;

/// Forgets the rows kept from an earlier run of the app in the same process (tests).
@visibleForTesting
void forgetBrowseRows() {
  _shown.clear();
  _lastWatching = null;
}

String _reason(Object error) => error is ApiException ? error.message : error.toString();

/// Rows of titles under a header that follows the focus, as in the reference:
/// one section's category rows (`kind`), or Home's latest rows (null).
/// `firstFocus` is where Down from the tabs lands. Home starts with Continue
/// watching, reloaded when [progressVersion] changes (a player closed) without
/// reloading the rest. When `tabsFocused`, the page is back at its top.
///
/// With WTW connected: Top picks and New for you on Home, Recommended for You
/// first in a section, Watch it again from what was Loved or Liked in WTW, and
/// each card's "% match". Home then has the server rank the catalog, and
/// reloads when a new ranking was made.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.kind,
    required this.firstFocus,
    required this.tabsFocused,
    required this.onMore,
    required this.onOpen,
    required this.onForYou,
  });

  final Kind? kind;
  final FocusNode firstFocus;
  final ValueListenable<bool> tabsFocused;
  final ValueChanged<Category> onMore;
  final ValueChanged<Title> onOpen;

  /// Opens Recommended for You, for one kind or (null) both.
  final ValueChanged<Kind?> onForYou;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  _Load _load = const _Loading();
  // Null until loaded: Home shows its rows once this is in too, so the row does not
  // appear above the rows after the user has started moving. A nicety: when it
  // fails, Home just has no Continue watching row.
  List<ContinueItem>? _watching;
  bool? _hebrew;
  late int _ratingsSeen = _catalog.ratingsVersion.value;
  // Each load's number: the answer of one that a newer load has replaced is dropped.
  int _run = 0;
  int _watchingRun = 0;
  List<BrowseRow>? _rows;

  Catalog get _catalog => services.catalog;
  bool get _home => widget.kind == null;
  _Owner get _owner => (_hebrew!, services.session.email, services.wtw.email);

  @override
  void initState() {
    super.initState();
    _catalog.ratingsVersion.addListener(_reload);
    progressVersion.addListener(_loadWatching);
    if (_home) _rank();
  }

  /// With WTW connected, has the server rank the catalog (it keeps a ranking for an hour, so this
  /// is cheap). A new ranking reloads the rows, quietly. A nicety: on failure Home keeps what it shows.
  Future<void> _rank() async {
    final wtw = services.wtw;
    if (wtw.email == null) return;
    try {
      if (!await _catalog.refreshRanking(await wtw.token()).timeout(_rankingWait)) return;
    } on Exception {
      return;
    }
    // The other pages' recommendations come from the ranking too.
    _shown.clear();
    _rankings++;
    if (mounted) _reload(quiet: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hebrew = isHebrew(context);
    if (hebrew == _hebrew) return;
    _hebrew = hebrew;
    _reload();
    _loadWatching();
  }

  @override
  void dispose() {
    _catalog.ratingsVersion.removeListener(_reload);
    progressVersion.removeListener(_loadWatching);
    super.dispose();
  }

  void _show(_Load load) {
    _load = load;
    _rows = null;
  }

  /// `quiet`: the rows on screen stay until the new ones are in.
  Future<void> _reload({bool quiet = false}) async {
    final run = ++_run;
    final l = AppLocalizations.of(context)!;
    final (owner, hebrew) = (_owner, _hebrew!);
    final ratings = _catalog.ratingsVersion.value;
    final progress = progressVersion.value;
    final epoch = _rankings;
    // A page switched back to shows its last rows at once; they are read again,
    // quietly, only after a rating or a playback, or when old.
    final kept = _shown[widget.kind];
    final cached = kept != null && kept.owner == owner ? kept : null;
    if (cached != null && !quiet) {
      setState(() => _show(cached.load));
      if (cached.ratings == ratings && cached.progress == progress && DateTime.now().difference(cached.at) < _rowsFresh) {
        _ratingsSeen = ratings;
        return;
      }
    }
    // A reload after a rating keeps the rows on screen until the new ones are in.
    final keep = (quiet || ratings != _ratingsSeen || cached != null) && _load is _Ready;
    _ratingsSeen = ratings;
    if (!keep) setState(() => _show(const _Loading()));
    _Load next;
    try {
      final rows = await _loadRows(_catalog, widget.kind, hebrew, l, wtw: owner.$3 != null);
      // Genre names are a nicety: without them the meta line just has no genres.
      final genres = await _catalog.genres().catchError((Object _) => const <(Kind, int), Genre>{}, test: (e) => e is Exception);
      next = _Ready(rows, genres);
    } on Exception catch (e) {
      next = _Failed(_reason(e));
    }
    // Rows read before a new ranking arrived are not kept: they hold the old one's picks.
    if (next is _Ready && epoch == _rankings) _shown[widget.kind] = _Shown(owner, ratings, progress, next, DateTime.now());
    if (!mounted || run != _run) return;
    // A failed quiet reload leaves what is shown.
    if (!(keep && next is _Failed)) setState(() => _show(next));
  }

  Future<void> _loadWatching() async {
    if (!_home) return;
    final run = ++_watchingRun;
    final owner = _owner;
    // Starts from the last one loaded, so Home back from Live TV does not wait.
    final last = _lastWatching;
    if (_watching == null && last != null && last.$1 == owner) {
      setState(() {
        _watching = last.$2;
        _rows = null;
      });
    }
    List<ContinueItem>? got;
    try {
      // Bounded: Home waits for it, and it is not worth a long wait.
      got = await _catalog.continueWatching().timeout(_continueWait);
    } on Exception {
      got = null;
    }
    if (run != _watchingRun) return;
    // Only a real answer is kept: after a failure, Home waits for the row again next time.
    if (got != null) _lastWatching = (owner, got);
    if (!mounted) return;
    setState(() {
      _watching = got ?? _watching ?? const [];
      _rows = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (_load) {
      case _Loading():
        return _Message(l.loading);
      case _Failed(:final message):
        return _Message(l.loadFailed(message), focusNode: widget.firstFocus, onRetry: _reload);
      case _Ready(:final rows, :final genres):
        final watching = _watching;
        if (_home && watching == null) return _Message(l.loading);
        // Kept between builds: the same rows are the same list, so the header stays on the focused card.
        final all = _rows ??= [
          if (_home) ?continueRow(watching!, l.rowContinue, l.seasonEpisode),
          ...rows,
        ];
        if (all.isEmpty) return _Message(l.nothingHere);
        return _Rows(
          rows: all,
          genres: genres,
          firstFocus: widget.firstFocus,
          tabsFocused: widget.tabsFocused,
          onMore: widget.onMore,
          onOpen: widget.onOpen,
          onForYou: widget.onForYou,
          storage: widget.kind?.name ?? 'home',
        );
    }
  }
}

/// Continue watching as a row: a series' card names the episode to resume.
/// After a finished episode the card shows neither label nor bar: the next
/// episode is known only on the series page. Null when empty.
@visibleForTesting
BrowseRow? continueRow(List<ContinueItem> items, String label, String Function(int season, int episode) seasonEpisode) =>
    items.isEmpty
    ? null
    : BrowseRow(
        label,
        null,
        [for (final item in items) item.title],
        progress: {
          for (final ContinueItem(:title, progress: p) in items)
            title.id: (
              p.finished ? null : p.fraction,
              p.isEpisode && !p.finished ? seasonEpisode(p.season!, p.episode!) : null,
            ),
        },
      );

/// The page's rows. With WTW connected (`wtw`): Top picks and New for you on
/// Home, "Recommended for You" first on Movies and Series, and Watch it again
/// from the titles Loved or Liked in WTW. Without WTW, Watch it again holds
/// what the user finished. Empty rows are left out.
Future<List<BrowseRow>> _loadRows(Catalog catalog, Kind? kind, bool hebrew, AppLocalizations l, {required bool wtw}) async {
  Future<List<Title>> none() async => const [];
  Future<List<Title>> orNone(Future<List<Title>> titles) => titles.catchError((Object _) => const <Title>[], test: (e) => e is Exception);
  if (kind == null) {
    final [picks, fresh, movies, series, again] = await Future.wait([
      wtw ? catalog.topPicks() : none(),
      wtw ? catalog.newForYou() : none(),
      catalog.latest(Kind.movie),
      catalog.latest(Kind.series),
      wtw ? catalog.watchAgain() : catalog.finishedTitles(),
    ]);
    return [
      BrowseRow(l.rowTopPicks, null, picks, forYou: true),
      BrowseRow(l.rowNewForYou, null, fresh),
      BrowseRow(l.rowRecentMovies, null, movies),
      BrowseRow(l.rowRecentSeries, null, series),
      BrowseRow(l.rowWatchAgain, null, again),
    ].where((row) => row.titles.isNotEmpty).toList();
  }
  // A nicety: when it fails, the section just has no Recommended row.
  final recommended = wtw ? orNone(catalog.topPicksPage(kind, offset: 0, limit: _sectionPicks)) : none();
  // A nicety too: without it the section has no Watch it again row.
  final again = orNone(wtw ? catalog.watchAgain(kind: kind) : catalog.finishedTitles(kind: kind));
  // The provider files series by service only: their genre rows come from TMDB (movies have the provider's).
  final genres = kind == Kind.series
      ? await catalog.genreCategories(Kind.series, hebrew: hebrew).catchError((Object _) => const <Category>[], test: (e) => e is Exception)
      : const <Category>[];
  final rows = [for (final (category, titles) in await catalog.rows(kind, extra: genres)) BrowseRow(category.label(hebrew: hebrew), category, titles)];
  return [
    ...[
      BrowseRow(l.rowRecommended, null, await recommended, forYou: true, forYouKind: kind),
      BrowseRow(l.rowWatchAgain, null, await again),
    ].where((row) => row.titles.isNotEmpty),
    ...rows,
  ];
}

class _Rows extends StatefulWidget {
  const _Rows({
    required this.rows,
    required this.genres,
    required this.firstFocus,
    required this.tabsFocused,
    required this.onMore,
    required this.onOpen,
    required this.onForYou,
    required this.storage,
  });

  final List<BrowseRow> rows;
  final Map<(Kind, int), Genre> genres;
  final FocusNode firstFocus;
  final ValueListenable<bool> tabsFocused;
  final ValueChanged<Category> onMore;
  final ValueChanged<Title> onOpen;
  final ValueChanged<Kind?> onForYou;

  /// Tells this page's rows from another page's with the same category number, where each row's place is kept.
  final String storage;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  final _list = ScrollController();
  // Safe: empty rows are left out, and an empty page never gets here.
  // Kept when only Continue watching changes: the header stays on the focused card.
  late Title _focused = widget.rows.first.titles.first;

  // WTW's own match: listeners are told as the answers arrive.
  final _scores = services.wtwScores;

  @override
  void initState() {
    super.initState();
    widget.tabsFocused.addListener(_toTop);
    _scores.addListener(_onScores);
    _scores.requestFor(_titlesOf(widget.rows.take(_firstScoredRows)));
  }

  void _onScores() => setState(() {});

  Iterable<Title> _titlesOf(Iterable<BrowseRow> rows) => rows.expand((row) => row.titles);

  /// The cards not answered yet are asked for: the first rows at once, then the focused row and
  /// the one under it as the user moves down, not the whole page at once.
  void _focus(Title title, int row) {
    setState(() => _focused = title);
    _scores.requestFor(_titlesOf(widget.rows.skip(row).take(2)));
  }

  @override
  void didUpdateWidget(_Rows old) {
    super.didUpdateWidget(old);
    if (widget.tabsFocused != old.tabsFocused) {
      old.tabsFocused.removeListener(_toTop);
      widget.tabsFocused.addListener(_toTop);
    }
    if (identical(widget.rows, old.rows)) return;
    // A reload (retry, language) brings new title objects: the header moves to the first card.
    if (!widget.rows.any((row) => row.titles.any((t) => t.id == _focused.id))) _focused = widget.rows.first.titles.first;
    _scores.requestFor(_titlesOf(widget.rows.take(_firstScoredRows)));
  }

  @override
  void dispose() {
    widget.tabsFocused.removeListener(_toTop);
    _scores.removeListener(_onScores);
    _list.dispose();
    super.dispose();
  }

  /// With the focus on the tabs, the page is back at its top.
  void _toTop() {
    if (!widget.tabsFocused.value) return;
    if (_list.hasClients) _list.jumpTo(0);
    setState(() => _focused = widget.rows.first.titles.first);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final hebrew = isHebrew(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Backdrop(_focused.heroImage),
        if (_scores.matchOf(_focused) case final match?) HeaderMatch(match),
        Padding(
          // 8 less than the page's 88: the rows keep that room for the focused card's lift.
          padding: const EdgeInsetsDirectional.only(start: 80, top: headerTop),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: TitleHeader(_focused, widget.genres),
              ),
              Expanded(
                child: RowsAtTop(
                  child: ListView.builder(
                    controller: _list,
                    padding: const EdgeInsets.only(bottom: 400),
                    itemCount: widget.rows.length,
                    itemBuilder: (context, at) {
                      final row = widget.rows[at];
                      final category = row.category;
                      // Two categories can share a label; their ids differ.
                      // Provider category and TMDB genre ids can be equal: the kind of tag is part of the key.
                      final key = category == null ? row.label : '${category.genre ? 'g' : 'c'}${category.id}';
                      return Padding(
                        key: ValueKey(key),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: RowTitle(row.label)),
                            SizedBox(
                              // A 200 wide landscape card, and room for its lift.
                              height: 200 * 9 / 16 + 12,
                              child: SideArrows(
                                builder: (controller) => ListView.separated(
                                  controller: controller,
                                  // The row's place is kept while it is off the screen.
                                  key: PageStorageKey('${widget.storage}:$key'),
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsetsDirectional.only(start: 8, end: 48, top: 6, bottom: 6),
                                  itemCount: row.titles.length + (category == null && !row.forYou ? 0 : 1),
                                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                                  itemBuilder: (context, i) {
                                    if (i == row.titles.length) {
                                      return ImageCard.landscape(
                                        imageUrl: null,
                                        title: l.more,
                                        onPressed: () => category != null ? widget.onMore(category) : widget.onForYou(row.forYouKind),
                                      );
                                    }
                                    final t = row.titles[i];
                                    final (watched, episode) = row.progress[t.id] ?? (null, null);
                                    return ImageCard.landscape(
                                      key: ValueKey(t.id),
                                      imageUrl: t.cardImage,
                                      title: t.displayName(hebrew: hebrew),
                                      label: episode,
                                      progress: watched,
                                      match: _scores.matchOf(t),
                                      onPressed: () => widget.onOpen(t),
                                      // From Continue watching the menu can also take the title out of that row.
                                      onMenu: () => TitleMenuScope.open(context, t, continuing: row.progress.isNotEmpty),
                                      onFocused: () => _focus(t, at),
                                      focusNode: at == 0 && i == 0 ? widget.firstFocus : null,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The focused title's header: name, year and genres, synopsis.
class TitleHeader extends StatelessWidget {
  const TitleHeader(this.title, this.genres, {super.key});

  final Title title;
  final Map<(Kind, int), Genre> genres;

  @override
  Widget build(BuildContext context) {
    final hebrew = isHebrew(context);
    // Fixed height: rows do not jump when the synopsis length changes.
    return SizedBox(
      height: headerHeight,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: 560,
          child: HeroText(
            titleMaxLines: 1,
            title: title.displayName(hebrew: hebrew),
            meta: MetaRow(items: metaItems(title, genres, hebrew), badges: [?title.certification]),
            synopsis: title.synopsis(hebrew: hebrew),
          ),
        ),
      ),
    );
  }
}

/// "2026", "Crime • Drama": year and up to two genres.
@visibleForTesting
List<String> metaItems(Title t, Map<(Kind, int), Genre> genres, bool hebrew) {
  final names = [for (final id in t.genreIds) ?genres[(t.kind, id)]?.label(hebrew: hebrew)].take(2).join(' • ');
  return [?t.year?.toString(), if (names.isNotEmpty) names];
}

/// Loading, error or empty page; with `onRetry`, a Retry button that can take the focus.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.focusNode, this.onRetry});

  final String text;
  final FocusNode? focusNode;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium!.copyWith(color: WtvColors.textMuted)),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          ActionButton(label: AppLocalizations.of(context)!.retry, focusNode: focusNode, onPressed: onRetry!),
        ],
      ],
    ),
  );
}
