import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

/// Mouse arrows on a sideways row: while the pointer is over the row, an arrow
/// shows at each end it can still scroll to, and a click moves the row by most
/// of its width. The arrows take no focus: the keys keep their own way.
class SideArrows extends StatefulWidget {
  const SideArrows({super.key, required this.builder});

  /// The row's list, built on this controller.
  final Widget Function(ScrollController controller) builder;

  @override
  State<SideArrows> createState() => _SideArrowsState();
}

class _SideArrowsState extends State<SideArrows> {
  final _controller = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(double sign) {
    final p = _controller.position;
    p.animateTo(
      (p.pixels + sign * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Stack(
      children: [
        widget.builder(_controller),
        if (_hover)
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (!_controller.hasClients || !_controller.position.hasContentDimensions) return const SizedBox.shrink();
              final p = _controller.position;
              return Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.pixels > p.minScrollExtent) _Arrow(Icons.chevron_left, () => _page(-1)),
                    const Spacer(),
                    if (p.pixels < p.maxScrollExtent) _Arrow(Icons.chevron_right, () => _page(1)),
                  ],
                ),
              );
            },
          ),
      ],
    ),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow(this.icon, this.onTap);

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        color: const Color(0xB30F171E),
        child: Icon(icon, size: 36, color: const Color(0xFFFFFFFF)),
      ),
    ),
  );
}

/// A page of rows whose items do not line up (a form: Settings). Up and Down
/// go to the nearest row, and in it to the item nearest sideways. The
/// framework's own rule prefers an item straight above or below, however far,
/// and so skips a row whose only items lie to the side. It looks at every item
/// of the page on each key press: for a page of tens of items, not thousands.
class NearestRows extends StatelessWidget {
  const NearestRows({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(policy: _NearestRowPolicy(), child: child);
}

class _NearestRowPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction != TraversalDirection.up && direction != TraversalDirection.down) return super.inDirection(currentNode, direction);
    final down = direction == TraversalDirection.down;
    final from = currentNode.rect;
    double gap(FocusNode node) => down ? node.rect.top - from.bottom : from.top - node.rect.bottom;
    // What lies wholly beyond this item (a pixel of overlap is rounding).
    final beyond = [
      for (final node in currentNode.nearestScope!.traversalDescendants)
        if (node != currentNode && gap(node) > -1) node,
    ];
    if (beyond.isEmpty) return false;
    final nearest = beyond.reduce((a, b) => gap(a) <= gap(b) ? a : b);
    // Its row: what lies level with it.
    final row = beyond.where((node) => node.rect.top < nearest.rect.bottom && node.rect.bottom > nearest.rect.top);
    double aside(FocusNode node) => (node.rect.center.dx - from.center.dx).abs();
    requestFocusCallback(
      row.reduce((a, b) => aside(a) <= aside(b) ? a : b),
      alignmentPolicy: down ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    return true;
  }
}

/// The Up arrow on `child` gives the focus to `target`.
class UpTo extends StatelessWidget {
  const UpTo(this.target, {super.key, required this.child});

  final FocusNode target;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
      if (event is! KeyUpEvent) target.requestFocus();
      return KeyEventResult.handled;
    },
    child: child,
  );
}
