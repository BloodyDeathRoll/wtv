import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'chips.dart';
import 'pressable.dart';

/// A button with a text: a dark pill, light when focused.
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.onPressed, this.focusNode, this.autofocus = false});

  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    focusNode: focusNode,
    autofocus: autofocus,
    builder: (context, focused) => Pill(
      focused: focused,
      color: WtvColors.chip,
      textColor: WtvColors.textPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      label: label,
    ),
  );
}
