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
  const ImageCard.person({super.key, required this.imageUrl, required this.title, required this.onPressed, this.label, this.focusNode})
    : width = 96,
      aspectRatio = 3 / 4,
      onFocused = null,
      progress = null,
      match = null,
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

/// A live channel: its logo (or its name, when there is none or it does not
/// load) on a plain card, the provider's number in the corner, a star when it
/// is a favourite, and under the name the programme on now (null while
/// unknown or without a guide). The card fills the width it is given.
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.logo,
    required this.name,
    required this.number,
    required this.favorite,
    required this.onPressed,
    this.onNow,
    this.onMenu,
    this.focusNode,
  });

  final String? logo;
  final String name;
  final int? number;
  final bool favorite;
  final VoidCallback onPressed;
  final String? onNow;

  /// Opens the channel's menu (see [Pressable.onMenu]).
  final VoidCallback? onMenu;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onNow = this.onNow;
    Widget now() => ContentText(onNow!, style: text.labelSmall!.copyWith(color: WtvColors.accent), maxLines: 1);
    const under = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
    final plain = Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ContentText(name, style: text.titleSmall, textAlign: TextAlign.center, maxLines: 2),
          ),
        ),
        if (onNow != null) Align(alignment: Alignment.bottomCenter, child: Padding(padding: under, child: now())),
      ],
    );
    final logo = this.logo;
    return Pressable(
      onPressed: onPressed,
      focusNode: focusNode,
      onMenu: onMenu,
      semanticLabel: name,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.04 : 1,
        duration: const Duration(milliseconds: 150),
        child: AspectRatio(
          aspectRatio: 16 / 9,
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
                    if (logo == null)
                      plain
                    else
                      Image.network(
                        logo,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => plain,
                        // The name goes under a logo that loaded: without one it is the card's middle.
                        frameBuilder: (_, image, _, _) => Stack(
                          fit: StackFit.expand,
                          children: [
                            Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, onNow != null ? 46 : 30), child: image),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: under,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ContentText(name, style: text.labelMedium!.copyWith(color: WtvColors.textSecondary), maxLines: 1),
                                    if (onNow != null) now(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (number != null)
                      Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('$number', style: text.labelSmall!.copyWith(color: WtvColors.textMuted)),
                        ),
                      ),
                    if (favorite)
                      const Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.star, size: 18, color: WtvColors.accent)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
