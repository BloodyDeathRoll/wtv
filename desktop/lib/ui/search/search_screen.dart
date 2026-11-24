import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Title;

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../data/live.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/badges.dart';
import '../components/cards.dart';
import '../components/fields.dart';
import '../components/pressable.dart';
import '../components/title_menu.dart';
import '../theme.dart';

/// Wait this long after the last key before searching.
const typingPause = Duration(milliseconds: 400);

/// Suggestions under the field: a few names to pick from as you type.
const _suggestionCount = 6;

/// What a search looks in: everything (from Home), one section's titles, or Live TV's channels.
enum SearchScope {
  all(null),
  movies(Kind.movie),
  series(Kind.series),
  live(null);

  const SearchScope(this.kind);

  final Kind? kind;
}

sealed class _Results {
  const _Results();
}

class _Idle extends _Results {
  const _Idle();
}

class _Searching extends _Results {
  const _Searching();
}

class _Found extends _Results {
  const _Found(this.query, this.titles, this.people, [this.channels = const []]);

  /// The one searched, which the field may have moved on from.
  final String query;
  final List<Title> titles;
  final List<CastMember> people;
  final List<Channel> channels;

  bool get empty => titles.isEmpty && people.isEmpty && channels.isEmpty;
}

class _Failed extends _Results {
  const _Failed(this.message);

  final String message;
}

/// Text search, in English or Hebrew. As the user types, suggestions appear
/// under the field (actors and titles, or channels), then the results:
/// actors, then title posters, or channel cards on Live TV. Enter in the
/// field moves on to the results; Down goes to what is below it.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.scope,
    required this.field,
    required this.onOpen,
    required this.onPerson,
    required this.onWatch,
  });

  final SearchScope scope;

  /// The text field: it has the focus when the page opens.
  final FocusNode field;
  final ValueChanged<Title> onOpen;
  final ValueChanged<CastMember> onPerson;

  /// Watch `channels[index]` of the channels found.
  final void Function(List<Channel> channels, int index) onWatch;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  var _query = '';
  _Results _results = const _Idle();
  // Each search's number: the answer of one that a newer query has replaced is dropped.
  var _run = 0;
  Timer? _pause;
  bool? _hebrew;
  // Enter was pressed before the results were in: move to them when they arrive.
  var _toResults = false;
  // Suggestions show while the field or a suggestion has the focus; in the results they make room.
  var _nearField = true;
  final _firstSuggestion = FocusNode();
  final _firstResult = FocusNode();
  // Live TV searches the channel list, read once.
  List<Channel>? _channels;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hebrew = isHebrew(context);
    final changed = _hebrew != null && _hebrew != hebrew;
    _hebrew = hebrew;
    // The other language's names are searched and shown.
    if (changed) _search();
  }

  @override
  void dispose() {
    _pause?.cancel();
    _text.dispose();
    _firstSuggestion.dispose();
    _firstResult.dispose();
    super.dispose();
  }

  // The field also tells of a moved cursor: only a changed text is a new query.
  void _onText() {
    if (_text.text == _query) return;
    _query = _text.text;
    _toResults = false;
    _search();
  }

  /// A new query drops the search of the previous one.
  void _search() {
    final run = ++_run;
    _pause?.cancel();
    final q = _query.trim();
    if (q.isEmpty) {
      setState(() => _results = const _Idle());
      return;
    }
    _pause = Timer(typingPause, () async {
      // Earlier results stay on screen until the new ones arrive: no flicker while typing.
      if (_results is! _Found) setState(() => _results = const _Searching());
      final catalog = services.catalog;
      final kind = widget.scope.kind;
      _Results next;
      try {
        if (widget.scope == SearchScope.live) {
          final lower = q.toLowerCase();
          // Every channel, hidden ones too, as in the TV app: a search is how a hidden one is still reached.
          final hits = (_channels ??= await catalog.channels()).where((c) => c.name.toLowerCase().contains(lower)).toList();
          bool starts(Channel c) => c.name.toLowerCase().startsWith(lower);
          // Names starting with the query first, as titles and actors are ordered.
          next = _Found(q, const [], const [], [...hits.where(starts), ...hits.where((c) => !starts(c))]);
        } else {
          final titles = catalog.search(q, hebrew: _hebrew!, kind: kind);
          // Actors are a nicety: without them the titles still show.
          final people = catalog.searchPeople(q, kind: kind).catchError((Object _) => const <CastMember>[], test: (e) => e is Exception);
          next = _Found(q, await titles, await people);
        }
      } on Exception catch (e) {
        next = _Failed(e is ApiException ? e.message : e.toString());
      }
      if (!mounted || run != _run) return;
      setState(() => _results = next);
      if (!_toResults) return;
      _toResults = false;
      // Not when the focus has moved on meanwhile (to a suggestion, to the side rail).
      if (next is _Found && !next.empty && widget.field.hasPrimaryFocus) {
        // Once the results are laid out.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _firstResult.context != null) _firstResult.requestFocus();
        });
      }
    });
  }

  /// Enter in the field moves on to the results, now or when they arrive.
  void _submit() {
    final r = _results;
    if (r is _Found && r.query == _query.trim()) {
      // This query's results are in: to the first one, if there is any.
      if (_firstResult.context != null) _firstResult.requestFocus();
    } else {
      // Results for an earlier query may still be on screen: wait for this one's.
      _toResults = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = _hebrew!;
    final r = _results;
    // The last results' suggestions stay while the next ones load: no jump on every key.
    final suggestions = r is! _Found || _query.trim().isEmpty
        ? const <_Suggestion>[]
        : [
            for (final p in r.people.take(2)) _Suggestion(p.name, l.searchActor, () => widget.onPerson(p)),
            for (final t in r.titles) _Suggestion(t.displayName(hebrew: hebrew), t.year?.toString(), () => widget.onOpen(t)),
            for (final (i, c) in r.channels.indexed) _Suggestion(c.name, null, () => widget.onWatch(r.channels, i)),
          ].take(_suggestionCount).toList();
    final showSuggestions = _nearField && suggestions.isNotEmpty;
    final fieldStyle = text.headlineMedium!.copyWith(color: WtvColors.textPrimary);
    Widget note(String message) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Text(message, style: text.titleMedium!.copyWith(color: WtvColors.textMuted)),
    );
    return Padding(
      // 8 less than the page's 88: the results keep that room for the focused card's lift.
      padding: const EdgeInsetsDirectional.only(start: 80, end: 48, top: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) => setState(() => _nearField = hasFocus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldKeys(
                    controller: _text,
                    // The first suggestion or the first result, not whichever card is nearest.
                    onDown: () {
                      final below = showSuggestions ? _firstSuggestion : _firstResult;
                      if (below.context != null) below.requestFocus();
                    },
                    child: TextField(
                      controller: _text,
                      focusNode: widget.field,
                      style: fieldStyle,
                      cursorColor: WtvColors.textPrimary,
                      textInputAction: TextInputAction.search,
                      // Back in the field the text is typed on, as on the TV: not replaced.
                      selectAllOnFocus: false,
                      // Enter keeps the focus in the field unless there are results to move to.
                      onEditingComplete: () {},
                      onSubmitted: (_) => _submit(),
                      // A click on the page's background leaves the focus where it is.
                      onTapOutside: (_) {},
                      decoration: fieldDecoration(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        hint: switch (widget.scope) {
                          SearchScope.all => l.searchHint,
                          SearchScope.movies => l.searchHintMovies,
                          SearchScope.series => l.searchHintSeries,
                          SearchScope.live => l.searchHintLive,
                        },
                        hintStyle: fieldStyle.copyWith(color: WtvColors.textMuted),
                      ),
                    ),
                  ),
                  if (showSuggestions) ...[
                    const SizedBox(height: 8),
                    for (final (i, s) in suggestions.indexed)
                      Pressable(
                        focusNode: i == 0 ? _firstSuggestion : null,
                        onPressed: s.pick,
                        builder: (context, focused) {
                          final color = focused ? WtvColors.background : WtvColors.textSecondary;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(color: focused ? WtvColors.textPrimary : null, borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              spacing: 16,
                              children: [
                                Expanded(child: ContentText(s.text, style: text.titleSmall!.copyWith(color: color), maxLines: 1)),
                                if (s.tag != null) Text(s.tag!, style: text.labelMedium!.copyWith(color: color)),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          switch (r) {
            _Idle() => const SizedBox.shrink(),
            _Searching() => note(l.searching),
            _Failed(:final message) => note(l.loadFailed(message)),
            _Found() when r.empty => note(l.noResults(r.query)),
            _Found() => Expanded(child: _found(r, hebrew)),
          },
        ],
      ),
    );
  }

  /// The results: actors (named), then title posters; or channel cards. The first one takes Enter from the field.
  Widget _found(_Found r, bool hebrew) => r.channels.isNotEmpty ? _foundChannels(r.channels) : _foundTitles(r, hebrew);

  Widget _foundChannels(List<Channel> channels) => GridView.builder(
    padding: const EdgeInsetsDirectional.only(start: 8, end: 8, top: 6, bottom: 48),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 5,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 16 / 9,
    ),
    itemCount: channels.length,
    itemBuilder: (context, i) {
      final c = channels[i];
      return ChannelCard(
        key: ValueKey(c.id),
        logo: c.logo,
        name: c.name,
        number: c.num,
        favorite: false,
        onPressed: () => widget.onWatch(channels, i),
        focusNode: i == 0 ? _firstResult : null,
      );
    },
  );

  Widget _foundTitles(_Found r, bool hebrew) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (r.people.isNotEmpty)
        SizedBox(
          // A 96 wide portrait's height, and the padding.
          height: 128 + 6 + 12,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(start: 8, top: 6, bottom: 12),
            itemCount: r.people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final p = r.people[i];
              return ImageCard.person(
                key: ValueKey(p.personId),
                imageUrl: p.photo,
                title: p.name,
                label: p.name,
                onPressed: () => widget.onPerson(p),
                focusNode: i == 0 ? _firstResult : null,
              );
            },
          ),
        ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsetsDirectional.only(start: 8, top: 6, bottom: 48),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            crossAxisSpacing: 16,
            mainAxisSpacing: 18,
            // A 120 wide poster's height.
            mainAxisExtent: 180,
          ),
          itemCount: r.titles.length,
          itemBuilder: (context, i) {
            final t = r.titles[i];
            return Align(
              key: ValueKey(t.id),
              alignment: AlignmentDirectional.topStart,
              child: ImageCard.poster(
                imageUrl: t.posterImage,
                title: t.displayName(hebrew: hebrew),
                onPressed: () => widget.onOpen(t),
                onMenu: () => TitleMenuScope.open(context, t),
                focusNode: r.people.isEmpty && i == 0 ? _firstResult : null,
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// A suggestion under the field: what it shows, a word for its kind (actor) or its year, and what picking it does.
class _Suggestion {
  const _Suggestion(this.text, this.tag, this.pick);

  final String text;
  final String? tag;
  final VoidCallback pick;
}
