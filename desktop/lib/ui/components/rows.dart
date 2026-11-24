import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

const _scroll = Duration(milliseconds: 200);

/// A page of card rows under the arrow keys: the focused row lands at the top
/// with its title showing, as in the reference (`titleSpace` is the room kept
/// above a focused card); sideways, a row scrolls just far enough to show the
/// card. The mouse moves the focus without scrolling: its wheel scrolls.
class RowsAtTop extends StatelessWidget {
  const RowsAtTop({super.key, this.titleSpace = 40, required this.child});

  final double titleSpace;
  final Widget child;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: ReadingOrderTraversalPolicy(requestFocusCallback: _focus),
    child: child,
  );

  void _focus(FocusNode node, {ScrollPositionAlignmentPolicy? alignmentPolicy, double? alignment, Duration? duration, Curve? curve}) {
    node.requestFocus();
    final item = node.context?.findRenderObject();
    if (item == null) return;
    // Each list around the card, from the row out to the page.
    RenderObject inner = item;
    for (var list = Scrollable.maybeOf(node.context!); list != null; list = Scrollable.maybeOf(list.context)) {
      final position = list.position;
      if (axisDirectionToAxis(list.axisDirection) == Axis.horizontal) {
        // Each policy scrolls only when the card is cut off on its side: together, just far enough to show it.
        for (final policy in const [ScrollPositionAlignmentPolicy.keepVisibleAtEnd, ScrollPositionAlignmentPolicy.keepVisibleAtStart]) {
          position.ensureVisible(
            inner,
            alignmentPolicy: policy,
            duration: _scroll,
            curve: Curves.easeOut,
            targetRenderObject: identical(inner, item) ? null : item,
          );
        }
      } else {
        final top = RenderAbstractViewport.of(inner).getOffsetToReveal(item, 0).offset - titleSpace;
        position.animateTo(
          top.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: _scroll,
          curve: Curves.easeOut,
        );
      }
      inner = list.context.findRenderObject()!;
    }
  }
}
