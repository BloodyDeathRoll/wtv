import 'package:intl/intl.dart' as intl;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';

/// A text from the catalog (a name, a synopsis). Its direction follows the
/// text itself, so an English synopsis in the Hebrew layout keeps its full
/// stop at the end (the TV app's `TextDirection.Content`).
class ContentText extends StatelessWidget {
  const ContentText(this.text, {super.key, this.style, this.maxLines, this.textAlign});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style,
    maxLines: maxLines,
    textAlign: textAlign,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    // A text with no letters (a year) keeps the layout's direction.
    textDirection: intl.Bidi.hasAnyRtl(text) || intl.Bidi.hasAnyLtr(text)
        ? (intl.Bidi.startsWithRtl(text) ? TextDirection.rtl : TextDirection.ltr)
        : null,
  );
}

Widget _box(Color color, double radius, EdgeInsets padding, Widget child) => DecoratedBox(
  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
  child: Padding(padding: padding, child: child),
);

/// Age rating or format badge: "TV-14", "16+", "4K".
class TextBadge extends StatelessWidget {
  const TextBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => _box(
    WtvColors.badge,
    4,
    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

/// WTW's "92% match", as WTW shows it; `small` on cards.
class MatchBadge extends StatelessWidget {
  const MatchBadge(this.percent, {super.key, this.small = false});

  final int percent;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dot = small ? 6.0 : 8.0;
    return _box(
      const Color(0xCC000000),
      small ? 4 : 6,
      EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 2 : 5),
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: small ? 4 : 6,
        children: [
          Container(width: dot, height: dot, decoration: const BoxDecoration(color: WtvColors.accent, shape: BoxShape.circle)),
          Text(AppLocalizations.of(context)!.wtwMatch(percent), style: small ? text.labelSmall : text.titleSmall),
        ],
      ),
    );
  }
}

/// Light tag in front of the meta line: "TRENDING", "NEW".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => _box(
    WtvColors.tag,
    4,
    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelMedium!.copyWith(color: WtvColors.onTag)),
  );
}
