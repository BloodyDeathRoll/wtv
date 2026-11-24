import 'package:flutter/services.dart';
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
    this.selected,
    this.semanticLabel,
    this.onMenu,
  });

  final VoidCallback onPressed;
  final Widget Function(BuildContext context, bool focused) builder;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// False where taking the focus has an effect of its own (a tab switches the section).
  final bool hoverFocuses;

  /// For a screen reader: whether this is the chosen one of a group (a tab, a chip). Null for a plain button.
  final bool? selected;

  /// For an item with no text of its own (an icon).
  final String? semanticLabel;

  /// Opens the item's menu, where the TV has "hold OK": a right click, the Menu key or Shift+F10.
  final VoidCallback? onMenu;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  FocusNode? _own;
  // A node from outside may hold the focus already when this item is built.
  late bool _focused = widget.focusNode?.hasFocus ?? false;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (widget.focusNode != old.focusNode) _focused = _node.hasFocus;
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: widget.selected,
    label: widget.semanticLabel,
    child: FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      shortcuts: widget.onMenu == null ? null : _menuKeys,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        _MenuIntent: CallbackAction<_MenuIntent>(onInvoke: (_) => widget.onMenu?.call()),
      },
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
          onSecondaryTap: widget.onMenu == null
              ? null
              : () {
                  _node.requestFocus();
                  widget.onMenu!();
                },
          child: widget.builder(context, _focused),
        ),
      ),
    ),
  );
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}

const _menuKeys = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
  SingleActivator(LogicalKeyboardKey.f10, shift: true): _MenuIntent(),
};
