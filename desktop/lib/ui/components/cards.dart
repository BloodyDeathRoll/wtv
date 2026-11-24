import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'badges.dart';
import 'pressable.dart';

const _shape = BorderRadius.all(Radius.circular(8));

/// A focusable image card. Focus gives a white ring and a slight lift.
/// `label` is drawn on the image (episode cards: "Episode 2"); `onFocused`
/// lets the page header follow the focus; `progress` (0–1) draws a watched
/// bar along the bottom.
class ImageCard extends StatelessWidget {
  const ImageCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onPressed,
    required this.width,
    required this.aspectRatio,
    this.label,
    this.onFocused,
    this.progress,
    this.match,
    this.focusNode,
    this.onMenu,
  });

  /// 16:9 card for rows of titles and episodes.
  const ImageCard.landscape({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onPressed,
    this.label,
    this.onFocused,
    this.progress,
    this.match,
    this.focusNode,
    this.onMenu,
  }) : width = 200,
       aspectRatio = 16 / 9;

  /// 2:3 poster for grids of titles (a person's titles, the watchlist).
  const ImageCard.poster({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onPressed,
    this.onFocused,
    this.focusNode,
    this.onMenu,
  }) : width = 120,
       aspectRatio = 2 / 3,
       label = null,
       progress = null,
       match = null;

  /// Portrait card for a cast member.
  const ImageCard.person({super.key, required this.imageUrl, required this.title, required this.onPressed, this.label})
    : width = 96,
      aspectRatio = 3 / 4,
      onFocused = null,
      progress = null,
      match = null,
      focusNode = null,
      onMenu = null;

  final String? imageUrl;
  final String title;
  final VoidCallback onPressed;
  final double width;
  final double aspectRatio;
  final String? label;
  final VoidCallback? onFocused;
  final double? progress;

  /// WTW's "% match", in the top right corner.
  final int? match;
  final FocusNode? focusNode;

  /// Opens the card's menu (see [Pressable.onMenu]).
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // No image, or one that fails to load: the title on a plain card.
    final plain = Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ContentText(title, style: text.labelLarge!.copyWith(color: WtvColors.textSecondary), textAlign: TextAlign.center),
      ),
    );
    final url = imageUrl;
    return Pressable(
      onPressed: onPressed,
      focusNode: focusNode,
      onMenu: onMenu,
      semanticLabel: title,
      onFocusChange: (focused) {
        if (focused) onFocused?.call();
      },
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.04 : 1,
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: _shape,
                border: focused ? Border.all(color: WtvColors.focus, width: 3) : null,
              ),
              child: ClipRRect(
                borderRadius: _shape,
                child: ColoredBox(
                  color: WtvColors.surface,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // shortcut: images are kept in memory only, add a disk cache if a start with many images is slow.
                      if (url == null)
                        plain
                      else
                        Image.network(url, fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: (_, _, _) => plain),
                      if (label != null) ...[
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.55, 1],
                              colors: [Color(0x00000000), Color(0xCC000000)],
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.bottomStart,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            // Two lines at most: a cast card is narrow.
                            child: ContentText(label!, style: text.labelLarge, maxLines: 2),
                          ),
                        ),
                      ],
                      // Top right in Hebrew too, as asked.
                      if (match != null) Positioned(top: 6, right: 6, child: MatchBadge(match!, small: true)),
                      if (progress != null)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            height: 4,
                            child: ColoredBox(
                              color: const Color(0x66000000),
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: progress!.clamp(0, 1),
                                child: const ColoredBox(color: WtvColors.accent, child: SizedBox.expand()),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
