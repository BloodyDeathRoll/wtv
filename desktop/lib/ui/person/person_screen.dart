import 'package:material_ui/material_ui.dart' hide Title;

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/badges.dart';
import '../components/buttons.dart';
import '../components/cards.dart';
import '../components/chips.dart';
import '../components/hero.dart';
import '../components/title_menu.dart';
import '../theme.dart';

/// A cast member's page: their photo and name, then every title of theirs the provider has.
class PersonScreen extends StatelessWidget {
  const PersonScreen(this.person, {super.key, required this.firstFocus, required this.onOpen});

  final CastMember person;
  final FocusNode firstFocus;
  final ValueChanged<Title> onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final photo = person.photo;
    return TitlesPage(
      load: () => services.catalog.personTitles(person.personId),
      firstFocus: firstFocus,
      onOpen: onOpen,
      header: (context, count) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (photo != null) ...[
            ClipOval(
              child: Image.network(
                photo,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.square(dimension: 96),
              ),
            ),
            const SizedBox(width: 24),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ContentText(person.name, style: text.displayMedium, maxLines: 1),
                if (count != null)
                  Text(
                    AppLocalizations.of(context)!.personTitles(count),
                    style: text.titleSmall!.copyWith(color: WtvColors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _Load {
  const _Load();
}

class _Loading extends _Load {
  const _Loading();
}

class _Ready extends _Load {
  const _Ready(this.titles);

  final List<Title> titles;
}

class _Failed extends _Load {
  const _Failed(this.message);

  final String message;
}

/// A page of title posters under a header: a person's titles, the watchlist.
/// `header` gets the number of titles once they are in. With `kinds`, chips
/// across from the header show all titles, the movies or the series. The
/// titles are read again when `reload` changes.
class TitlesPage extends StatefulWidget {
  const TitlesPage({
    super.key,
    required this.load,
    required this.firstFocus,
    required this.onOpen,
    required this.header,
    this.kinds = false,
    this.reload,
  });

  final Future<List<Title>> Function() load;
  final FocusNode firstFocus;
  final ValueChanged<Title> onOpen;
  final Widget Function(BuildContext context, int? count) header;
  final bool kinds;
  final Listenable? reload;

  @override
  State<TitlesPage> createState() => _TitlesPageState();
}

class _TitlesPageState extends State<TitlesPage> {
  _Load _load = const _Loading();
  // Each load's number: the answer of one that a newer load has replaced is dropped.
  var _run = 0;
  // Null: all titles.
  Kind? _kind;
  // The focused poster's name shows under the header, as on a category's page.
  Title? _focused;

  @override
  void initState() {
    super.initState();
    widget.reload?.addListener(_loadTitles);
    _loadTitles();
  }

  @override
  void dispose() {
    widget.reload?.removeListener(_loadTitles);
    super.dispose();
  }

  Future<void> _loadTitles() async {
    final run = ++_run;
    // A reload keeps the posters on screen until the new ones are in.
    if (_load is! _Ready) setState(() => _load = const _Loading());
    _Load next;
    try {
      next = _Ready(await widget.load());
    } on Exception catch (e) {
      next = _Failed(e is ApiException ? e.message : e.toString());
    }
    if (!mounted || run != _run) return;
    setState(() {
      _load = next;
      // The header no longer names a poster that is gone.
      if (next is! _Ready || !next.titles.any((t) => t.id == _focused?.id)) _focused = null;
    });
    // The page had nothing to focus while it loaded, so it held the focus itself: its
    // first item (Retry, the first poster) takes it. Not when the focus is elsewhere.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && FocusScope.of(context).hasPrimaryFocus && widget.firstFocus.context != null) widget.firstFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = isHebrew(context);
    final load = _load;
    final shown = load is _Ready
        ? [
            for (final t in load.titles)
              if (_kind == null || t.kind == _kind) t,
          ]
        : const <Title>[];
    final focused = _focused;
    Widget message(String message, {VoidCallback? onRetry}) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Text(message, style: text.titleMedium!.copyWith(color: WtvColors.textMuted)),
          if (onRetry != null) ActionButton(label: l.retry, focusNode: widget.firstFocus, onPressed: onRetry),
        ],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Backdrop(focused?.heroImage),
        Padding(
          // 8 less than the page's 88: the grid keeps that room for the focused poster's lift.
          padding: const EdgeInsetsDirectional.only(start: 80, end: 48, top: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The chips across from the header: at the end, which is the left in Hebrew.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: widget.header(context, load is _Ready ? load.titles.length : null)),
                        if (widget.kinds)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 24),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 8,
                              children: [
                                for (final (kind, label) in [(null, l.filterAll), (Kind.movie, l.tabMovies), (Kind.series, l.tabSeries)])
                                  OptionChip(
                                    selected: kind == _kind,
                                    label: label,
                                    onPressed: () => setState(() {
                                      _kind = kind;
                                      _focused = null;
                                    }),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ContentText(
                      focused == null
                          ? ' '
                          : [focused.displayName(hebrew: hebrew), ?focused.year?.toString(), ?focused.certification].join('   '),
                      style: text.titleSmall!.copyWith(color: WtvColors.textSecondary),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              switch (load) {
                _Loading() => message(l.loading),
                _Failed(message: final reason) => message(l.loadFailed(reason), onRetry: _loadTitles),
                _Ready() when shown.isEmpty => message(l.nothingHere),
                _Ready() => Expanded(
                  child: GridView.builder(
                    // Start and top: room for the focused poster's lift.
                    padding: const EdgeInsetsDirectional.only(start: 8, top: 6, bottom: 48),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 18,
                      // A 120 wide poster's height.
                      mainAxisExtent: 180,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final t = shown[i];
                      return Align(
                        key: ValueKey(t.id),
                        alignment: AlignmentDirectional.topStart,
                        child: ImageCard.poster(
                          imageUrl: t.posterImage,
                          title: t.displayName(hebrew: hebrew),
                          onPressed: () => widget.onOpen(t),
                          onMenu: () => TitleMenuScope.open(context, t),
                          onFocused: () => setState(() => _focused = t),
                          focusNode: i == 0 ? widget.firstFocus : null,
                        ),
                      );
                    },
                  ),
                ),
              },
            ],
          ),
        ),
      ],
    );
  }
}
