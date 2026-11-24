import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../app_language.dart';
import '../data/catalog.dart';
import '../data/progress.dart';
import '../data/provider_login.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import 'browse/browse_screen.dart';
import 'categories/categories_screen.dart';
import 'components/buttons.dart';
import 'components/chips.dart';
import 'components/pressable.dart';
import 'components/side_rail.dart';
import 'components/title_menu.dart';
import 'grid/grid_screen.dart';
import 'person/person_screen.dart';
import 'player/player_screen.dart';
import 'search/search_screen.dart';
import 'settings/settings_screen.dart';
import 'theme.dart';
import 'title/title_screen.dart';

/// The four sections in the top tabs.
enum Section { home, movies, series, liveTv }

/// A page opened over the section. Live TV's player comes with its work package.
sealed class AppPage {
  const AppPage();

  /// Which page this is: opening one already on the stack goes back to it.
  String get id;
}

/// Side rail → Search: it looks in the section on screen.
class SearchPage extends AppPage {
  const SearchPage(this.scope);

  final SearchScope scope;

  @override
  String get id => 'search:${scope.name}';
}

/// Side rail → Categories: the provider's categories and the genres of a kind.
class CategoriesPage extends AppPage {
  const CategoriesPage(this.kind);

  final Kind kind;

  @override
  String get id => 'categories';
}

/// A whole category, in rows of four.
class GridPage extends AppPage {
  const GridPage(this.category);

  final Category category;

  @override
  String get id => 'grid:${category.kind.name}:${category.genre ? 'genre:' : ''}${category.id}';
}

class TitlePage extends AppPage {
  const TitlePage(this.title, {this.autoPlay = false});

  final Title title;

  /// Opened from a card's menu with Play: Play is pressed once the page is in.
  final bool autoPlay;

  @override
  String get id => 'title:${title.id}';
}

class PersonPage extends AppPage {
  const PersonPage(this.person);

  final CastMember person;

  /// The same person from two casts (different characters) is one page.
  @override
  String get id => 'person:${person.personId}';
}

class WatchlistPage extends AppPage {
  const WatchlistPage();

  @override
  String get id => 'watchlist';
}

class SettingsPage extends AppPage {
  const SettingsPage({this.providerFirst = false});

  /// Opened by Play when there is no provider login: the page opens on it.
  final bool providerFirst;

  @override
  String get id => 'settings';
}

/// A film or an episode, full screen. `titleId` is the copy played; `episodeId` is set for an episode.
/// For an episode, `series` is the series' name and `episodes` its episodes in order, so the next one can follow.
class PlayerPage extends AppPage {
  const PlayerPage({
    required this.url,
    required this.title,
    required this.titleId,
    required this.episodeId,
    required this.startSecs,
    this.series,
    this.episodes = const [],
  });

  final String url;
  final String title;
  final int titleId;
  final int? episodeId;
  final int startSecs;
  final String? series;
  final List<Episode> episodes;

  @override
  String get id => 'player';

  Episode? get next => episodeAfter(episodes, episodeId);
  Episode? get previous => episodeBefore(episodes, episodeId);
}

/// One screen of the stack: the section under the tabs (`page` null), or a page over it.
class _Entry {
  _Entry(this.page);

  final AppPage? page;

  /// Holds the screen's items. It remembers the one that last had the focus,
  /// so Back from a title page lands on the card it was opened from.
  final scope = FocusScopeNode();

  /// The screen's first item: where the focus goes when it opens.
  final first = FocusNode();

  bool get hasItems => scope.traversalDescendants.isNotEmpty;

  /// Focuses the item that last had the focus, or else the first one. A screen with no items holds the focus itself.
  void enter() => (scope.focusedChild == null && first.context != null ? first : scope).requestFocus();

  void dispose() {
    scope.dispose();
    first.dispose();
  }
}

/// The app frame: top tabs, the side rail, and the page in between.
///
/// Keys and mouse, as on the TV's remote:
/// - Moving the focus onto a tab switches the section; so does a click on it.
/// - Back (Esc, or the mouse's back button) from inside a page goes to the tabs; Back on the tabs asks before leaving.
/// - A rail item opens its page over the section; Back closes it. Main menu closes every page and returns to the tabs.
class WtvShell extends StatefulWidget {
  const WtvShell({super.key});

  @override
  State<WtvShell> createState() => _WtvShellState();
}

class _WtvShellState extends State<WtvShell> {
  var _section = Section.home;
  final _base = _Entry(null);
  // Pages opened over the section, in order; Back pops one.
  final _stack = <_Entry>[];
  // One per tab: Back focuses the selected tab, not the first one (which would switch section).
  final _tabs = {for (final s in Section.values) s: FocusNode()};
  final _rail = {for (final item in RailItem.values) item: FocusNode()};
  // Whether the focus was on the tabs (rather than the page) before it went to the rail: the arrow back returns there.
  var _lastOnTabs = true;
  // True while a tab has the focus: the section's page is then back at its top.
  final _tabsFocused = ValueNotifier(false);

  FocusNode get _selectedTab => _tabs[_section]!;

  @override
  void initState() {
    super.initState();
    _focusTop(toTabs: true);
  }

  @override
  void dispose() {
    for (final entry in [_base, ..._stack]) {
      entry.dispose();
    }
    for (final node in [..._tabs.values, ..._rail.values]) {
      node.dispose();
    }
    _tabsFocused.dispose();
    super.dispose();
  }

  /// After the stack changed and the screens are rebuilt, the one on top takes the focus.
  void _focusTop({bool toTabs = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (_stack.isNotEmpty) {
      _stack.last.enter();
    } else if (toTabs || !_base.hasItems) {
      _selectedTab.requestFocus();
    } else {
      _base.enter();
    }
  });

  void _setStack(void Function() change, {bool toTabs = false}) {
    final before = [..._stack];
    setState(change);
    // Once their widgets are gone. The shell's own dispose covers the entries still on the stack, so none is disposed twice.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in before.where((e) => !_stack.contains(e))) {
        entry.dispose();
      }
    });
    _focusTop(toTabs: toTabs);
  }

  /// Opening a page already on the stack goes back to it, rather than stacking a second copy.
  void _open(AppPage page) {
    final existing = _stack.indexWhere((e) => e.page!.id == page.id);
    _setStack(() => existing < 0 ? _stack.add(_Entry(page)) : _stack.removeRange(existing + 1, _stack.length));
  }

  void _back() {
    if (_stack.isNotEmpty) {
      _setStack(_stack.removeLast);
    } else if (!_selectedTab.hasFocus) {
      _selectedTab.requestFocus();
    } else {
      _askExit();
    }
  }

  Future<void> _askExit() async {
    final leave = await showDialog<bool>(context: context, builder: (_) => const _ExitDialog());
    if (leave ?? false) await SystemNavigator.pop();
  }

  void _select(RailItem item) => switch (item) {
    RailItem.search => _open(
      SearchPage(switch (_section) {
        Section.movies => SearchScope.movies,
        Section.series => SearchScope.series,
        // The channel search comes with Live TV's work package.
        Section.home || Section.liveTv => SearchScope.all,
      }),
    ),
    RailItem.categories => _open(CategoriesPage(_section == Section.series ? Kind.series : Kind.movie)),
    RailItem.mainMenu => _stack.isEmpty ? _selectedTab.requestFocus() : _setStack(_stack.clear, toTabs: true),
    RailItem.watchlist => _open(const WatchlistPage()),
    RailItem.settings => _open(const SettingsPage()),
  };

  void _openTitle(Title title) => _open(TitlePage(title));

  /// The saved provider login: a stream needs it. With none, Settings opens on it
  /// (`replace`: in the player's place) and this is null.
  ProviderLogin? _login({required bool replace}) {
    final login = services.provider.login;
    if (login != null && login.isComplete) return login;
    const settings = SettingsPage(providerFirst: true);
    replace ? _setStack(() => _stack[_stack.length - 1] = _Entry(settings)) : _open(settings);
    return null;
  }

  void _play(PlayerPage Function(ProviderLogin login) page) {
    final login = _login(replace: false);
    if (login != null) _open(page(login));
  }

  String _episodeTitle(String series, Episode e) => '$series · ${AppLocalizations.of(context)!.seasonEpisode(e.season, e.number)}';

  /// Another episode (the next, the previous) replaces the player on top: Back still returns to the series page.
  void _playEpisode(PlayerPage p, Episode e) {
    final login = _login(replace: true);
    if (login == null) return;
    final page = PlayerPage(
      url: streamUrl(login, StreamKind.episode, e.extId, e.containerExt),
      title: _episodeTitle(p.series ?? '', e),
      titleId: p.titleId,
      episodeId: e.id,
      startSecs: 0,
      series: p.series,
      episodes: p.episodes,
    );
    _setStack(() => _stack[_stack.length - 1] = _Entry(page));
  }

  // Saved positions: one save at a time. Reports that arrive meanwhile collapse into the latest
  // for that film or episode, which carries the whole position (a held seek key sends many).
  final _saves = <(int, int?), Future<void> Function()>{};
  // Those with a final report waiting: the pages showing positions reload once it is in.
  final _finals = <(int, int?)>{};
  var _saving = false;

  Future<void> _saveProgress(PlayerPage p, int positionSecs, int? durationSecs, bool isFinal) async {
    final key = (p.titleId, p.episodeId);
    if (isFinal) _finals.add(key);
    _saves[key] = () async {
      try {
        await services.catalog.saveProgress(p.titleId, p.episodeId, positionSecs, durationSecs);
      } on Exception catch (e) {
        // shortcut: a failed save is dropped; the next one (every 15 s) carries the position.
        debugPrint('Saving the position failed: $e');
      }
      if (_finals.remove(key)) progressVersion.value++;
    };
    if (_saving) return;
    _saving = true;
    while (_saves.isNotEmpty) {
      await _saves.remove(_saves.keys.first)!();
    }
    _saving = false;
  }

  /// A card's menu, over whatever page the card is on.
  Future<void> _menu(Title title, {required bool continuing}) async {
    final choice = await showDialog<TitleMenuChoice>(context: context, builder: (_) => TitleMenu(title, continuing: continuing));
    if (!mounted) return;
    switch (choice) {
      case TitleMenuChoice.info:
        _open(TitlePage(title));
      case TitleMenuChoice.play:
        _open(TitlePage(title, autoPlay: true));
      case TitleMenuChoice.remove:
        final catalog = services.catalog;
        try {
          await catalog.clearProgress({for (final p in await catalog.progress(title)) p.titleId});
          progressVersion.value++;
        } on Exception catch (e) {
          debugPrint('Removing the positions failed: $e');
        }
      case null:
    }
  }

  /// From the rail back to where the focus was.
  void _leaveRail() {
    if (_stack.isNotEmpty) {
      _stack.last.enter();
    } else if (_lastOnTabs || !_base.hasItems) {
      _selectedTab.requestFocus();
    } else {
      _base.enter();
    }
  }

  /// An arrow key at the edge of a screen: up to the tabs (from the section), sideways to the nearest rail item.
  void _onEdge(_Entry entry, TraversalDirection direction) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (direction == TraversalDirection.up && entry == _base) {
      _selectedTab.requestFocus();
    } else if (direction == (rtl ? TraversalDirection.right : TraversalDirection.left)) {
      final items = _rail.values.where((n) => n.context != null);
      // No rail on screen: the focus stays.
      if (items.isEmpty) return;
      final y = FocusManager.instance.primaryFocus!.rect.center.dy;
      double distance(FocusNode node) => (node.rect.center.dy - y).abs();
      items.reduce((a, b) => distance(a) <= distance(b) ? a : b).requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = isHebrew(context);
    final tabLabels = {
      Section.home: l.tabHome,
      Section.movies: l.tabMovies,
      Section.series: l.tabSeries,
      Section.liveTv: l.tabLive,
    };
    return Actions(
      actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _back())},
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kBackMouseButton != 0) _back();
        },
        child: Material(
          color: WtvColors.background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _layer(
                _base,
                covered: _stack.isNotEmpty,
                onFocus: () => _lastOnTabs = false,
                child: switch (_section) {
                  // Live TV comes with its work package.
                  Section.liveTv => const SizedBox.expand(),
                  _ => BrowseScreen(
                    // A section's page is its own: its rows, its place and its header.
                    key: ValueKey(_section),
                    kind: switch (_section) {
                      Section.movies => Kind.movie,
                      Section.series => Kind.series,
                      _ => null,
                    },
                    firstFocus: _base.first,
                    tabsFocused: _tabsFocused,
                    onMore: (category) => _open(GridPage(category)),
                    onOpen: _openTitle,
                  ),
                },
                over: PositionedDirectional(
                  start: 88,
                  top: 18,
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    // Down from the tabs enters the page, never the rail.
                    onKeyEvent: (_, event) {
                      if (event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
                      if (event is KeyDownEvent && _base.hasItems) _base.enter();
                      return KeyEventResult.handled;
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 20,
                      children: [
                        for (final section in Section.values)
                          Pressable(
                            focusNode: _tabs[section],
                            hoverFocuses: false,
                            selected: section == _section,
                            // Nothing more on a press: the click gives the tab the focus, and the focus switches the section.
                            onPressed: () {},
                            onFocusChange: (focused) {
                              _tabsFocused.value = _tabs.values.any((tab) => tab.hasFocus);
                              if (!focused) return;
                              _lastOnTabs = true;
                              if (section != _section) setState(() => _section = section);
                            },
                            builder: (context, focused) => Pill(
                              focused: focused,
                              color: section == _section ? WtvColors.surface : null,
                              textColor: section == _section ? WtvColors.textPrimary : WtvColors.textSecondary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              style: text.titleSmall,
                              label: tabLabels[section]!,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final entry in _stack)
                _layer(
                  entry,
                  covered: entry != _stack.last,
                  child: switch (entry.page!) {
                    SettingsPage(:final providerFirst) => SettingsScreen(firstFocus: entry.first, providerFirst: providerFirst),
                    CategoriesPage(:final kind) => CategoriesScreen(
                      kind,
                      firstFocus: entry.first,
                      onOpen: (category) => _open(GridPage(category)),
                    ),
                    GridPage(:final category) => GridScreen(category, firstFocus: entry.first, onOpen: _openTitle),
                    TitlePage(:final title, :final autoPlay) => TitleScreen(
                      title,
                      autoPlay: autoPlay,
                      play: entry.first,
                      onPlay: (copy, start) => _play(
                        (login) => PlayerPage(
                          url: streamUrl(login, StreamKind.movie, copy.extId, copy.containerExt),
                          title: title.displayName(hebrew: hebrew),
                          titleId: copy.id,
                          episodeId: null,
                          startSecs: start,
                        ),
                      ),
                      onPlayEpisode: (e, start, episodes) {
                        final series = title.displayName(hebrew: hebrew);
                        _play(
                          (login) => PlayerPage(
                            url: streamUrl(login, StreamKind.episode, e.extId, e.containerExt),
                            title: _episodeTitle(series, e),
                            titleId: title.id,
                            episodeId: e.id,
                            startSecs: start,
                            series: series,
                            episodes: episodes,
                          ),
                        );
                      },
                      onPerson: (person) => _open(PersonPage(person)),
                      onOpen: _openTitle,
                    ),
                    PersonPage(:final person) => PersonScreen(person, firstFocus: entry.first, onOpen: _openTitle),
                    WatchlistPage() => TitlesPage(
                      load: services.catalog.watchlist,
                      // Read again after a watchlist change (a title removed on its page, say).
                      reload: services.catalog.watchlistVersion,
                      firstFocus: entry.first,
                      onOpen: _openTitle,
                      kinds: true,
                      header: (context, _) => Text(l.railWatchlist, style: text.displayMedium),
                    ),
                    final PlayerPage p => PlayerScreen(
                      url: p.url,
                      title: p.title,
                      startSecs: p.startSecs,
                      firstFocus: entry.first,
                      episode: p.episodeId != null,
                      next: switch (p.next) {
                        null => null,
                        final e => [l.seasonEpisode(e.season, e.number), ?e.displayName(hebrew: hebrew)].join(' · '),
                      },
                      onNext: () {
                        if (p.next case final e?) _playEpisode(p, e);
                      },
                      onPrevious: switch (p.previous) {
                        null => null,
                        final e => () => _playEpisode(p, e),
                      },
                      onProgress: (position, duration, isFinal) => _saveProgress(p, position, duration, isFinal),
                      onClose: _back,
                    ),
                    SearchPage(:final scope) => SearchScreen(
                      scope: scope,
                      field: entry.first,
                      onOpen: _openTitle,
                      onPerson: (person) => _open(PersonPage(person)),
                    ),
                  },
                ),
              // Not over the video: the player is the whole screen.
              if (_stack.lastOrNull?.page is! PlayerPage)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: SideRail(
                    nodes: _rail,
                    onSelect: _select,
                    onLeave: _leaveRail,
                    // Categories lists movie or series tags: not on Home or Live TV.
                    showCategories: _section == Section.movies || _section == Section.series,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One screen of the stack. Screens under the top one stay built (no reload,
  /// same scroll) but cannot take the focus and are not drawn. `over` lies on
  /// the screen, outside its focus scope.
  Widget _layer(_Entry entry, {required bool covered, required Widget child, VoidCallback? onFocus, Widget? over}) {
    return ExcludeFocus(
      // Keyed by the entry, so a page keeps its state while pages open over it.
      key: ObjectKey(entry),
      excluding: covered,
      child: Offstage(
        offstage: covered,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Actions(
              actions: {DirectionalFocusIntent: _ArrowAction((direction) => _onEdge(entry, direction))},
              child: FocusScope(
                node: entry.scope,
                onFocusChange: (hasFocus) {
                  if (hasFocus) onFocus?.call();
                },
                // A card's menu opens from any screen.
                child: TitleMenuScope(onOpen: _menu, child: child),
              ),
            ),
            ?over,
          ],
        ),
      ),
    );
  }
}

/// Arrow keys move the focus inside the screen's focus scope, which they cannot leave; at its edge, `onEdge` decides.
class _ArrowAction extends Action<DirectionalFocusIntent> {
  _ArrowAction(this.onEdge);

  final ValueChanged<TraversalDirection> onEdge;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    if (_atEdge(focus, intent.direction) || !focus.focusInDirection(intent.direction)) onEdge(intent.direction);
  }

  bool _atEdge(FocusNode focus, TraversalDirection direction) {
    final items = focus.nearestScope!.traversalDescendants;
    // A screen with nothing focused holds the focus itself (its items are still loading, or it
    // has none). The arrow towards the rail is then at its edge; with no items, every arrow is.
    if (focus is FocusScopeNode) {
      final rtl = Directionality.of(focus.context!) == TextDirection.rtl;
      return items.isEmpty || direction == (rtl ? TraversalDirection.right : TraversalDirection.left);
    }
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) return false;
    // Left and right stay in the row. With no item level with this one on that side the row has ended,
    // where the framework would jump to the nearest item of another row.
    final from = focus.rect;
    return !items.any(
      (item) =>
          item != focus &&
          item.rect.top < from.bottom &&
          item.rect.bottom > from.top &&
          (direction == TraversalDirection.left ? item.rect.center.dx < from.center.dx : item.rect.center.dx > from.center.dx),
    );
  }
}

/// "Exit the app?" with Yes (focused) and No; Back answers No.
class _ExitDialog extends StatelessWidget {
  const _ExitDialog();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    Widget button(String label, bool answer) =>
        ActionButton(label: label, autofocus: answer, onPressed: () => Navigator.pop(context, answer));
    return Dialog(
      backgroundColor: WtvColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.exitQuestion, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            Row(mainAxisSize: MainAxisSize.min, spacing: 16, children: [button(l.yes, true), button(l.no, false)]),
          ],
        ),
      ),
    );
  }
}
