import 'package:material_ui/material_ui.dart';

/// An item the arrow keys can reach and Enter, Space or a click presses.
/// The mouse moves the focus too: the item under a moving pointer takes it,
/// so there is one highlight, not one for the keys and one for the mouse.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.hoverFocuses = true,
    this.semanticLabel,
  });

  final VoidCallback onPressed;
  final Widget Function(BuildContext context, bool focused) builder;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// False where taking the focus has an effect of its own (a tab switches the section).
  final bool hoverFocuses;

  /// For an item with no text of its own (an icon).
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  FocusNode? _own;
  // A node from outside may hold the focus already when this item is built.
  late bool _focused = widget.focusNode?.hasFocus ?? false;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.semanticLabel,
    child: FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed())},
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        widget.onFocusChange?.call(focused);
      },
      child: MouseRegion(
        // Hover, not enter: a list scrolling under a still pointer must not take the focus from the keys.
        onHover: widget.hoverFocuses ? (_) => _node.requestFocus() : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _node.requestFocus();
            widget.onPressed();
          },
          child: widget.builder(context, _focused),
        ),
      ),
    ),
  );
}
