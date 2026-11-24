import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../browse/browse_screen.dart';
import '../components/buttons.dart';
import '../components/cards.dart';
import '../components/chips.dart';
import '../components/hero.dart';
import '../components/rows.dart';
import '../theme.dart';

const _columns = 4;
const _page = 60;

/// Load the next page when the focus gets this close to the end.
const _preload = 2 * _columns;

/// A 200 wide landscape card's height.
const _cardHeight = 112.5;
const _rowGap = 28.0;
const _edge = 12.0;

/// A whole category in rows of four, with a choice of order. The focused
/// title's header and backdrop show above the rows.
class GridScreen extends StatelessWidget {
  const GridScreen(this.category, {super.key, required this.firstFocus, required this.onOpen});

  final Category category;
  final FocusNode firstFocus;
  final ValueChanged<Title> onOpen;

  @override
  Widget build(BuildContext context) {
    final hebrew = isHebrew(context);
    final catalog = services.catalog;
    return PosterGrid(
      label: category.label(hebrew: hebrew),
      firstFocus: firstFocus,
      onOpen: onOpen,
      fetch: (sort, offset, limit) => sort == null
          ? catalog.recommendedPage(category, offset: offset, limit: limit)
          : catalog.page(category, sort, hebrew: hebrew, offset: offset, limit: limit),
    );
  }
}

/// Titles in rows of four under `label`, two rows on screen, loaded `pageSize`
/// at a time as the focus nears the end. With `sorts`, chips choose the order
/// (null: Recommended); without, `fetch` gets null.
class PosterGrid extends StatefulWidget {
  const PosterGrid({
    super.key,
    required this.label,
    required this.firstFocus,
    required this.onOpen,
    required this.fetch,
    this.sorts = true,
    this.pageSize = _page,
  });

  final String label;
  final FocusNode firstFocus;
  final ValueChanged<Title> onOpen;
  final Future<List<Title>> Function(Sort? sort, int offset, int limit) fetch;
  final bool sorts;
  final int pageSize;

  @override
  State<PosterGrid> createState() => _PosterGridState();
}

class _PosterGridState extends State<PosterGrid> {
  // Null: Recommended, the user's WTW ranking (newest first without one).
  Sort? _sort;
  bool? _hebrew;
  var _titles = <Title>[];
  // Rows received so far: the next offset. Not the number of titles, which drops repeats.
  var _fetched = 0;
  var _end = false;
  var _loading = false;
  String? _error;
  Title? _focused;
  // Each order's number: a page that arrives for an order since left is dropped.
  var _order = 0;
  // The first page takes the focus only on opening: after a sort change the focus stays on the chips.
  var _placed = false;
  final _chips = FocusNode();
  // Genre names are a nicety: without them the header's meta line just has no genres.
  var _genres = const <(Kind, int), Genre>{};

  @override
  void initState() {
    super.initState();
    services.catalog.genres().then((genres) {
      if (mounted) setState(() => _genres = genres);
    }, onError: (Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hebrew = isHebrew(context);
    if (hebrew == _hebrew) return;
    _hebrew = hebrew;
    _restart();
  }

  @override
  void dispose() {
    _chips.dispose();
    super.dispose();
  }

  /// A new order or language: the titles are read again from the start.
  void _restart() {
    _order++;
    _titles = [];
    _fetched = 0;
    _end = _loading = false;
    _error = null;
    _focused = null;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _end) return;
    final order = _order;
    setState(() => _loading = true);
    final before = _titles.length;
    try {
      final page = await widget.fetch(_sort, _fetched, widget.pageSize);
      if (!mounted || order != _order) return;
      _fetched += page.length;
      // A sync between two pages shifts rows, so a title can come twice: keys must stay unique.
      final seen = {for (final t in _titles) t.id};
      _titles = [..._titles, ...page.where((t) => seen.add(t.id))];
      if (page.length < widget.pageSize) _end = true;
      _focused ??= page.firstOrNull;
      _error = null;
    } on Exception catch (e) {
      if (!mounted || order != _order) return;
      _error = e is ApiException ? e.message : e.toString();
    }
    final addedNothing = _error == null && _titles.length == before;
    setState(() => _loading = false);
    // A page made only of repeats: no new card to focus, so fetch the next one now.
    if (addedNothing) return _loadMore();
    // The page had nothing to focus while it loaded; when the first titles arrive, the first card takes the focus.
    if (_titles.isNotEmpty && !_placed) {
      _placed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && FocusScope.of(context).hasFocus) widget.firstFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = _hebrew!;
    final focused = _focused;
    final labels = {null: l.sortRecommended, Sort.added: l.sortAdded, Sort.year: l.sortYear, Sort.name: l.sortName, Sort.rating: l.sortRating};
    return Stack(
      fit: StackFit.expand,
      children: [
        Backdrop(focused?.heroImage),
        // The name and the sort chips sit where the tabs are on the browse pages: the name
        // at the start, the chips across from it at the end, in line with the rows' end.
        PositionedDirectional(
          start: 88,
          end: 30,
          top: 18,
          child: Row(
            children: [
              Expanded(child: Text(widget.label, style: text.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              // Without sorts the order stays null, which `fetch` gets.
              if (widget.sorts) ...[
                const SizedBox(width: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    // Recommended (null) is not a Sort: it is a server function, not a REST order.
                    for (final sort in <Sort?>[null, ...Sort.values])
                      OptionChip(
                        selected: sort == _sort,
                        focusNode: sort == null ? _chips : null,
                        label: labels[sort]!,
                        onPressed: () {
                          if (sort == _sort) return;
                          _sort = sort;
                          _restart();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          // 8 less than the page's 88: the grid keeps that room for the focused card's lift.
          padding: const EdgeInsetsDirectional.only(start: 80, top: headerTop),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: focused == null ? const SizedBox(height: headerHeight) : TitleHeader(focused, _genres),
              ),
              if (_titles.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: _error != null
                      // While a retry runs the button stays, holding the focus, and the text says so.
                      ? _Message(_loading ? l.loading : l.loadFailed(_error!), focusNode: widget.firstFocus, onRetry: _loadMore)
                      : _Message(_end ? l.nothingHere : l.loading),
                )
              else
                // Two rows high: the rows under them stay hidden.
                SizedBox(
                  height: _edge * 2 + _cardHeight * 2 + _rowGap,
                  // The focused row goes to the top, so each step down shows one new row.
                  child: RowsAtTop(
                    titleSpace: _edge,
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          // End: four 200 wide cards fill the row. Top and bottom: room for the focused card's lift.
                          padding: const EdgeInsetsDirectional.only(start: 8, top: _edge, end: 30, bottom: _edge),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _columns,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: _rowGap,
                              mainAxisExtent: _cardHeight,
                            ),
                            itemCount: _titles.length,
                            itemBuilder: (context, i) {
                              final t = _titles[i];
                              final card = ImageCard.landscape(
                                imageUrl: t.cardImage,
                                title: t.displayName(hebrew: hebrew),
                                onPressed: () => widget.onOpen(t),
                                onFocused: () {
                                  setState(() => _focused = t);
                                  if (i >= _titles.length - _preload) _loadMore();
                                },
                                focusNode: i == 0 ? widget.firstFocus : null,
                              );
                              return Align(
                                key: ValueKey(t.id),
                                alignment: AlignmentDirectional.topStart,
                                // Up from the first row goes to the sort chips.
                                child: widget.sorts && i < _columns ? _UpTo(_chips, child: card) : card,
                              );
                            },
                          ),
                        ),
                        // A later page failed: a Retry under the grid, since the focus may not move again.
                        if (_error != null)
                          SliverToBoxAdapter(
                            child: Center(child: ActionButton(label: l.retry, onPressed: _loadMore)),
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
}

/// The Up arrow on `child` gives the focus to `target`.
class _UpTo extends StatelessWidget {
  const _UpTo(this.target, {required this.child});

  final FocusNode target;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
      if (event is! KeyUpEvent) target.requestFocus();
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// Loading, empty or error message; with `onRetry`, a Retry button that can take the focus.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.focusNode, this.onRetry});

  final String text;
  final FocusNode? focusNode;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: Theme.of(context).textTheme.titleMedium!.copyWith(color: WtvColors.textMuted)),
      if (onRetry != null) ...[
        const SizedBox(height: 16),
        ActionButton(label: AppLocalizations.of(context)!.retry, focusNode: focusNode, onPressed: onRetry!),
      ],
    ],
  );
}
