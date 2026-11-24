import 'package:material_ui/material_ui.dart';

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/chips.dart';
import '../theme.dart';

/// Side bar → Categories, for movies or series: All movies (or series), the
/// provider's categories, then the genres, each with how many titles it has.
/// A tag opens its full grid, as More does at a row's end.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen(this.kind, {super.key, required this.firstFocus, required this.onOpen});

  final Kind kind;
  final FocusNode firstFocus;
  final ValueChanged<Category> onOpen;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool? _hebrew;
  // Null until loaded; a group that fails to load is left out. A group's label is null for the one with "All".
  List<(String?, List<Category>)>? _groups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hebrew = isHebrew(context);
    if (hebrew == _hebrew) return;
    _hebrew = hebrew;
    _load(hebrew, AppLocalizations.of(context)!);
  }

  Future<void> _load(bool hebrew, AppLocalizations l) async {
    final catalog = services.catalog;
    final kind = widget.kind;
    Future<T?> orNull<T>(Future<T> call) => call.then<T?>((value) => value).catchError((Object _) => null, test: (e) => e is Exception);
    final (providers, genres, counts) = await (
      orNull(catalog.categories(kind)),
      orNull(catalog.genreCategories(kind, hebrew: hebrew)),
      // Counts are a nicety: without them the tags show without numbers, and none is left out.
      orNull(catalog.categoryCounts(kind)),
    ).wait;
    if (!mounted || hebrew != _hebrew) return;
    List<Category> counted(String tag, List<Category>? list) => [
      for (final c in list ?? const <Category>[])
        if (counts == null) c else if (counts[(tag, c.id)] case final count?) c.copyWith(count: count),
    ];
    final allLabel = kind == Kind.movie ? l.categoriesAllMovies : l.categoriesAllSeries;
    final all = Category(0, kind, allLabel, allLabel, allLabel, all: true, count: counts?[('all', 0)]);
    final hadFocus = FocusScope.of(context).hasFocus;
    setState(() {
      _groups = [
        (null, [all]),
        (l.categoriesProviders, counted('category', providers)),
        (l.categoriesGenres, counted('genre', genres)),
      ].where((group) => group.$2.isNotEmpty).toList();
    });
    // The tags arrive after the page opened: the first one takes the focus then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && hadFocus && FocusScope.of(context).focusedChild == null) widget.firstFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = _hebrew!;
    final groups = _groups;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(start: 88, end: 48, top: 48, bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.railCategories, style: text.displayMedium),
          if (groups != null && groups.isEmpty) ...[
            const SizedBox(height: 24),
            Text(l.nothingHere, style: text.titleMedium!.copyWith(color: WtvColors.textMuted)),
          ],
          for (final (label, tags) in groups ?? const <(String?, List<Category>)>[]) ...[
            const SizedBox(height: 28),
            if (label != null) ...[
              Text(label, style: text.titleMedium!.copyWith(color: WtvColors.textSecondary)),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in tags)
                  OptionChip(
                    selected: false,
                    focusNode: identical(c, groups!.first.$2.first) ? widget.firstFocus : null,
                    label: c.label(hebrew: hebrew),
                    detail: c.count?.toString(),
                    onPressed: () => widget.onOpen(c),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
