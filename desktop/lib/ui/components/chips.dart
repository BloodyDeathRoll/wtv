import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'pressable.dart';

/// A choice chip (sort, filter, season, group, setting): dark and borderless,
/// its text white at 50%, or full white on a darker chip when selected.
/// Focused, it turns light like the tabs.
class OptionChip extends StatelessWidget {
  const OptionChip({super.key, required this.selected, required this.onPressed, required this.label, this.focusNode});

  final bool selected;
  final VoidCallback onPressed;
  final String label;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    focusNode: focusNode,
    builder: (context, focused) => Pill(
      focused: focused,
      color: selected ? WtvColors.chipSelected : WtvColors.chip,
      textColor: selected ? WtvColors.textPrimary : WtvColors.textPrimary.withValues(alpha: 0.5),
      radius: 8,
      label: label,
    ),
  );
}

/// The shape under a chip, a tab or a button: its own colours, or light with dark text when focused.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.focused,
    required this.color,
    required this.textColor,
    required this.label,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    this.style,
  });

  final bool focused;
  final Color? color;
  final Color textColor;
  final String label;
  final double radius;
  final EdgeInsets padding;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: focused ? WtvColors.textPrimary : color,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(
      label,
      style: (style ?? Theme.of(context).textTheme.labelLarge!).copyWith(
        color: focused ? WtvColors.background : textColor,
      ),
    ),
  );
}
