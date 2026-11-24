import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'badges.dart';

/// Where a page's header starts, under the tabs.
const headerTop = 60.0;

/// The header's height on browse pages: two rows of cards fit under it.
const headerHeight = 148.0;

/// WTW's "% match" across from a page's header, in line with its top. Goes in the page's [Stack].
class HeaderMatch extends StatelessWidget {
  const HeaderMatch(this.percent, {super.key});

  final int percent;

  @override
  Widget build(BuildContext context) => PositionedDirectional(top: headerTop, end: 64, child: MatchBadge(percent));
}

const _fade = Duration(milliseconds: 300);
const _imageWidth = 0.72;
const _imageHeight = 0.8;

/// The page background: the focused title's backdrop on the right, fading into
/// the page colour to the left and bottom, as in the reference.
class Backdrop extends StatefulWidget {
  const Backdrop(this.imageUrl, {super.key});

  final String? imageUrl;

  @override
  State<Backdrop> createState() => _BackdropState();
}

/// The new image fades in over the old one at full alpha (no dip), once it
/// has loaded; the old one goes when the fade ends.
class _BackdropState extends State<Backdrop> with SingleTickerProviderStateMixin {
  late final _in = AnimationController(vsync: this, duration: _fade, value: 1);
  late String? _shown = widget.imageUrl;
  String? _previous;

  @override
  void didUpdateWidget(Backdrop old) {
    super.didUpdateWidget(old);
    final url = widget.imageUrl;
    if (url == _shown) return;
    // Mid-fade, the half-faded image is dropped: the old one stays under.
    if (_in.value >= 0.5 || _previous == null) _previous = _shown;
    _shown = url;
    _in.value = 0;
    if (url == null) {
      _fadeIn();
    } else {
      // A failed image counts as loaded: the fade then shows the page colour.
      precacheImage(NetworkImage(url), context, onError: (_, _) {}).then((_) {
        if (mounted && _shown == url) _fadeIn();
      });
    }
  }

  void _fadeIn() => _in.forward().whenComplete(() {
    if (mounted) setState(() => _previous = null);
  });

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    // The image sits at the end (right in English, left in Hebrew); the fade starts from the other side.
    alignment: AlignmentDirectional.topEnd,
    child: FractionallySizedBox(
      widthFactor: _imageWidth,
      heightFactor: _imageHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Keyed by address, so an image keeps its place as it goes from new to old.
          for (final url in {?_previous, ?_shown})
            Image.network(
              url,
              key: ValueKey(url),
              fit: BoxFit.cover,
              alignment: AlignmentDirectional.topEnd,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              opacity: url == _shown && url != _previous
                  ? _in
                  : _shown == null
                  ? ReverseAnimation(_in) // fading out to nothing
                  : null,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          // The fades are laid out on the whole page; this box is its top-end part.
          // They reach a little past the image where they are solid: on a box edge that
          // falls inside a pixel, the image would show through as a thin line.
          const PositionedDirectional(
            start: -1,
            top: 0,
            end: 0,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional(-(2 * (1 - _imageWidth) / _imageWidth + 1), 0),
                  end: AlignmentDirectional.centerEnd,
                  stops: [0, 0.32, 0.62, 1],
                  colors: [WtvColors.background, WtvColors.background, Color(0x590F171E), Color(0x000F171E)],
                ),
              ),
            ),
          ),
          const PositionedDirectional(
            start: -1,
            top: 0,
            end: 0,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45 / _imageHeight, 1],
                  colors: [Color(0x000F171E), WtvColors.background],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The header text block: title, highlight line, meta row, synopsis, and an
/// optional row of actions (title pages only). The caller sets the width.
class HeroText extends StatelessWidget {
  const HeroText({
    super.key,
    required this.title,
    required this.meta,
    required this.synopsis,
    this.titleMaxLines = 2,
    this.highlight,
    this.actions,
  });

  final String title;
  final Widget meta;
  final String? synopsis;
  final int titleMaxLines;
  final String? highlight;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ContentText(title, style: text.displayMedium, maxLines: titleMaxLines),
        if (highlight != null) ...[
          const SizedBox(height: 6),
          Text(highlight!, style: text.titleSmall!.copyWith(color: WtvColors.accent)),
        ],
        const SizedBox(height: 8),
        meta,
        if (synopsis != null) ...[
          const SizedBox(height: 8),
          ContentText(synopsis!, style: text.bodyLarge!.copyWith(color: WtvColors.textSecondary), maxLines: 3),
        ],
        if (actions != null) ...[const SizedBox(height: 20), actions!],
      ],
    );
  }
}

/// "2026   Crime • Drama   [TV-MA]": plain items, then badges.
class MetaRow extends StatelessWidget {
  const MetaRow({super.key, required this.items, this.badges = const [], this.tag});

  final List<String> items;
  final List<String> badges;
  final String? tag;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 14,
    children: [
      if (tag != null) Tag(tag!),
      for (final item in items) Text(item, style: Theme.of(context).textTheme.titleSmall),
      for (final badge in badges) TextBadge(badge),
    ],
  );
}

/// A row title above a row of cards.
class RowTitle extends StatelessWidget {
  const RowTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
