import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'pressable.dart';

/// The side rail's entries. Categories is shown only where it has something to list.
enum RailItem { search, categories, mainMenu, watchlist, settings }

/// The narrow icon rail on the left (right in Hebrew): search, categories,
/// main menu, watchlist, settings. With the focus on it, it opens and names
/// each icon. The arrow towards the page calls `onLeave`, and so does the
/// pointer when it moves off the rail.
class SideRail extends StatefulWidget {
  const SideRail({
    super.key,
    required this.nodes,
    required this.onSelect,
    required this.onLeave,
    this.showCategories = true,
  });

  /// One per item, so the page can hand the focus to the nearest one.
  final Map<RailItem, FocusNode> nodes;
  final ValueChanged<RailItem> onSelect;
  final VoidCallback onLeave;
  final bool showCategories;

  @override
  State<SideRail> createState() => _SideRailState();
}

class _SideRailState extends State<SideRail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardsPage = rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
    final items = [
      (RailItem.search, Icons.search_outlined, l.railSearch),
      if (widget.showCategories) (RailItem.categories, Icons.grid_view_outlined, l.railCategories),
      (RailItem.mainMenu, Icons.home_outlined, l.railMainMenu),
      (RailItem.watchlist, Icons.bookmark_border_outlined, l.railWatchlist),
      (RailItem.settings, Icons.settings_outlined, l.railSettings),
    ];
    return MouseRegion(
      onExit: (_) {
        if (_open) widget.onLeave();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) => setState(() => _open = hasFocus),
        onKeyEvent: (_, event) {
          if (event.logicalKey != towardsPage) return KeyEventResult.ignored;
          if (event is KeyDownEvent) widget.onLeave();
          return KeyEventResult.handled;
        },
        child: Container(
          // Open, it lies over the page: a shade keeps the labels readable.
          // Closed, an empty decoration: with none, opening would rebuild the items from nothing, focus highlight included.
          decoration: !_open
              ? const BoxDecoration()
              : BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      WtvColors.background,
                      WtvColors.background,
                      WtvColors.background.withValues(alpha: 0.9),
                      // Clear, but still this colour: fading to clear black would draw a dark band.
                      WtvColors.background.withValues(alpha: 0),
                    ],
                  ),
                ),
          padding: EdgeInsetsDirectional.only(start: 20, end: _open ? 96 : 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              for (final (item, icon, label) in items)
                Pressable(
                  focusNode: widget.nodes[item],
                  onPressed: () => widget.onSelect(item),
                  // Closed, the icon is all there is to read.
                  semanticLabel: _open ? null : label,
                  builder: (context, focused) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: focused ? WtvColors.textPrimary : null,
                        ),
                        child: Icon(icon, size: 22, color: focused ? WtvColors.background : WtvColors.textMuted),
                      ),
                      if (_open)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 14),
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                              color: focused ? WtvColors.textPrimary : WtvColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
