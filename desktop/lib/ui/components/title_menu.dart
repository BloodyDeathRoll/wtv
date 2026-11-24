import 'package:material_ui/material_ui.dart' hide Title;

import '../../app_language.dart';
import '../../data/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../theme.dart';
import 'badges.dart';
import 'dialogs.dart';
import 'pressable.dart';

/// Opens a title card's menu, over whatever page the card is on; the app frame provides it.
class TitleMenuScope extends InheritedWidget {
  const TitleMenuScope({super.key, required this.onOpen, required super.child});

  final void Function(Title title, {required bool continuing}) onOpen;

  /// `continuing`: a card in Continue watching, whose menu can also take the title out of that row.
  static void open(BuildContext context, Title title, {bool continuing = false}) =>
      context.getInheritedWidgetOfExactType<TitleMenuScope>()?.onOpen(title, continuing: continuing);

  @override
  bool updateShouldNotify(TitleMenuScope old) => false;
}

/// What was chosen in a title's menu; the watchlist item does its work itself.
enum TitleMenuChoice { info, play, remove }

/// A title card's menu: Watchlist, Info, Play (focused), Close, each a row
/// with its icon at the start and its name after it (mirrored in Hebrew).
/// With `continuing`, Remove as well. Pops with the choice; Back closes.
class TitleMenu extends StatefulWidget {
  const TitleMenu(this.title, {super.key, required this.continuing});

  final Title title;
  final bool continuing;

  @override
  State<TitleMenu> createState() => _TitleMenuState();
}

class _TitleMenuState extends State<TitleMenu> {
  // Null until known: the watchlist item says Add or Remove.
  bool? _onWatchlist;

  @override
  void initState() {
    super.initState();
    services.catalog.marks(widget.title).then((marks) => marks.onWatchlist).catchError((Object _) => false, test: (e) => e is Exception).then((on) {
      if (mounted) setState(() => _onWatchlist = on);
    });
  }

  Future<void> _toggleWatchlist() async {
    final on = _onWatchlist;
    if (on == null) return;
    try {
      await services.catalog.setWatchlist(widget.title, !on);
    } on Exception catch (e) {
      debugPrint('Changing the watchlist failed: $e');
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final on = _onWatchlist ?? false;
    void choose(TitleMenuChoice? choice) => Navigator.pop(context, choice);
    return Panel(
      // Wide enough for the longest label in either language on one line.
      width: 440,
      children: [
        ContentText(widget.title.displayName(hebrew: isHebrew(context)), style: Theme.of(context).textTheme.titleLarge, maxLines: 2),
        const SizedBox(height: 16),
        Column(
          spacing: 8,
          children: [
            MenuItem(on ? Icons.check : Icons.add, on ? l.removeFromWatchlist : l.addToWatchlist, _toggleWatchlist),
            MenuItem(Icons.info_outline, l.moreInfo, () => choose(TitleMenuChoice.info)),
            MenuItem(Icons.play_arrow, l.play, () => choose(TitleMenuChoice.play), autofocus: true),
            if (widget.continuing) MenuItem(Icons.close, l.menuRemove, () => choose(TitleMenuChoice.remove)),
            MenuItem(Icons.close, l.close, () => choose(null)),
          ],
        ),
      ],
    );
  }
}

/// A row of a menu: the icon at the start (left in English, right in Hebrew), then its name.
class MenuItem extends StatelessWidget {
  const MenuItem(this.icon, this.label, this.onPressed, {super.key, this.autofocus = false});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    autofocus: autofocus,
    builder: (context, focused) {
      final color = focused ? WtvColors.background : WtvColors.textPrimary;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: focused ? WtvColors.textPrimary : WtvColors.chip, borderRadius: BorderRadius.circular(999)),
        child: Row(
          spacing: 16,
          children: [
            Icon(icon, size: 26, color: color),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(color: color),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    },
  );
}
