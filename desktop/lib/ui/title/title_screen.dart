import 'package:material_ui/material_ui.dart' hide Title;

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../data/marks.dart';
import '../../data/progress.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/actions.dart';
import '../components/badges.dart';
import '../components/buttons.dart';
import '../components/cards.dart';
import '../components/chips.dart';
import '../components/dialogs.dart';
import '../components/hero.dart';
import '../components/rows.dart';
import '../components/title_menu.dart';
import '../theme.dart';

/// A 200 wide landscape card's height, and a 96 wide cast card's.
const _landscape = 112.5;
const _portrait = 128.0;

/// The value of `future`, or `fallback` if it fails.
Future<T> _or<T>(Future<T> future, T fallback) async {
  try {
    return await future;
  } on Exception {
    return fallback;
  }
}

/// A title's page: the header with Play and the title's actions; for a series
/// its seasons and episodes, the header following the focused episode; then
/// Viewers also liked and the cast.
///
/// Play resumes: a movie where it stopped, a series at its next episode. The
/// saved positions are read again when [progressVersion] changes (a player
/// closed). `onPlay` and `onPlayEpisode` take the second to start at.
class TitleScreen extends StatefulWidget {
  const TitleScreen(
    this.title, {
    super.key,
    this.autoPlay = false,
    required this.play,
    required this.onPlay,
    required this.onPlayEpisode,
    required this.onPerson,
    required this.onOpen,
  });

  final Title title;

  /// Press Play as soon as the page opens (Play from a card's menu).
  final bool autoPlay;

  /// The Play button's focus: the page opens on it.
  final FocusNode play;
  final void Function(Copy copy, int startSecs) onPlay;

  /// The episode, the second to start at, and the series' episodes in order (for the next one).
  final void Function(Episode episode, int startSecs, List<Episode> episodes) onPlayEpisode;
  final ValueChanged<CastMember> onPerson;
  final ValueChanged<Title> onOpen;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  // Cast, copies, genres and Viewers also liked are extras: the page shows without them.
  var _cast = const <CastMember>[];
  var _copies = const <Copy>[];
  var _genres = const <(Kind, int), Genre>{};
  var _alsoLiked = const <Title>[];
  var _extrasLoaded = false;
  // Saved positions, newest first; null until first loaded. A failed load counts as none.
  List<Progress>? _progress;
  // Each read's number: the answer of one that a newer read has replaced is dropped.
  var _progressRun = 0;
  // A series' episodes; null until loaded.
  late List<Episode>? _episodes = _series ? null : const [];
  // Null: the first season.
  int? _season;
  // The focused episode, which the header then shows. Null: the header is the title's.
  Episode? _episode;
  var _marks = const Marks();
  // A press before the rating and watchlist came in wins over the loaded value.
  var _touched = false;
  // Rating and watchlist saves run one at a time, in the order pressed.
  Future<void> _saving = Future.value();
  // Play pressed before the copies (or positions) arrived: answered once they do, so a 4K copy
  // is not skipped. The second to start at; -1: where the movie stopped.
  int? _playPending;
  // Play on a series pressed before the episodes (or positions) arrived.
  var _episodePending = false;

  Catalog get _catalog => services.catalog;
  Title get _title => widget.title;
  bool get _series => _title.kind == Kind.series;
  int get _movieStart => (_progress ?? const <Progress>[]).where((p) => !p.isEpisode).firstOrNull?.resumeSecs ?? 0;
  EpisodePlay? get _next => nextEpisode(_episodes ?? const [], _progress ?? const []);

  // WTW's own match for the title: asked for when it came without one.
  final _scores = services.wtwScores;

  void _onScores() => setState(() {});

  @override
  void initState() {
    super.initState();
    progressVersion.addListener(_loadProgress);
    _scores.addListener(_onScores);
    _scores.requestFor([_title]);
    _loadExtras();
    _loadProgress();
    _loadMarks();
    if (_series) _loadEpisodes();
    if (widget.autoPlay) _pressPlay();
  }

  @override
  void dispose() {
    progressVersion.removeListener(_loadProgress);
    _scores.removeListener(_onScores);
    super.dispose();
  }

  Future<void> _loadExtras() async {
    final (cast, copies, genres, alsoLiked) = await (
      _or(_catalog.cast(_title.id), const <CastMember>[]),
      _or(_catalog.copies(_title), const <Copy>[]),
      _or(_catalog.genres(), const <(Kind, int), Genre>{}),
      _or(_catalog.alsoLiked(_title), const <Title>[]),
    ).wait;
    if (!mounted) return;
    // Viewers also liked comes in with the cast, so it never lands above a row already on screen.
    setState(() {
      _cast = cast;
      _copies = copies;
      _genres = genres;
      _alsoLiked = alsoLiked;
      _extrasLoaded = true;
    });
    _answerPending();
  }

  Future<void> _loadProgress() async {
    final run = ++_progressRun;
    final progress = await _or(_catalog.progress(_title), const <Progress>[]);
    if (!mounted || run != _progressRun) return;
    setState(() => _progress = progress);
    _answerPending();
  }

  Future<void> _loadEpisodes() async {
    final episodes = await _or(_catalog.episodes(_title), const <Episode>[]);
    if (!mounted) return;
    setState(() => _episodes = episodes);
    _answerPending();
  }

  Future<void> _loadMarks() async {
    final marks = await _or<Marks?>(_catalog.marks(_title), null);
    if (marks != null && mounted && !_touched) setState(() => _marks = marks);
  }

  /// Plays the movie from `from`: with more than one copy, after asking which.
  Future<void> _play(int from) async {
    if (_copies.length < 2) {
      // Copies failed to load: play this copy.
      widget.onPlay(_copies.firstOrNull ?? _title.asCopy(), from);
      return;
    }
    final copy = await showDialog<Copy>(context: context, builder: (_) => _CopyChooser(_copies));
    if (copy != null && mounted) widget.onPlay(copy, from);
  }

  void _playNext({bool startOver = false}) {
    final next = _next;
    if (next != null) widget.onPlayEpisode(next.episode, startOver ? 0 : next.startSecs, _episodes!);
  }

  /// Play: what is not loaded yet is waited for, then played.
  void _pressPlay() {
    if (!_series) {
      _extrasLoaded && _progress != null ? _play(_movieStart) : _playPending = -1;
    } else if (_episodes == null || _progress == null) {
      _episodePending = true;
    } else {
      _playNext();
    }
  }

  void _startOver() {
    if (_series) {
      _playNext(startOver: true);
    } else {
      _extrasLoaded ? _play(0) : _playPending = 0;
    }
  }

  /// Something arrived: a Play pressed while it was awaited is answered.
  void _answerPending() {
    final pending = _playPending;
    if (pending != null && _extrasLoaded && _progress != null) {
      _playPending = null;
      _play(pending < 0 ? _movieStart : pending);
    }
    if (_episodePending && _episodes != null && _progress != null) {
      _episodePending = false;
      _playNext();
    }
  }

  /// A rating or watchlist change is shown at once and saved in the order
  /// pressed; `undo` puts it back if the save fails.
  void _save(Future<void> Function() save, VoidCallback undo) {
    _touched = true;
    _saving = _saving.then((_) async {
      try {
        await save();
      } on Exception {
        if (mounted) setState(undo);
      }
    });
  }

  /// A rating pressed again is cleared.
  void _rate(Rating rating) {
    final before = _marks.rating;
    final to = before == rating ? null : rating;
    setState(() => _marks = _marks.copyWith(rating: () => to));
    _save(() => _catalog.setRating(_title, to), () {
      // Unless a later press changed it.
      if (_marks.rating == to) _marks = _marks.copyWith(rating: () => before);
    });
  }

  void _toggleWatchlist() {
    final to = !_marks.onWatchlist;
    setState(() => _marks = _marks.copyWith(onWatchlist: to));
    _save(() => _catalog.setWatchlist(_title, to), () {
      if (_marks.onWatchlist == to) _marks = _marks.copyWith(onWatchlist: !to);
    });
  }

  Future<void> _removeFromContinue() async {
    // The button goes away: the focus moves to Play first, not off the page.
    widget.play.requestFocus();
    try {
      await _catalog.clearProgress({for (final p in _progress ?? const <Progress>[]) p.titleId});
      progressVersion.value++;
    } on Exception catch (e) {
      debugPrint('Removing the positions failed: $e');
    }
  }

  /// With the focus in `child`, outside the episodes, the header is the title's again.
  Widget _titleAgain(Widget child, {Key? key}) => Focus(
    key: key,
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (focused && _episode != null) setState(() => _episode = null);
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final hebrew = isHebrew(context);
    final title = _title;
    final progress = _progress ?? const <Progress>[];
    final all = _episodes ?? const <Episode>[];
    final seasons = {for (final e in all) e.season}.toList();
    final shownSeason = _season ?? seasons.firstOrNull;
    final seasonEpisodes = [
      for (final e in all)
        if (e.season == shownSeason) e,
    ];
    final next = _next;
    // Episode positions by season and number, the newest of each: the bar on each card, and where it starts.
    final watched = <(int, int), Progress>{};
    for (final p in progress) {
      if (p.isEpisode) watched.putIfAbsent((p.season!, p.episode!), () => p);
    }
    // What the Play button says: Resume, "Play S1 E4" for the next episode, or Play.
    final resuming = _series ? (next?.startSecs ?? 0) > 0 : _movieStart > 0;
    final playLabel = resuming
        ? l.resume
        : next != null && next.episode != all.firstOrNull
        ? l.playEpisode(l.seasonEpisode(next.episode.season, next.episode.number))
        : l.play;
    String runtime(int minutes) => minutes >= 60 ? l.runtimeHours(minutes ~/ 60, minutes % 60) : l.runtimeMinutes(minutes);
    final genres = [for (final id in title.genreIds) ?_genres[(title.kind, id)]?.label(hebrew: hebrew)].take(2).join(' • ');
    final e = _episode;
    final rating = _marks.rating;
    return Stack(
      fit: StackFit.expand,
      children: [
        Backdrop(title.heroImage),
        if (_scores.matchOf(title) case final match?) HeaderMatch(match),
        Padding(
          // 8 less than the page's 88: the rows keep that room for the focused card's lift.
          padding: const EdgeInsetsDirectional.only(start: 80, top: headerTop),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed height: the rows do not jump when the header text changes. Below the
              // browse header's text: the actions, and the focused action's name under them.
              Container(
                height: headerHeight + 92,
                padding: const EdgeInsetsDirectional.only(start: 8),
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(
                  width: 560,
                  child: HeroText(
                    titleMaxLines: 1,
                    title: e == null ? title.displayName(hebrew: hebrew) : e.displayName(hebrew: hebrew) ?? l.episodeNumber(e.number),
                    meta: MetaRow(
                      items: e != null
                          ? [
                              l.seasonEpisode(e.season, e.number),
                              if (e.durationSecs case final secs?) runtime(secs ~/ 60),
                              ?title.year?.toString(),
                            ]
                          : [
                              if (seasons.length > 1) l.seasons(seasons.length),
                              ?title.year?.toString(),
                              if (title.runtimeMin case final minutes? when !_series) runtime(minutes),
                              if (genres.isNotEmpty) genres,
                            ],
                      badges: [?title.certification, if (_copies.any((c) => c.is4k)) '4K'],
                    ),
                    synopsis: e?.synopsis(hebrew: hebrew) ?? title.synopsis(hebrew: hebrew),
                    actions: _titleAgain(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlayButton(label: playLabel, onPressed: _pressPlay, focusNode: widget.play),
                          const SizedBox(width: 12),
                          if (resuming) ActionIcon(icon: Icons.replay, description: l.startOver, onPressed: _startOver),
                          ActionIcon(
                            icon: _marks.onWatchlist ? Icons.check : Icons.add,
                            description: _marks.onWatchlist ? l.removeFromWatchlist : l.addToWatchlist,
                            onPressed: _toggleWatchlist,
                            selected: _marks.onWatchlist,
                          ),
                          if (progress.isNotEmpty)
                            ActionIcon(
                              icon: Icons.remove_circle_outline,
                              description: l.removeFromContinue,
                              onPressed: _removeFromContinue,
                            ),
                          ActionIcon(
                            icon: Icons.info_outline,
                            description: l.moreInfo,
                            onPressed: () => showDialog<void>(context: context, builder: (_) => _MoreInfo(title, _cast)),
                          ),
                          // The ratings stand apart from the title's actions.
                          const ActionDivider(),
                          for (final (to, on, off, name) in [
                            (Rating.love, Icons.favorite, Icons.favorite_border, l.rateLove),
                            (Rating.like, Icons.thumb_up, Icons.thumb_up_outlined, l.rateLike),
                            (Rating.dislike, Icons.thumb_down, Icons.thumb_down_outlined, l.rateDislike),
                          ])
                            ActionIcon(
                              icon: rating == to ? on : off,
                              description: name,
                              onPressed: () => _rate(to),
                              selected: rating == to,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                // The episodes row's title line holds the season chips: more room above its cards.
                child: RowsAtTop(
                  titleSpace: 58,
                  child: ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 400),
                    children: [
                      // A series' row is there from the start, empty while loading, so it never
                      // lands above a row the focus is already in.
                      if (seasonEpisodes.isNotEmpty || (_series && _episodes == null))
                        _CardRow(
                          key: const ValueKey('episodes'),
                          // A new row per season: it starts at episode 1, not at the old scroll position.
                          listKey: ValueKey(shownSeason),
                          height: _landscape,
                          heading: seasons.length < 2
                              ? RowTitle(l.rowEpisodes)
                              : SizedBox(
                                  height: 46,
                                  child: Row(
                                    children: [
                                      RowTitle(l.rowEpisodes),
                                      const SizedBox(width: 20),
                                      // On the chips the header is the series' again.
                                      Expanded(child: _titleAgain(_seasonChips(seasons, shownSeason, l))),
                                    ],
                                  ),
                                ),
                          count: seasonEpisodes.length,
                          card: (context, i) {
                            final episode = seasonEpisodes[i];
                            final saved = watched[(episode.season, episode.number)];
                            return ImageCard.landscape(
                              key: ValueKey(episode.id),
                              imageUrl: episode.image ?? title.cardImage,
                              title: episode.displayName(hebrew: hebrew) ?? l.episodeNumber(episode.number),
                              label: l.episodeNumber(episode.number),
                              progress: saved?.fraction,
                              onPressed: () => widget.onPlayEpisode(episode, saved?.resumeSecs ?? 0, all),
                              onFocused: () => setState(() => _episode = episode),
                            );
                          },
                        ),
                      if (_alsoLiked.isNotEmpty)
                        _titleAgain(
                          key: const ValueKey('alsoLiked'),
                          _CardRow(
                            height: _landscape,
                            heading: RowTitle(l.rowAlsoLiked),
                            count: _alsoLiked.length,
                            card: (context, i) {
                              final t = _alsoLiked[i];
                              final name = t.displayName(hebrew: hebrew);
                              return ImageCard.landscape(
                                key: ValueKey(t.id),
                                imageUrl: t.cardImage,
                                title: name,
                                // The name on the image: the picture alone does not tell titles apart.
                                label: name,
                                onPressed: () => widget.onOpen(t),
                                onMenu: () => TitleMenuScope.open(context, t),
                              );
                            },
                          ),
                        ),
                      if (_cast.isNotEmpty)
                        _titleAgain(
                          key: const ValueKey('cast'),
                          _CardRow(
                            height: _portrait,
                            heading: RowTitle(l.rowCast),
                            count: _cast.length,
                            card: (context, i) {
                              final member = _cast[i];
                              return ImageCard.person(
                                key: ValueKey(member.personId),
                                imageUrl: member.photo,
                                title: member.name,
                                label: member.name,
                                onPressed: () => widget.onPerson(member),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Season choices next to the episodes row title. Moving onto one shows that season.
  Widget _seasonChips(List<int> seasons, int? shown, AppLocalizations l) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.only(bottom: 10),
    itemCount: seasons.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (context, i) {
      final season = seasons[i];
      void show() {
        if (season != shown) setState(() => _season = season);
      }

      return Focus(
        key: ValueKey(season),
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) show();
        },
        child: Center(
          child: OptionChip(selected: season == shown, label: l.seasonNumber(season), onPressed: show),
        ),
      );
    },
  );
}

/// A row of cards under its heading.
class _CardRow extends StatelessWidget {
  const _CardRow({super.key, required this.heading, required this.height, required this.count, required this.card, this.listKey});

  final Widget heading;

  /// A card's height.
  final double height;
  final int count;
  final NullableIndexedWidgetBuilder card;
  final Key? listKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: heading),
        SizedBox(
          // And room for the focused card's lift.
          height: height + 12,
          child: ListView.separated(
            key: listKey,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(start: 8, end: 48, top: 6, bottom: 6),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: card,
          ),
        ),
      ],
    ),
  );
}

/// "Play in 4K / HD": one button per copy, the first (4K if any) focused. Pops with the copy.
class _CopyChooser extends StatelessWidget {
  const _CopyChooser(this.copies);

  final List<Copy> copies;

  @override
  Widget build(BuildContext context) {
    final labels = copyLabels(copies);
    return Panel(
      spacing: 10,
      children: [
        Text(AppLocalizations.of(context)!.chooseCopy, style: Theme.of(context).textTheme.titleMedium),
        for (final (i, copy) in copies.indexed)
          ActionButton(label: labels[i], autofocus: i == 0, onPressed: () => Navigator.pop(context, copy)),
      ],
    );
  }
}

/// Full synopsis and credits.
class _MoreInfo extends StatelessWidget {
  const _MoreInfo(this.title, this.cast);

  final Title title;
  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = isHebrew(context);
    final quiet = text.bodyMedium!.copyWith(color: WtvColors.textSecondary);
    final castLine = cast.isEmpty ? title.castNames ?? '' : cast.take(8).map((member) => member.name).join(', ');
    return Panel(
      width: 620,
      padding: 28,
      spacing: 12,
      children: [
        // Full texts, as on the TV.
        ContentText(title.displayName(hebrew: hebrew), style: text.headlineMedium),
        if (title.synopsis(hebrew: hebrew) case final synopsis?) ContentText(synopsis, style: quiet),
        for (final (label, value) in [
          if (title.director case final director?) (l.infoDirector, director),
          if (castLine.isNotEmpty) (l.infoCast, castLine),
          if (title.originalLanguage case final language?) (l.infoLanguage, language.toUpperCase()),
          if (title.tmdbRating case final rating?) (l.infoRating, l.infoRatingValue(rating.toStringAsFixed(1))),
        ])
          Text('$label: $value', style: quiet),
        ActionButton(label: l.close, autofocus: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
