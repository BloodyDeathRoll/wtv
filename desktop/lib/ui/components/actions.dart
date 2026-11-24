import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'pressable.dart';

/// The main action on a title page. Light when focused, like the reference.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.label, required this.onPressed, this.focusNode});

  final String label;
  final VoidCallback onPressed;

  /// The title page focuses Play first.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    focusNode: focusNode,
    builder: (context, focused) {
      final color = focused ? WtvColors.background : WtvColors.textPrimary;
      return Container(
        padding: const EdgeInsetsDirectional.only(start: 16, end: 24, top: 10, bottom: 10),
        decoration: BoxDecoration(
          color: focused ? WtvColors.textPrimary : WtvColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(Icons.play_arrow, size: 22, color: color),
            Text(label, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: color)),
          ],
        ),
      );
    },
  );
}

/// A round icon action next to Play: watchlist, Love, Like, Dislike, more info.
/// Focused, it names itself underneath, like the reference.
class ActionIcon extends StatelessWidget {
  const ActionIcon({super.key, required this.icon, required this.description, required this.onPressed, this.selected});

  final IconData icon;
  final String description;
  final VoidCallback onPressed;

  /// For a rating or the watchlist: whether it is chosen. Null for a plain action.
  final bool? selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Pressable(
      onPressed: onPressed,
      semanticLabel: description,
      selected: selected,
      builder: (context, focused) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: focused ? WtvColors.textPrimary : null, shape: BoxShape.circle),
            child: Icon(
              icon,
              size: 24,
              color: focused
                  ? WtvColors.background
                  : selected ?? false
                  ? WtvColors.accent
                  : WtvColors.textPrimary,
            ),
          ),
          if (focused)
            // Laid out with no width: centred under the button, outside the row.
            Positioned(
              top: 46,
              height: 16,
              child: SizedBox(
                width: 0,
                child: OverflowBox(
                  maxWidth: double.infinity,
                  child: ExcludeSemantics(
                    child: Text(description, style: Theme.of(context).textTheme.labelMedium, maxLines: 1, softWrap: false),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The thin line between the title actions and the ratings.
class ActionDivider extends StatelessWidget {
  const ActionDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(width: 1, height: 28, child: ColoredBox(color: WtvColors.textMuted)),
  );
}
