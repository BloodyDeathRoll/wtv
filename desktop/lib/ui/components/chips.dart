import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'pressable.dart';

/// A choice chip (sort, filter, season, group, setting): dark and borderless,
/// its text white at 50%, or full white on a darker chip when selected.
/// Focused, it turns light like the tabs.
class OptionChip extends StatelessWidget {
  const OptionChip({super.key, required this.selected, required this.onPressed, required this.label, this.detail, this.focusNode});

  final bool selected;
  final VoidCallback onPressed;
  final String label;

  /// A second, quieter text after the label (a category's number of titles).
  final String? detail;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    focusNode: focusNode,
    selected: selected,
    builder: (context, focused) => Pill(
      focused: focused,
      color: selected ? WtvColors.chipSelected : WtvColors.chip,
      textColor: selected ? WtvColors.textPrimary : WtvColors.textPrimary.withValues(alpha: 0.5),
      radius: 8,
      label: label,
      detail: detail,
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
    this.detail,
  });

  final bool focused;
  final Color? color;
  final Color textColor;
  final String label;
  final double radius;
  final EdgeInsets padding;
  final TextStyle? style;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final color = focused ? WtvColors.background : textColor;
    final style = (this.style ?? Theme.of(context).textTheme.labelLarge!).copyWith(color: color);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: focused ? WtvColors.textPrimary : this.color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: detail == null
          ? Text(label, style: style)
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                Text(label, style: style),
                Text(detail!, style: style.copyWith(color: color.withValues(alpha: 0.6))),
              ],
            ),
    );
  }
}
