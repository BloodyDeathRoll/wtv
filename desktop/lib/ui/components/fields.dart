import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// A text field keeps the arrow keys for its cursor. Around one, Up and Down
/// move the focus instead, as on the TV; in an empty field, where there is no
/// text to move in, so does the arrow towards the side rail.
class FieldKeys extends StatelessWidget {
  const FieldKeys({super.key, required this.controller, required this.child, this.onDown});

  final TextEditingController controller;
  final Widget child;

  /// Down, where it is not simply "to what is below".
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final empty = controller.text.isEmpty;
      final key = event.logicalKey;
      final TraversalDirection direction;
      if (key == LogicalKeyboardKey.arrowDown) {
        direction = TraversalDirection.down;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        direction = TraversalDirection.up;
      } else if (empty && key == (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
        direction = rtl ? TraversalDirection.right : TraversalDirection.left;
      } else {
        return KeyEventResult.ignored;
      }
      if (direction == TraversalDirection.down && onDown != null) {
        onDown!();
      } else {
        Actions.invoke(context, DirectionalFocusIntent(direction));
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// A text field's box: the surface colour, with a white edge when it has the focus.
InputDecoration fieldDecoration({required EdgeInsets padding, String? hint, TextStyle? hintStyle}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color, width: 2),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: hintStyle,
    hintMaxLines: 1,
    isDense: true,
    filled: true,
    fillColor: WtvColors.surface,
    hoverColor: Colors.transparent,
    contentPadding: padding,
    enabledBorder: border(WtvColors.surface),
    focusedBorder: border(WtvColors.focus),
  );
}
