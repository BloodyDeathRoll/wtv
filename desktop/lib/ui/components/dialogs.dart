import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// A panel over the page: a choice, more about a title, a card's menu. Back closes it.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.children, this.width, this.padding = 24, this.spacing = 0});

  final List<Widget> children;

  /// Null: as wide as its content.
  final double? width;
  final double padding;
  final double spacing;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WtvColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Container(
      width: width,
      padding: EdgeInsets.all(padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: spacing,
        children: children,
      ),
    ),
  );
}
